# Relocation rehearsal - release 0.8.1

2026-09-13T17:40:41.238392+00:00 · API from the smoke logs: C:\Users\DAREN~1.LAP\AppData\Local\Temp/claude/gate-0.8.1-qa-split/smoke-administrator.log, C:\Users\DAREN~1.LAP\AppData\Local\Temp/claude/gate-0.8.1-qa-split/smoke-readonly.log · database PnCPlatform_V2_QA · environment QA

| Step | Item | Outcome | Detail |
|---|---|---|---|
| 1 | OT VMs joined to the OT domain | observed | vgs-vm02.vgsot.internal:8443 as pnc-gate-admin@vgsot.internal (Windows/Administrator) against https://vgs-vm02.vgsot.internal:8443 at 2026-09-13T17:38:42+00:00; vgs-vm02.vgsot.internal:8443 as None (Windows/ReadOnly) against https://vgs-vm02.vgsot.internal:8443 at 2026-09-13T17:38:42+00:00 |
| 2 | Service account holds app_execute; users by domain account | observed | Windows identities signed in with roles ['Administrator', 'ReadOnly'] |
| 3 | Release package installed (hashes, /health release, no developer configuration) | pass |  |
| 4 | Firewall configured from the register (Phase 1 flows only) | not-applicable | an infrastructure act; the register is docs/PLATFORM-ARCHITECTURE.md section 1.2 |
| 5 | Temporary Business -> OT rule closed | pass | 10.10.70.20:8443: timed out (filtered — no route or a host firewall without an allow for this source) |
| 6 | User-journey smoke (Windows/Administrator on vgs-vm02.vgsot.internal:8443) | pass | SMOKE PASS: 81 passed, 0 failed, 10 skipped |
| 6 | User-journey smoke (Windows/ReadOnly on vgs-vm02.vgsot.internal:8443) | pass | SMOKE PASS: 44 passed, 0 failed, 10 skipped |
| 6 | Feed pull (F3) completes | not-applicable | no feed in Phase 1 (F3 arrives with the integration phase); nothing to pull |
| 7 | Run recorded as a PlatformDeployment record | pass | F185FDCA-7510-46D5-95BD-18EA72C2E6EC (written from the build machine through record.Record_Add / CharacteristicValue_Add as the SYSTEM actor: no API path from Business, by the register) |

Record: `F185FDCA-7510-46D5-95BD-18EA72C2E6EC` (PlatformDeployment, subject Platform). Result: **PASS**.

Steps marked not-applicable are infrastructure acts (section 1.4 items 1, 2, 4, 5) that a QA run on the OT mimic must perform by hand and re-run this script against.
