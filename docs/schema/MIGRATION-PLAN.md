# MIGRATION-PLAN — the legacy relay-settings database into the platform

**Version 2.0 · W7, 2026-09-12 · decisions #137–#144.** The predecessor's plan of 2026-09-04 (its rules M-01…M-23, its
rehearsals r1–r9) was held uncommitted through W0–W6 (#82) and is replaced by this one: the same machinery, the
rules of `docs/migration/CUTOVER-STRATEGY.md` §5 as the owner ruled them (#31, #34, #56, #58–#62, #72), V2's numbers.
What was carried and what was not is #137.

## 1. Authority and principles

- The source is `dbRelayManagement_Legacy` on VM01 (`docs/review/LEGACY-SYSTEM.md`: 9 tables, 48 706 rows, no logic),
  restored from `Z:\Reference\SqlBackup\dbRelayManagement_legacy.bak` (captured 2026-04-22).
- The target is `PnCPlatform_V2_DEV` (never the predecessor's `PnCPlatform_DEV`, #99); the loader refuses any other
  prefix.
- **Writes go only through the deployed procedures**, every one with `@MigrationRunId`; `run_rehearsal.py` greps the
  loaders for a direct `INSERT`/`UPDATE`/`DELETE`/`MERGE`. The hand-written engine procedures gained the parameter in
  W7 (#138).
- **One `migration.Provenance` row per target row** (`SourceKey`, SHA-256 of the source row); the reverse walk from any
  platform row to its legacy row is always possible.
- **Idempotent** on `(target, SourceKey, hash)`: a re-run writes nothing for unchanged source rows; a re-run repairs one
  thing only — an A/P revision an earlier run left without an in-service period.
- **Flags, never repairs**: `FLAG:<kind>: text` in `Provenance.Notes`, counted per kind in the reconciliation.
- **Every input row is accounted for by exactly one rule** in the reconciliation (`RECONCILIATION-<date>.md`); the
  totals sum to the source counts.

## 2. The toolkit (`docs/schema/migration/`)

| File | Carried / new | What |
|---|---|---|
| `common.py` | carried (#137) | `Run` (a `migration.Run` under the System actor `Migration:<source>`), `exec` (a procedure with `@ActorId`/`@MigrationRunId`), provenance, idempotence, flags, `date_quality` |
| `run_rehearsal.py` | carried, one loader | runs `legacy_import.py` twice (idempotence), checks provenance and direct writes, writes `REHEARSAL-<date>-<env>.md` |
| `catalogue_sources.py`, `SOURCES.md` | carried | the read-only source catalogue |
| `LEGACY-FIELDS.md` | carried | the owner's field dictionary |
| `mappings/*.csv` | carried | the owner's manufacturer, model, asset-type and station-number rulings of 2026-09-04/05/09 |
| `legacy_import.py` | **new** | the importer, §5 |
| `profile_set1.py` | **new** | the per-model SET1 profile for the templates card (#61) |
| `tools/cutover_diff.py` | **new** | the hash-diff cutover tool (§3 of the strategy; #32) |

Not carried: the predecessor's loaders (`legacy_relay_management.py`, `seeds_predecessor.py`, `predecessor_population.py`,
`rationale_predecessor.py`, `floc_*.py`, `tlm_gridinfo.py`, `aspen_layer.py`) and its rehearsal reports — they load the
predecessor's databases with rules three of which contradict V2 (`NativeSettings` for SET1, the tracks dropped, the
OLD_NO prefix never read). They stay in `C:\Projects\PnCPlatform\docs\schema\migration\`.

## 3. Running it

```
python docs/schema/migration/run_rehearsal.py --database PnCPlatform_V2_DEV            # two passes + the checks + the report
python docs/schema/migration/legacy_import.py --limit 40 --report recon.md            # a smoke over the first 40 base numbers
python docs/schema/migration/profile_set1.py --top 40                                  # the templates card's input
python tools/cutover_diff.py --left db:dbRelayManagement_Legacy --snapshot ours.json   # see the tool's header
```

Credentials: `dev.local` `PNC_DEV_PWD` (never in the repository). A full run is roughly 130 000 procedure calls at
~45 ms each over Tailscale (measured on the first 40 base numbers).

## 4. Environments and runs

| Run | Database | Result |
|---|---|---|
| 2026-09-12 first 20 / 40 base numbers | `PnCPlatform_V2_DEV` | the shape confirmed through the parity views (Active / Archived / Outstanding, a landed instance's tree, a finding, the FLOC rows); three defects found and fixed (a duplicate station number, a duplicate legacy record number within a chain, in-service dates that do not advance along a chain) |
| 2026-09-12 full | `PnCPlatform_V2_DEV` | `REHEARSAL-2026-09-12-V2DEV.md`, `RECONCILIATION-2026-09-12.md` |
| 2026-09-13 observed | `PnCPlatform_V2_DEV` | the parity screens in Chrome over the load (`docs/workflow/evidence/W7-*.jpg`); found in the source: for 3 770 of the 5 850 P rows the header and tracks on the OLD_NO name a different Change Request ID than the SETTINGS row (P0002: 2141435 vs 2144042) — the importer keys them by the SETTINGS CR, so those requests read "settings change, assumed" with tracks Not Started; put to the owner as W7 card item H, nothing re-keyed until ruled |

## 5. The rules — one per source row kind (CUTOVER-STRATEGY §5, as built)

| # | Source | Becomes | Rule as built | Flags |
|---|---|---|---|---|
| R-01 | `Users` (32) | `personnel.Person` | first/last split of the name, `IsSystemAccount` 0, the level in Notes; **no account, no password** (#143) | — |
| R-02 | `SETTINGS.MANUFACTURER` (46 labels) | `party.Entity` + `ref.Manufacturer` | `mappings/manufacturer.csv` (short code, name), else the label as found; `UNKNOWN` for a null | `ManufacturerFromLabel` |
| R-03 | `(MANUFACTURER, DEVICE)` (1 100 labels) | `ref.Model` | `mappings/device_model.csv` (code, name, technology), else the label as the code; asset type `ProtectiveRelay` (`CONTROL_SWITCH` for the switch rows, `mappings/asset_type.csv`); technology from the CSV, else Microprocessor for SEL/GE/ABB/Beckwith/Basler/Startco/Littelfuse/iGard/ERL, else Electromechanical | `TechnologyAssumed` (owner's card) |
| R-04 | `LOCATIONS` (825) + `SETTINGS.LOCATION` | `location.Node` Station under a Division | the station's most frequent `USERNAME` group → division (Hydro → Generation · Hydro, CCove → Generation · Coleson, Gen → Generation · Belledune, Dist → Distribution, Eng → Transmission — **defaults, #139, owner's card**); station number from `mappings/station_asset_number.csv`, else the dominant `SETTINGS.ASSET`; one placeholder Building per station | `StationGroupConflict`, `StationNotInLocations`, `StationNumberAssumed`, `StationNumberDuplicate` |
| R-05 | distinct `(LOCATION, EQUIPMENT)` (1 773) | `location.Node` Panel | under the station's placeholder building, named the equipment string — the legacy "protected asset" level | — |
| R-06 | one base number (`OLD_NO` minus prefix; 6 842) | `DevicePosition` + `asset.Asset` + `device.Device`, Installed | the representative row is the A row, else the M, else the latest P; the position under R-05's panel, named from `FUNCTIONS` (else `DEVICE`); the asset named `<DEVICE> [<base>]`, status InService / Planned / OutOfService by A / M-only / P-only; keys `LegacyRecordNumber` per distinct `OLD_NO`, `SerialNumber` | `ChainLocationVaries`, `LegacyRecordNumberDuplicate`, `SerialNumberDuplicate` |
| R-07 | `FUNCTIONS` with an ANSI code in parentheses | `ProtectionFunction` node + `scheme.CommissionedFunction` (+ `ref.AnsiFunction` upserted) | one per code, the first principal; text without a code → `location.NodeFunction` label | — |
| R-08 | distinct `Change Request ID` of the A/M/P rows (11 848) | `work.WorkRequest` | the header row naming the chain (else the first) → type → work type (#131), requester, SAP order; no header → `SETTINGS_CHANGE`; scoped to the chain's asset; keys `LegacyChangeRequestNumber`, `SapWorkOrder` | `RequestNoHeader`, `RequestTypeUnknown`, `HeaderDuplicated`, `RequesterNotAUser`, `RequestSpansDevices` |
| R-09 | `Setting Software Management` non-NA row of a chain | a dated note on the request (#58) | `Legacy software track (<OLD_NO>): <status> <date> — <notes>` | — |
| R-10 | `A` / `M` / `P` row (5 641 / 357 / 5 850) | a `SettingsText` configuration-file revision from `SET1` (#61, #140) + one `ConfigurationFileRevision` record | `WriteConfigurationRevision` with the file-kind override, at CDATE (else VDATE, else the capture date, quality 2); A → Issued and in service from VDATE (open); P → Superseded, in service from VDATE until the next revision's; M → Draft; in-service dates that do not advance along the CR order are set one second after the prior, quality 2; the overflow columns in the record's summary | `CalculatedDateUnknown`, `VerifiedDateUnknown`, `InServiceDateAdjusted`, `InServiceOrder`, `NoSettingsText` |
| R-11 | `M` row (357) | a `SETTINGS_CHANGE_REQUEST` + `SETTINGS_CHANGE` run landed at COMPLETION (#56, #141) | `process.LandMigratedInstance`: steps 1–12 Skipped/`Migrated`, the two branches from `Relay Document Management` and `Setting Database Management` (Complete → Completed, NA → Skipped/NotApplicable, else Running) | `TrackRowMissing` |
| R-12 | the 17 chains where an archived CR exceeds the active CR | `record.Finding` (`MigrationReconciliation`, Major, Open) on the device (#59, #142) | migrated as the letters say; a person rules | — |
| R-13 | `D` rows (2 361), the two `2440` rows | dropped, counted (#31, #60) | never written | — |
| R-14 | header / track rows of a dropped or unknown chain; duplicate header rows | counted, not written; duplicates folded into their request | — | — |
| R-15 | `IDATE`; `Date` of the header | dropped (#72; 100 % null) | — | — |
| R-16 | `CT_*`, `PT_*`, `DESC1-4`, `REMARKS1-5`, `CLASS`, `USE`, `RESPONSIBILITY`, … | the revision record's summary text (W7 default) | typed characteristics are a later mapping | — |

## 6. Not done here, by design

- **The per-model settings templates** (#61): `profile_set1.py` profiles every model's names; the templates are the
  owner's card. Until a model has one, its migrated text files stay `NotParsed` (`ParseSettingsText` needs a template).
- **Rationale documents**: NB Power's inventory (count, location, naming) is an open ask; the predecessor's 171
  `protection.Attachment` rows are not loaded here (their loader was not carried).
- **Cutover deletes**: `cutover_diff.py` reports them; applying them is the W8 rehearsal's.
- **Division mapping, FLOC shape, model technology, null-VDATE handling**: defaults, on the owner's W7 card.
