# VGS-VM02 — the V2 API as a second IIS site (decision #89)

**2026-09-11. Steps 1 and the identities of step 7 are done; steps 2–7 are the owner's, by hand (decision #91).** What installing the V2 API next to the predecessor's site
involves, with what the predecessor's record does and does not say. Every "recorded" fact below was
read this session in `C:\Projects\PnCPlatform`; every **not recorded** is a gap the install has to
close by looking at the VM itself.

## What is on VM02 today (recorded)

| Fact | Source |
|---|---|
| Windows 11 Pro, joined to `vgsot.internal`, IIS + ASP.NET Core Hosting Bundle **10.0.11**, the predecessor's release only | `docs/reference/dev-environment.md:16` |
| Site on **443 only**, hostname `vgs-vm02.vgsot.internal`, app pool identity `VGSOT\svc-pncapi`, Windows authentication only | `docs/PLATFORM-ARCHITECTURE.md:109`, `_handoff.md:34` |
| Physical path `C:\inetpub\PnCPlatform`; the package arrives as an ISO attached to the VM and is unpacked there, keeping `appsettings.QA.json` | `_handoff.md:163` |
| The site's certificate is **self-signed**; VM07 trusts it, VM02 itself does not | `docs/PLATFORM-ARCHITECTURE.md:116`, `_handoff.md:167` |
| The laptop reaches the VM through the **Proxmox API and the QEMU guest agent** (`pve-ryzen`, VM id 101), not WinRM or RDP; a domain-user action is a scheduled task with `/ru` | `docs/working-agreements/qa-environment.md:21-23`, `_handoff.md:29` |
| `web.config` from `dotnet publish` (`AspNetCoreModuleV2`, in-process); it sets **no** environment variable | `dist/0.10.10/app/web.config` |
| Firewall register row F1: Application VM → Application server, HTTPS **443**; within OT, host allow-listing only | `docs/PLATFORM-ARCHITECTURE.md:76` |

**Not recorded anywhere:** the IIS site name and app pool name; how the certificate was issued
(no thumbprint, PFX or command); how `ASPNETCORE_ENVIRONMENT=QA` is set on the site; the exact
`CREATE USER` run on `PnCPlatform_QA`; the host firewall commands; how `PnC.Api.Smoke.exe` reached
VM07.

## The install, step by step

Steps 2–7 are also one script, `install-vm02-second-site.ps1` beside this file, to run on the VM in an
elevated PowerShell with the package's path; it asks for the pool identity's password and writes it
nowhere. Running it from the laptop through the Proxmox guest agent was attempted on 2026-09-11 and
stopped by this session's permission mode (remote execution on the OT server); it stays the owner's
to run, or the owner allows that path.

1. **Database (VM01)** — **done** by the owner 2026-09-11 (card round 2 G1) and verified by query: `app_execute` on `_V2_DEV` holds `VGSOT\svc-pncapi`.
   ```sql
   USE PnCPlatform_V2_DEV;
   CREATE USER [VGSOT\svc-pncapi] FOR LOGIN [VGSOT\svc-pncapi];
   ALTER ROLE [app_execute] ADD MEMBER [VGSOT\svc-pncapi];
   ```
   Verified 2026-09-11 (read): `PnCPlatform_QA` holds this user in `app_execute`; `_V2_DEV` has the
   role and not the user. `deploy.py` already passes `DoNotDropObjectTypes=Users;Logins;RoleMembership;Permissions`
   so a republish keeps it (the predecessor lost it once, `deploy.py:69-73`).
2. **Package to the VM** — `dist/0.1.0/PnC.Api-0.1.0.zip` (SHA-256 in `dist/0.1.0/release.json`)
   by the recorded route: an ISO attached through Proxmox, unpacked to **`C:\inetpub\PnCPlatform_V2`**
   (a new folder; the predecessor's stays).
3. **Settings on the VM** — `appsettings.Local.json` is never shipped. The site needs a local file
   with the V2 database and Windows mode; the predecessor's site keeps an `appsettings.QA.json`, and
   the V2 host reads `appsettings.Local.json` only, so the file is:
   ```json
   { "Database": { "ConnectionString": "Server=10.10.70.25;Database=PnCPlatform_V2_DEV;Integrated Security=true;TrustServerCertificate=true;Encrypt=true;Application Name=PnC.Api" },
     "Auth": { "Mode": "Windows", "UpnSuffix": "vgsot.internal" } }
   ```
   `ASPNETCORE_ENVIRONMENT` is left unset: the host defaults to Production, and Windows mode does
   not need DEV (#85, #90).
4. **IIS** — a new app pool `PnCPlatformV2` (No Managed Code, identity `VGSOT\svc-pncapi`, the same
   account as the predecessor's pool so the Kerberos SPN `HTTP/vgs-vm02.vgsot.internal` still
   applies); a new site `PnCPlatform_V2`, physical path from step 2, binding **https, port 8443,
   hostname `vgs-vm02.vgsot.internal`**, Windows Authentication enabled and Anonymous disabled.
5. **Certificate** — reuse the existing site's self-signed certificate on the 8443 binding (same
   hostname, and VM07 already trusts it). If the thumbprint cannot be found on the VM, a new
   self-signed certificate means a new trust step on VM07; recorded as a mimic deviation either way
   (D5, #89: a trusted certificate arrives with W8).
6. **Host firewall** — an inbound allow for TCP 8443 from `10.10.70.21` (VM07) on VM02, the same
   shape as the 443 rule the register describes. The UniFi gateway sees none of this (both hosts
   are in OT). Register row F1 gains `8443` for the V2 site.
7. **Verify from VM07** — `https://vgs-vm02.vgsot.internal:8443/health` in the browser, then the
   Windows-mode smoke as VGS01 and VGS99:
   ```
   PnC.Api.Smoke.exe https://vgs-vm02.vgsot.internal:8443 - --windows=Administrator
   PnC.Api.Smoke.exe https://vgs-vm02.vgsot.internal:8443 - --windows=ReadOnly
   ```
   `security.User` rows for `VGS01@vgsot.internal` (Administrator, Global) and `VGS99@vgsot.internal`
   (ReadOnly, Global) **exist on `_V2_DEV`** — seeded through the procedures as the SYSTEM actor on
   2026-09-11 (G3, #91), each person noted as a W1 gate fixture. W2 replaces them with the real model.
8. **Record** — `platform.Deployment` for the V2 database (deploy.py does this on the schema side);
   the W1 gate record in `PHASE-1-WORKFLOW.md` gets the observed result.

## Done through the Proxmox guest agent, 2026-09-11 (session run as claude-rw@pve)

Observed on the VM, step by step: the package landed in 82 chunks and its SHA-256 matched `release.json`
(`23d92d61…4047e`); unpacked to `C:\inetpub\PnCPlatform_V2` (31 files, no local settings shipped);
`appsettings.Local.json` written; pool `PnCPlatformV2` cloned from the predecessor's with `appcmd` so the
identity `VGSOT\svc-pncapi` carried over without its password being handled; site `PnCPlatform_V2` on
`https *:8443` (no host header, matching the predecessor's `*:443`) with certificate `E1443DF1…B51DAE`;
Windows auth on, anonymous off; firewall rule *PnC F1 HTTPS 8443 from Application VM (V2)*, TCP 8443 from
10.10.70.21. HTTP.sys shows the certificate on both ports. `curl -k` from the VM reached IIS on 8443 and got
**401.2 on `/health`** — IIS authenticates every caller, as on the predecessor's site; a per-path anonymous
location was tried and sent `/health` to the static-file handler (404.0), so it was removed. With Negotiate
(`curl -k --negotiate -u :` as SYSTEM) the request reached the app and exposed the real fault: **500.30, the
app failed at start** — `api-permissions.json` names `platform.Release_Append` and `platform.Deployment_Append`
as not callable, and under `app_execute` those procedures are invisible in `sys.procedures` (no rights on the
`platform` schema, `Roles.sql`), so the start-up validation refused a map that was correct. Fixed in code:
only entries that make a procedure *callable* must exist; not-callable entries naming unseen procedures are
logged. Lesson for every wave: the catalogue the app sees is the identity's, not `db_owner`'s.
PowerShell 5.1's own web client on VM02 fails the TLS handshake to the site (the predecessor's note about
VM02 and its own certificate); `curl.exe` with `-k` is the check that works there.

## Outcome, 2026-09-11

**Browser from VM07, first try:** Edge prompted for credentials on 8443 and refused VGS01's correct
password; the IIS log showed 401.2 three times per attempt. Cause, read from both sites' configuration:
the predecessor's site has `useAppPoolCredentials=True`, the new one had the default `False`. Kerberos
tickets for `HTTP/vgs-vm02.vgsot.internal` are issued to the pool identity, so kernel-mode Windows
authentication must use the pool's credentials to decrypt them. Set on `PnCPlatform_V2`, pool restarted,
the machine-account check still answers the API's own 401. The install script carries it as step 4d.

#91 was overtaken: the owner allowed the Proxmox path and this session did steps 2–7 through the
guest agent (the by-hand script stays valid and idempotent). After the redeploy of the package built
from 348a631, observed on VM02 with `curl -k --negotiate -u :` as SYSTEM: **`/health` → 200**
`{"environment":"QA","release":"0.1.0","database":"ok"}`; **`/api/v1/me` → the API's own 401**
*Identity is not a platform user* for the machine account; `/` → 200; with no credentials IIS answers
401. Still owed for the gate: the VM07 vantage point as VGS01 and VGS99 — VM07's guest agent answers a
ping but times out on commands, so that is the owner's, on the round-3 test card. The `AccessRefused`
row the ReadOnly write check leaves in `audit.vActionLog` is what this session reads back afterwards.
(The API writes no sign-in rows.)

## W8, 2026-09-13 — the site repointed to `PnCPlatform_V2_QA` (decision #149)

- `PnCPlatform_V2_QA` was created fresh on VM01 by `deploy.py --database PnCPlatform_V2_QA --fresh --package dist/0.8.0`
  (schema smoke PASS); the four gate accounts became its users through `tools/ot/gate_users.py`; the site's
  `appsettings.Local.json` now names the QA database (the DEV copy is kept as `pkgppsettings.Local.json.dev-0.7.0`).
- **Found on the first start against QA: 500.30.** A fresh database has no user for the pool identity — `deploy.py`
  keeps users, logins and role membership on a republish, but a `--fresh` database starts with none, and the owner's
  2026-09-11 grant of `app_execute` to `VGSOT\svc-pncapi` was on `_V2_DEV` only. Fixed by `CREATE USER [VGSOT\svc-pncapi]
  FROM LOGIN …` and `ALTER ROLE app_execute ADD MEMBER` on QA (the login already exists on the server); `/health` then
  answered `environment QA, release 0.8.0, database ok`. Every fresh V2 database needs this step; `gate_users.py` does
  not do it (it is a server-login mapping, not platform data) — recorded here so PROD's first start does not repeat it.
- In Windows mode the definitions arrive over several gate passes: the Administrator run loads the lifecycle workflow
  (Draft), the Approver run approves it, the next Administrator run loads the procedure and the request workflow, the
  next Approver approves them. A fresh database therefore takes three Administrator → Approver passes before every
  gate check can pass (the DEV-mode smoke does it in one process with both identities).
- VM02 and VM07 were **not** rebuilt for QA (the workflow's §4 assumption, overturned: a VM rebuild is infrastructure
  this session cannot perform); the predecessor's site on 443 still stands beside the V2 site on 8443. On the W8 card.

## The smoke as a share for VM07, 2026-09-13 (W8 card E, #153)

The owner's first try from VM07 used the administrative share (`\vgs-vm02\C$\…`) and got *network path not found*
as VGS01. `C:\inetpub\PnCPlatform_V2	ools\smoke` is now the read-only SMB share **`\vgs-vm02\pncsmoke`** (VGSOT\Domain
Users, READ), so from VM07:

```
\vgs-vm02\pncsmoke\PnC.Api.Smoke.exe https://vgs-vm02.vgsot.internal:8443 - --windows=Administrator > %USERPROFILE%\smoke-vm07.log
```

Reversible: `Remove-SmbShare pncsmoke`. The share carries only the smoke's binaries; the site folder's own permissions are unchanged.

**Found on the first run from VM07 (2026-09-13 evening):** *You must install .NET to run this application* — VM07 has no
.NET runtime, so the framework-dependent build the share first held cannot run there. The share now points at
`tools\smoke-sc`, the package's **self-contained** single-file build (`dist/<version>/tools/PnC.Api.Smoke`, 84 MB,
zipped to 35 MB for the transfer); `tools\smoke` (framework-dependent, 5 MB) stays for the gate tasks on VM02, which
carries the shared runtime. Nothing is installed on VM07.

## Gate tooling on VM02, 2026-09-12 (W2 card A1, decision #97)

- `C:\inetpub\PnCPlatform_V2\tools\smoke\` holds the framework-dependent `PnC.Api.Smoke` of the current
  package (`pkg\smoke-fdd.zip`, unpacked); `pkg\` keeps every package zip transferred, hash-verified.
- The site's certificate (thumbprint `E1443DF1…B51DAE`, the same self-signed one VM07 trusts) is in
  VM02's `LocalMachine\Root`, so the smoke on VM02 validates TLS. Reversible: remove it from that store.
- A gate run: `python tools\ot\gate_runs.py [Administrator] [ReadOnly] [Hydro]` from the laptop registers a
  one-shot scheduled task on VM02 as the gate account (`schtasks /ru VGSOT\pnc-gate-… /rl limited`), runs it,
  reads the output back and deletes task, command file and output. The passwords never leave the laptop's
  `dev.local` except inside the encoded command. `Start-Process -Credential` from the agent's SYSTEM session
  is refused ("Access is denied"), which is why the task exists at all.
- Two host facts the run depends on, found 2026-09-12 when the first runs produced nothing:
  - **The gate accounts hold *Log on as a batch job* (`SeBatchLogonRight`)** — without it `schtasks /create`
    warns *Batch logon privilege needs to be enabled for the task principal* and the task never starts (last
    result 267011). Granted with `secedit /configure` from an exported `USER_RIGHTS` template that appends the
    three SIDs (`…-1604`, `…-1605`, `…-1606`) to the existing holders (Administrators, Backup Operators,
    Performance Log Users, IIS_IUSRS); verified by re-export. Reversible: the same template without them.
  - **The run's command and output files are in `C:\Users\Public`**, not in `tools\smoke`: the accounts have
    `BUILTIN\Users` read and execute on `C:\inetpub\PnCPlatform_V2`, so a redirect into it fails (exit 1, no file).
- **W3, 2026-09-12:** a fourth account, `pnc-gate-approver` (Administrator, Global; SID `…-1607`, batch-logon right
  granted the same way), so the Author/Approve segregation can be observed on the Windows path: the Administrator run
  authors a Draft, the Approver run approves it. 0.3.0 deployed the same way as 0.2.1 (stop pool, keep
  `appsettings.Local.json`, expand, restart) — `/health` → `release 0.3.0`; runs: admin 49, approver 8, read-only 10,
  hydro 6 PASS.
- First full run 2026-09-12 09:42–09:45: Administrator 31 PASS, ReadOnly 9 PASS, Hydro 6 PASS (after the smoke's
  role-list check was corrected to expect the engineer's 403); recorded in `PHASE-1-WORKFLOW.md`, W2.
- The three gate accounts are platform users on `_V2_DEV` (Administrator Global, ReadOnly Global,
  PCEngineer on *Generation · Hydro*); `VGS01` / `VGS99` stay from W1 (#91) but are no longer gate fixtures.
