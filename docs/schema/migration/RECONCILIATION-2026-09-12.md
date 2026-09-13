# Reconciliation — dbRelayManagement_Legacy → PnCPlatform_V2_DEV — 2026-09-12

Run `259DD02D-4084-4A41-A1B8-B53F68DE5DE5` · 9 procedure calls · 106 s · limit none

## Source totals

| Table | Rows |
|---|---:|
| `SETTINGS` | 14,211 |
| `Settings Management` | 8,409 |
| `Relay Document Management` | 8,409 |
| `Setting Database Management` | 8,408 |
| `Setting Software Management` | 8,408 |
| `LOCATIONS` | 825 |
| `Users` | 32 |

Sum: 48,702 (the gate: 14 211 + 8 409 + 8 409 + 8 408 + 8 408 + 825 + 32 = 48 702, plus `Setting Software Data` 4 and `sysdiagrams` 0 = 48 706)

## Every input row under one rule

| Rule | Rows |
|---|---:|
| (LOCATION, EQUIPMENT) → Panel | 1,769 |
| A row → the current revision, in service now | 5,530 |
| CONTROL SWITCH row: asset only, no configuration file (mappings/asset_type.csv) | 277 |
| Change Request ID (of an A/M/P row) → work.WorkRequest | 11,840 |
| D row: dropped, counted (#31) | 2,361 |
| DEVICE → ref.Model (existing) | 1,552 |
| LOCATIONS row → its station's USERNAME groups | 825 |
| M row → a Draft revision (the open change) | 350 |
| MANUFACTURER → ref.Manufacturer (existing) | 46 |
| P row → a superseded revision with its in-service period | 5,683 |
| Relay Document Management row of a dropped or unknown chain: counted, not written | 4,237 |
| Relay Document Management row → a completion-track state on its request | 4,172 |
| Setting Database Management row of a dropped or unknown chain: counted, not written | 4,236 |
| Setting Database Management row → a completion-track state on its request | 4,172 |
| Setting Software Management non-NA row → a note on the request (#58) | 1,156 |
| Setting Software Management row of a dropped or unknown chain: counted, not written | 4,236 |
| Setting Software Management row of an A/M/P chain: NA (nothing to carry) or a note (#58) | 4,172 |
| Settings Management duplicate row (same CR): folded into its request | 761 |
| Settings Management row of a dropped chain (D / 2440): counted, not written | 2,478 |
| Settings Management row with no SETTINGS row: counted, not written | 601 |
| Settings Management row → the request's type, requester, notes | 4,569 |
| Users → personnel.Person | 32 |
| base number → DevicePosition + Asset (+ Device, Installed) | 6,839 |
| chain where an archived CR exceeds the active CR → a finding (#59) | 17 |
| row keyed '2…' (2440): dropped, counted (#60) | 2 |
| row of a base with no LOCATION/EQUIPMENT panel: counted, not written | 8 |
| station created / confirmed | 231 |

### SETTINGS arithmetic

A 5,530 + M 350 + P 5,683 + control-switch rows 277 + D 2,361 + 2440 2 + no-panel 8 = 14,211

## Target rows written / skipped (idempotent)

| Target | Written | Skipped |
|---|---:|---:|
| `asset.Asset` | 0 | 6,830 |
| `document.ConfigurationFile` | 0 | 11,563 |
| `location.AlternateKey` | 0 | 225 |
| `location.Node` | 0 | 9,070 |
| `personnel.Person` | 0 | 32 |
| `process.ProcedureInstance` | 0 | 357 |
| `record.Finding` | 0 | 17 |
| `work.WorkRequest` | 0 | 11,831 |

## Flags

| Flag | Count | Examples |
|---|---:|---|
| `ChainLocationVaries` | 1,572 | 0002 base 0002: its rows name more than one (LOCATION, EQUIPMENT); the A0002 row's is used; 0003 base 0003: its rows name more than one (LOCATION, EQUIPMENT); the M0003 row's is used; 0004 base 0004: its rows name more than one (LOCATION, EQUIPMENT); the A0004 row's is used; 0005 base 0005: its rows |
| `HeaderDuplicated` | 760 | 6161412 CR 6161412 has 2 header rows; the one naming this chain (else the first) is used; 3212819 CR 3212819 has 2 header rows; the one naming this chain (else the first) is used; 3212924 CR 3212924 has 2 header rows; the one naming this chain (else the first) is used; 8078295 CR 8078295 has 2 heade |
| `InServiceOrder` | 6 | P0004 P0004/6161412: SetInService refused on re-run (('42000', '[42000] [Microsoft][ODBC Driver 17 for SQL Server][SQL Server]document.SetInService: the ); P0007 P0007/3212924: SetInService refused on re-run (('42000', '[42000] [Microsoft][ODBC Driver 17 for SQL Server][SQL Server]document.SetInServ |
| `PrefixLowerCase` | 9 | a0193 a0193/686: the state prefix is lower case; read as A; a0547 a0547/953: the state prefix is lower case; read as A; a0566 a0566/1027: the state prefix is lower case; read as A; a0635 a0635/6594: the state prefix is lower case; read as A; a1236 a1236/5466: the state prefix is lower case; read as  |
| `RequestNoHeader` | 7,271 | 3 CR 3: no Settings Management row; work type SETTINGS_CHANGE assumed; 2141435 CR 2141435: no Settings Management row; work type SETTINGS_CHANGE assumed; 7268134 CR 7268134: no Settings Management row; work type SETTINGS_CHANGE assumed; 7759879 CR 7759879: no Settings Management row; work type SETTI |
| `RequestTypeUnknown` | 19 | 9177900 CR 9177900: type None; work type SETTINGS_CHANGE assumed; 6228376 CR 6228376: type 'add Order'; work type SETTINGS_CHANGE assumed; 9607020 CR 9607020: type None; work type SETTINGS_CHANGE assumed; 9606982 CR 9606982: type None; work type SETTINGS_CHANGE assumed; 9606983 CR 9606983: type None |
| `RequesterNotAUser` | 1,192 | 4193909 CR 4193909: requested by 'David LeBlanc', not in Users; 4198934 CR 4198934: requested by 'David LeBlanc', not in Users; 8078994 CR 8078994: requested by 'David LeBlanc', not in Users; 8078295 CR 8078295: requested by 'David LeBlanc', not in Users; 8078592 CR 8078592: requested by 'David LeBl |
| `StationGroupConflict` | 187 | ABERDEEN STREET 'ABERDEEN STREET' is listed under {'Eng': 1, 'Dist': 1}; the most frequent group placed it; ADEX MINERALS 'ADEX MINERALS' is listed under {'Eng': 1, 'Dist': 1}; the most frequent group placed it; ATLANTIC WALLBOARD 'ATLANTIC WALLBOARD' is listed under {'Eng': 1, 'Dist': 1}; the most  |
| `StationNumberAssumed` | 214 | ABERDEEN STREET 'ABERDEEN STREET' station number 6100 from the dominant SETTINGS.ASSET (19 rows); ADEX MINERALS 'ADEX MINERALS' station number 5216 from the dominant SETTINGS.ASSET (2 rows); ALLARDVILLE SS 'ALLARDVILLE SS' station number 4498 from the dominant SETTINGS.ASSET (11 rows); ATLANTIC WALL |
| `StationNumberDuplicate` | 2 | MOBILE 35MVA 'MOBILE 35MVA' station number 6160 already belongs to another station; no key written — the owner's W7 card; NEGUAC 'NEGUAC' station number 6100 already belongs to another station; no key written — the owner's W7 card |
