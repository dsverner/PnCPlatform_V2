# Rehearsal 2026-09-13 — `PnCPlatform_V2_DEV`

Started 2026-09-13T11:29:12; loaders: legacy_import.

## Outcome

- First pass wrote **42,179** target rows across 1 run(s); **42,179** provenance rows.
- Second pass (idempotence): **0** rows written — PASS.
- Rows tagged with these runs but lacking provenance: **0** PASS.
- Direct table writes in loaders (grep): **0** PASS.

## dbRelayManagement_Legacy — run `46AB9EBA-72B4-4512-B133-1BF8F806F993`

Actor `2ED01632-E06A-4C64-B528-C15EAABC8D5B`; 42,195 procedure calls in 439.5s.

| Target | Written | Skipped (already loaded) |
|---|---|---|
| `asset.Asset` | 0 | 6,830 |
| `document.ConfigurationFile` | 0 | 11,563 |
| `location.AlternateKey` | 0 | 225 |
| `location.Node` | 0 | 9,070 |
| `personnel.Person` | 0 | 32 |
| `process.InstanceVersionSet` | 9,388 | 0 |
| `process.ProcedureInstance` | 0 | 5,114 |
| `process.StepInstance` | 28,097 | 0 |
| `process.WorkflowTransition` | 4,694 | 0 |
| `record.Finding` | 0 | 19 |
| `work.AlternateKey` | 0 | 11,881 |
| `work.WorkRequest` | 0 | 11,840 |

| Flag | Count | Examples |
|---|---|---|
| `RequestNoHeader` | 5,599 | 3 CR 3: no Settings Management row; work type SETTINGS_CHANGE assumed; 7268134 CR 7268134: no Settings Management row; work type SETTINGS_CHANGE assumed; 7759879 CR 7759879: no Settings Management row; work type SETTINGS |
| `TrackUnderOtherCr` | 3,398 | P0002 P0002/2141435: doc track found under CR 2144042 (SETTINGS and the track disagree) — card H; P0002 P0002/2141435: db track found under CR 2144042 (SETTINGS and the track disagree) — card H; P0004 P0004/3196082: doc  |
| `RequesterNotAUser` | 1,686 | 4193909 CR 4193909: requested by 'David LeBlanc', not in Users; 4198934 CR 4198934: requested by 'David LeBlanc', not in Users; 8074893 CR 8074893: requested by 'David LeBlanc', not in Users |
| `HeaderUnderOtherCr` | 1,672 | 2141435 CR 2141435/P0002: no header under this CR; the relay's header under CR 2144042 used (1 candidate CR(s)) — card H; 3196082 CR 3196082/P0004: no header under this CR; the relay's header under CR 3380710 used (2 can |
| `ChainLocationVaries` | 1,572 | 0002 base 0002: its rows name more than one (LOCATION, EQUIPMENT); the A0002 row's is used; 0003 base 0003: its rows name more than one (LOCATION, EQUIPMENT); the M0003 row's is used; 0004 base 0004: its rows name more t |
| `HeaderDuplicated` | 760 | 6161412 CR 6161412 has 2 header rows; the one naming this chain (else the first) is used; 3212819 CR 3212819 has 2 header rows; the one naming this chain (else the first) is used; 3212924 CR 3212924 has 2 header rows; th |
| `StationNumberAssumed` | 214 | ABERDEEN STREET 'ABERDEEN STREET' station number 6100 from the dominant SETTINGS.ASSET (19 rows); ADEX MINERALS 'ADEX MINERALS' station number 5216 from the dominant SETTINGS.ASSET (2 rows); ALLARDVILLE SS 'ALLARDVILLE S |
| `StationGroupConflict` | 187 | ABERDEEN STREET 'ABERDEEN STREET' is listed under {'Eng': 1, 'Dist': 1}; the most frequent group placed it; ADEX MINERALS 'ADEX MINERALS' is listed under {'Eng': 1, 'Dist': 1}; the most frequent group placed it; ATLANTIC |
| `RequestTypeUnknown` | 32 | 9177900 CR 9177900: type None; work type SETTINGS_CHANGE assumed; 7992075 CR 7992075: type None; work type SETTINGS_CHANGE assumed; 8840935 CR 8840935: type None; work type SETTINGS_CHANGE assumed |
| `PrefixLowerCase` | 9 | a0193 a0193/686: the state prefix is lower case; read as A; a0547 a0547/953: the state prefix is lower case; read as A; a0566 a0566/1027: the state prefix is lower case; read as A |
| `SapWorkOrderDuplicate` | 7 | 8375553 CR 8375553: SapWorkOrder '000000' already belongs to another request; no key written; 911 CR 911: SapWorkOrder '3000040109' already belongs to another request; no key written; 8233397 CR 8233397: SapWorkOrder '30 |
| `InServiceOrder` | 6 | P0004 P0004/6161412: SetInService refused on re-run (('42000', '[42000] [Microsoft][ODBC Driver 17 for SQL Server][SQL Server]document.SetInService: the ); P0007 P0007/3212924: SetInService refused on re-run (('42000', ' |
| `LandingNotRepaired` | 5 | M3378 M3378/7205759: landed earlier under other track states; a landed run is not re-shaped; M3379 M3379/7205816: landed earlier under other track states; a landed run is not re-shaped; M3381 M3381/7205930: landed earlie |
| `StationNumberDuplicate` | 2 | MOBILE 35MVA 'MOBILE 35MVA' station number 6160 already belongs to 'MOBILE 15MVA'; no key written; a finding raised (card C); NEGUAC 'NEGUAC' station number 6100 already belongs to 'ABERDEEN STREET'; no key written; a fi |

## Rows in the target tagged with these runs

| Table | Rows |
|---|---|
