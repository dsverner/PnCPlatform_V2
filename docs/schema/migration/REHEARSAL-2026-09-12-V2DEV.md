# Rehearsal 2026-09-12 — `PnCPlatform_V2_DEV`

Started 2026-09-12T23:18:27; loaders: legacy_import.

## Outcome

- First pass wrote **0** target rows across 1 run(s); **0** provenance rows.
- Second pass (idempotence): **0** rows written — PASS.
- Rows tagged with these runs but lacking provenance: **0** PASS.
- Direct table writes in loaders (grep): **0** PASS.

## dbRelayManagement_Legacy — run `E71469C8-D308-4B1F-95C5-192F89D5FB8E`

Actor `2ED01632-E06A-4C64-B528-C15EAABC8D5B`; 9 procedure calls in 205.9s.

| Target | Written | Skipped (already loaded) |
|---|---|---|
| `asset.Asset` | 0 | 6,830 |
| `document.ConfigurationFile` | 0 | 11,563 |
| `location.AlternateKey` | 0 | 225 |
| `location.Node` | 0 | 9,070 |
| `personnel.Person` | 0 | 32 |
| `process.ProcedureInstance` | 0 | 357 |
| `record.Finding` | 0 | 17 |
| `work.WorkRequest` | 0 | 11,831 |

| Flag | Count | Examples |
|---|---|---|
| `RequestNoHeader` | 7,271 | 3 CR 3: no Settings Management row; work type SETTINGS_CHANGE assumed; 2141435 CR 2141435: no Settings Management row; work type SETTINGS_CHANGE assumed; 7268134 CR 7268134: no Settings Management row; work type SETTINGS |
| `ChainLocationVaries` | 1,572 | 0002 base 0002: its rows name more than one (LOCATION, EQUIPMENT); the A0002 row's is used; 0003 base 0003: its rows name more than one (LOCATION, EQUIPMENT); the M0003 row's is used; 0004 base 0004: its rows name more t |
| `RequesterNotAUser` | 1,192 | 4193909 CR 4193909: requested by 'David LeBlanc', not in Users; 4198934 CR 4198934: requested by 'David LeBlanc', not in Users; 8078994 CR 8078994: requested by 'David LeBlanc', not in Users |
| `HeaderDuplicated` | 760 | 6161412 CR 6161412 has 2 header rows; the one naming this chain (else the first) is used; 3212819 CR 3212819 has 2 header rows; the one naming this chain (else the first) is used; 3212924 CR 3212924 has 2 header rows; th |
| `StationNumberAssumed` | 214 | ABERDEEN STREET 'ABERDEEN STREET' station number 6100 from the dominant SETTINGS.ASSET (19 rows); ADEX MINERALS 'ADEX MINERALS' station number 5216 from the dominant SETTINGS.ASSET (2 rows); ALLARDVILLE SS 'ALLARDVILLE S |
| `StationGroupConflict` | 187 | ABERDEEN STREET 'ABERDEEN STREET' is listed under {'Eng': 1, 'Dist': 1}; the most frequent group placed it; ADEX MINERALS 'ADEX MINERALS' is listed under {'Eng': 1, 'Dist': 1}; the most frequent group placed it; ATLANTIC |
| `RequestTypeUnknown` | 19 | 9177900 CR 9177900: type None; work type SETTINGS_CHANGE assumed; 6228376 CR 6228376: type 'add Order'; work type SETTINGS_CHANGE assumed; 9607020 CR 9607020: type None; work type SETTINGS_CHANGE assumed |
| `PrefixLowerCase` | 9 | a0193 a0193/686: the state prefix is lower case; read as A; a0547 a0547/953: the state prefix is lower case; read as A; a0566 a0566/1027: the state prefix is lower case; read as A |
| `InServiceOrder` | 6 | P0004 P0004/6161412: SetInService refused on re-run (('42000', '[42000] [Microsoft][ODBC Driver 17 for SQL Server][SQL Server]document.SetInService: the ); P0007 P0007/3212924: SetInService refused on re-run (('42000', ' |
| `StationNumberDuplicate` | 2 | MOBILE 35MVA 'MOBILE 35MVA' station number 6160 already belongs to another station; no key written — the owner's W7 card; NEGUAC 'NEGUAC' station number 6100 already belongs to another station; no key written — the owner |

## Rows in the target tagged with these runs

| Table | Rows |
|---|---|
