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

## Decided

The owner runs steps 2–7 by hand on the VM (#91), the way the predecessor's installs were done. When
the site answers, this session verifies from the laptop: `/health` over the Tailscale path is **not**
expected to answer (Business → OT allows SQL only); the observation is the VM07 smoke output the owner
pastes into the next card, and the `AccessRefused` and `SignIn`-shaped rows in `audit.vActionLog` on
`_V2_DEV`, which this session can read.
