"""W2 card A1: the Windows-mode smoke on VGS-VM02 as each gate account. The guest agent runs as SYSTEM in session 0,
where Start-Process -Credential is refused, so each run is a one-shot scheduled task registered with the account's
credential, run, read back and deleted. Passwords come from the predecessor's dev.local, travel only inside the
encoded command, and are never printed. The command and output files live in C:\\Users\\Public: the gate accounts have only
read and execute on the site folder, so a redirect into tools\\smoke fails with exit 1 and no output (found 2026-09-12).
The accounts also need SeBatchLogonRight on VM02 (granted with secedit, 2026-09-12; without it schtasks warns at create
and the task never starts, last result 267011). Nothing persists on VM02 after a run (task deleted, files removed)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pve
env = {}
for line in open(r"C:\Projects\PnCPlatform\dev.local", encoding="utf-8"):
    if "=" in line and not line.startswith("#"): k, v = line.split("=", 1); env[k.strip()] = v.strip()
RUNS = [("pnc-gate-admin", "PNC_GATE_ADMIN_PWD", "Administrator"), ("pnc-gate-approver", "PNC_GATE_APPROVER_PWD", "Approver"), ("pnc-gate-ro", "PNC_GATE_RO_PWD", "ReadOnly"), ("pnc-gate-hydro", "PNC_GATE_HYDRO_PWD", "Hydro")]
only = sys.argv[1:]
TOOLS = "C:/inetpub/PnCPlatform_V2/tools/smoke"
p = pve.Pve()
for sam, key, mode in RUNS:
    if only and mode not in only: continue
    pwd = env[key].replace("'", "''")
    task = f"PnC W2 gate {mode}"
    script = f"""$ErrorActionPreference = 'Continue'; $ProgressPreference = 'SilentlyContinue'
$tools = '{TOOLS}'; $out = "C:/Users/Public/pnc-gate-{mode}.txt"; $cmd = "C:/Users/Public/pnc-gate-{mode}.cmd"
Remove-Item $out -Force -ErrorAction SilentlyContinue
$exe = ($tools -replace '/', [string][char]92) + [char]92 + 'PnC.Api.Smoke.exe'
$outw = ($out -replace '/', [string][char]92)
Set-Content -Path $cmd -Value ('@"' + $exe + '" https://vgs-vm02.vgsot.internal:8443 - --windows={mode} > "' + $outw + '" 2>&1') -Encoding Ascii
$cmdw = ($cmd -replace '/', [string][char]92)
$user = 'VGSOT' + [char]92 + '{sam}'
$r = & schtasks.exe /create /tn '{task}' /tr $cmdw /sc once /st 23:59 /ru $user /rp '{pwd}' /rl limited /f 2>&1
"CREATE: " + (($r | Out-String).Trim() -replace '{pwd}', '***')
$r = & schtasks.exe /run /tn '{task}' 2>&1; "RUN: " + ($r | Out-String).Trim()
$done = $false
for ($i = 0; $i -lt 60; $i++) {{
  Start-Sleep -Seconds 5
  $q = & schtasks.exe /query /tn '{task}' /fo list /v 2>&1 | Out-String
  if ($q -notmatch 'Status:\\s+Running') {{ $done = $true; break }}
}}
$q = & schtasks.exe /query /tn '{task}' /fo list /v 2>&1 | Out-String
"TASK: finished=$done; " + (($q -split "`r?`n" | Where-Object {{ $_ -match '^(Status|Last Run Time|Last Result):' }}) -join '; ')
if (Test-Path $out) {{ "OUTPUT:"; Get-Content $out }} else {{ "OUTPUT: none written" }}
$r = & schtasks.exe /delete /tn '{task}' /f 2>&1; "DELETE: " + ($r | Out-String).Trim()
Remove-Item $out, $cmd -Force -ErrorAction SilentlyContinue
"CLEAN: task and files removed: $(-not (Test-Path $cmd))"
"""
    print(f"=== {sam} --windows={mode}")
    code, out, err = p.ps(pve.VM02, script, timeout=600)
    print(out)
    if err: print("PSERR:", err[:1500])
