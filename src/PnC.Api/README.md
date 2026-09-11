# PnC.Api — running it on the build laptop

The design is `docs/design/API.md`. This is only how to start it locally.

Two things must both be true for the DEV identity header to work: `Auth:Mode = Development` in the
gitignored `appsettings.Local.json`, **and** the environment name `DEV`. The host defaults to
`Production`, and in Production with Development mode it now refuses to start (W1 card T1).

**PowerShell** (the shell on this laptop — `set X=Y` is `cmd` syntax and does nothing here):

```powershell
cd src\PnC.Api
$env:ASPNETCORE_ENVIRONMENT = 'DEV'
dotnet run --urls http://127.0.0.1:5210
```

**cmd:** `set ASPNETCORE_ENVIRONMENT=DEV` then the same `dotnet run`.

Expected first log line: `PnC.Api DEV: catalogue 497 procedures, 375 views across 21 schemas; auth mode Development`
(counts as of W1). Then http://127.0.0.1:5210/ shows the platform panel and *not signed in*; the
browser sends no identity header, so the catalogue stays empty. The signed-in paths are exercised by
the smoke:

```powershell
dotnet run --project ..\PnC.Api.Smoke -- http://127.0.0.1:5210 "<the dev_pnc connection string>"
```

`appsettings.Local.json` (gitignored, never published):

```json
{ "Database": { "ConnectionString": "Server=10.10.70.25;Database=PnCPlatform_V2_DEV;User ID=dev_pnc;Password=...;TrustServerCertificate=true;Encrypt=true" },
  "Auth": { "Mode": "Development" } }
```
