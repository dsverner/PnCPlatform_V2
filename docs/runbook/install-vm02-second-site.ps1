<#
docs/runbook/VM02-SECOND-SITE.md, steps 2–7, as one idempotent script to run ON VGS-VM02 in an
elevated PowerShell (5.1 is fine). Decision #89 / #91. Nothing here touches the predecessor's site.

Before running, copy to the VM:
  PnC.Api-0.1.0.zip   (dist/0.1.0; SHA-256 in dist/0.1.0/release.json)
and put its path in -PackageZip below. The script:
  2. unpacks the package to C:\inetpub\PnCPlatform_V2
  3. writes appsettings.Local.json (V2 database, Windows mode, UPN suffix)
  4. creates app pool PnCPlatformV2 (No Managed Code, identity VGSOT\svc-pncapi) and site PnCPlatform_V2
     bound https *:8443 (no host header, as the predecessor's *:443), Windows auth on, anonymous off except /health
  5. reuses the certificate already bound on :443 (the predecessor's self-signed one)
  6. host firewall: allow TCP 8443 inbound from 10.10.70.21 (VGS-VM07)
  7. calls /health on the new site (certificate check skipped: VM02 does not trust its own certificate)
Then, from VGS-VM07 as VGS01 and VGS99:
  PnC.Api.Smoke.exe https://vgs-vm02.vgsot.internal:8443 - --windows=Administrator
  PnC.Api.Smoke.exe https://vgs-vm02.vgsot.internal:8443 - --windows=ReadOnly
#>
param(
    [Parameter(Mandatory = $true)] [string] $PackageZip,
    [string] $SiteName = 'PnCPlatform_V2',
    [string] $PoolName = 'PnCPlatformV2',
    [string] $PhysicalPath = 'C:\inetpub\PnCPlatform_V2',
    [string] $HostName = 'vgs-vm02.vgsot.internal',
    [int]    $Port = 8443,
    [string] $PoolIdentity = 'VGSOT\svc-pncapi',
    [string] $AllowFrom = '10.10.70.21',
    [string] $SqlServer = '10.10.70.25',
    [string] $Database = 'PnCPlatform_V2_DEV'
)
$ErrorActionPreference = 'Stop'
Import-Module WebAdministration

# The pool identity's password is asked for here and never written anywhere.
$cred = Get-Credential -UserName $PoolIdentity -Message "Password for the app pool identity $PoolIdentity"

# 2. package
if (-not (Test-Path $PackageZip)) { throw "package not found: $PackageZip" }
$hash = (Get-FileHash $PackageZip -Algorithm SHA256).Hash.ToLower()
Write-Host "package $PackageZip sha256 $hash  (compare with dist/0.1.0/release.json)"
New-Item -ItemType Directory -Force $PhysicalPath | Out-Null
Expand-Archive -Path $PackageZip -DestinationPath $PhysicalPath -Force
if (-not (Test-Path (Join-Path $PhysicalPath 'PnC.Api.dll'))) { throw "PnC.Api.dll not found under $PhysicalPath after unpack" }
Write-Host "2. unpacked to $PhysicalPath"

# 3. local settings — the only file that names the database; Windows mode; UPN suffix (#85, #89)
$local = @{
    Database = @{ ConnectionString = "Server=$SqlServer;Database=$Database;Integrated Security=true;TrustServerCertificate=true;Encrypt=true;Application Name=PnC.Api" }
    Auth     = @{ Mode = 'Windows'; UpnSuffix = 'vgsot.internal' }
} | ConvertTo-Json -Depth 3
Set-Content -Path (Join-Path $PhysicalPath 'appsettings.Local.json') -Value $local -Encoding utf8
Write-Host "3. appsettings.Local.json written ($Database, Windows mode)"

# 4. app pool and site
if (-not (Test-Path "IIS:\AppPools\$PoolName")) {
    New-WebAppPool -Name $PoolName | Out-Null
    Set-ItemProperty "IIS:\AppPools\$PoolName" managedRuntimeVersion ''            # No Managed Code
    Write-Host "4a. app pool $PoolName created"
} else { Write-Host "4a. app pool $PoolName exists" }
Set-ItemProperty "IIS:\AppPools\$PoolName" -Name processModel -Value @{ userName = $cred.UserName; password = $cred.GetNetworkCredential().Password; identityType = 'SpecificUser' }

if (-not (Get-Website -Name $SiteName -ErrorAction SilentlyContinue)) {
    New-Website -Name $SiteName -PhysicalPath $PhysicalPath -ApplicationPool $PoolName -Port $Port -Ssl | Out-Null
    Write-Host "4b. site $SiteName created on https :$Port $HostName"
} else { Write-Host "4b. site $SiteName exists" }
Set-WebConfigurationProperty -PSPath "IIS:\" -Location $SiteName -Filter 'system.webServer/security/authentication/anonymousAuthentication' -Name enabled -Value $false
Set-WebConfigurationProperty -PSPath "IIS:\" -Location $SiteName -Filter 'system.webServer/security/authentication/windowsAuthentication' -Name enabled -Value $true
Write-Host "4c. Windows authentication on, anonymous off"
# /health carries no identity by design (API.md §7); with anonymous off site-wide IIS answers 401.2 before the app.
# The section is locked against web.config overrides, so it is set in applicationHost.config for this one path.
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location "$SiteName/health" -Filter 'system.webServer/security/authentication/anonymousAuthentication' -Name enabled -Value $true
Write-Host "4d. anonymous allowed at /health only"

# 5. certificate: the one already bound on :443
$existing = Get-ChildItem IIS:\SslBindings | Where-Object { $_.Port -eq 443 } | Select-Object -First 1
if (-not $existing) { throw "no SSL binding on :443 to take the certificate from; bind a certificate on :$Port by hand" }
$thumb = $existing.Thumbprint
$store = if ($existing.Store) { $existing.Store } else { 'My' }
$sslPath = "IIS:\SslBindings\0.0.0.0!$Port"
if (-not (Test-Path $sslPath)) {
    Get-Item "Cert:\LocalMachine\$store\$thumb" | New-Item $sslPath | Out-Null
}
Write-Host "5. certificate $thumb (from :443) bound on :$Port"

# 6. host firewall
$ruleName = "PnC Platform V2 API $Port from VGS-VM07"
if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort $Port -RemoteAddress $AllowFrom -Action Allow -Profile Domain | Out-Null
    Write-Host "6. firewall rule '$ruleName' created"
} else { Write-Host "6. firewall rule exists" }

# 7. health, from the VM itself (its own certificate is not trusted here — skipped for this call only)
Restart-WebAppPool -Name $PoolName
Start-Sleep -Seconds 3
$prev = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
try {
    $health = Invoke-RestMethod -Uri "https://${HostName}:$Port/health" -UseBasicParsing
    Write-Host ("7. /health → environment {0}, release {1}, database {2}" -f $health.environment, $health.release, $health.database)
} finally { [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $prev }
Write-Host "Done. Next, from VGS-VM07: PnC.Api.Smoke.exe https://${HostName}:$Port - --windows=Administrator  (and --windows=ReadOnly)"
