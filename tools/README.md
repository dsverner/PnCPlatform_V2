# `tools/` — repository-level tooling

| Script | What |
|---|---|
| `rehearse_relocation.py` | the relocation checklist (PLATFORM-ARCHITECTURE §1.4, decision 253) as a runnable against a deployed release: performs steps 3, 6, 7, reports 1, 2, 4, 5; writes the `PlatformDeployment` record and `dist/<version>/REHEARSAL-<date>.md`; exit 1 on a failed step |
| `package_release.py` | the release artifact set (PLATFORM-ARCHITECTURE §9.2, decision 249): `dist/<version>/` with the DACPAC, the published site (+ zip), `sbom.json`, `release.json` (hashes) and the release document skeleton. Version = the sqlproj's `<DacVersion>`. Writes nothing to any database. |

The schema's own tooling (`deploy.py`, `smoke.py`, `generate.py`, `record_release.py`) lives in
`docs/schema/ddl/tools/`; `deploy.py --package dist/<version>` records the package hash on the
release row alongside the DACPAC hash.

```
python tools/package_release.py                      # → dist/<version>/
python docs/schema/ddl/tools/deploy.py --package dist/<version>      # publishes the packaged DACPAC, records both hashes
python tools/rehearse_relocation.py --package dist/<version> --api-url http://<host>:5200 --satellite-url http://<sat>:5210 --server <sql> --database PnCPlatform_QA [--expect-refused <ot-host>:<port>]
```
