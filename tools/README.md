# `tools/` — repository-level tooling

| Script | What |
|---|---|
| `rehearse_relocation.py` | the relocation checklist (PLATFORM-ARCHITECTURE §1.4, decision 253) as a runnable against a deployed release: performs steps 3, 6, 7, reports 1, 2, 4, 5; writes the `PlatformDeployment` record and `dist/<version>/REHEARSAL-<date>.md`; exit 1 on a failed step |
| `ot/pve.py` | the Proxmox path to the OT hosts (API + QEMU guest agent as `claude-rw@pve`, credentials from the predecessor's `dev.local`, never printed): inventory, chunked hash-verified file transfer, run a PowerShell script in a guest, a shell line in a Linux guest, reboot a VM whose agent has stopped answering (decision #98) |
| `ot/gate_accounts.py` | the four gate accounts on `vgsot.internal` through the Samba DC (decisions #97, #105 — the approver is W3's); idempotent; passwords generated here and written only to `dev.local` |
| `ot/gate_runs.py` | the Windows-mode API smoke on VGS-VM02 as each gate account, Administrator → Approver → ReadOnly → Hydro — a one-shot scheduled task per account, run, read back, deleted; the accounts hold `SeBatchLogonRight` on VM02 and the run's files live in `C:\Users\Public` (`docs/runbook/VM02-SECOND-SITE.md`) |
| `ot/gate_users.py` | the four gate accounts as platform users on a fresh V2 database (W8, #149): `Person_Add` / `User_Add` / `Grant_Add` as the SYSTEM actor, idempotent |
| `cutover_diff.py` | the content-hash diff of CUTOVER-STRATEGY §3 (W7, #32); duplicate natural keys suffixed in hash order (W8, #149); the rehearsal's mutated copy comes from `docs/schema/migration/make_cutover_copy.py` |
| `package_release.py` | the release artifact set (PLATFORM-ARCHITECTURE §9.2, decision 249): `dist/<version>/` with the DACPAC, the published site (+ zip), `sbom.json`, `release.json` (hashes) and the release document skeleton. Version = the sqlproj's `<DacVersion>`. Writes nothing to any database. |

The schema's own tooling (`deploy.py`, `smoke.py`, `generate.py`, `record_release.py`) lives in
`docs/schema/ddl/tools/`; `deploy.py --package dist/<version>` records the package hash on the
release row alongside the DACPAC hash.

```
python tools/package_release.py                      # → dist/<version>/
python docs/schema/ddl/tools/deploy.py --package dist/<version>      # publishes the packaged DACPAC, records both hashes
python tools/rehearse_relocation.py --package dist/<version> --api-url http://<host>:5200 --satellite-url http://<sat>:5210 --server <sql> --database PnCPlatform_V2_QA [--expect-refused <ot-host>:<port>]
```
