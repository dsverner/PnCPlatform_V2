# Rehearsal 2026-09-16 — `PnCPlatform_V2_DEV`

Started 2026-09-16T09:54:53; loaders: legacy_import.

## Outcome

- First pass wrote **437,358** target rows across 1 run(s); **437,358** provenance rows.
- Second pass (idempotence): **0** rows written — PASS.
- Rows tagged with these runs but lacking provenance: **3007** ({'scheme.CommissionedFunction': 3007}).
- Direct table writes in loaders (grep): **0** PASS.

## dbRelayManagement_Legacy — run `4BAEC9B4-837A-4068-940C-062DD6D58E71`

Actor `8B944B6C-0AA9-47D6-B0CB-3ABE8FE23702`; 572,331 procedure calls in 7304.1s.

| Target | Written | Skipped (already loaded) |
|---|---|---|
| `asset.AlternateKey` | 10,836 | 0 |
| `asset.Asset` | 6,839 | 0 |
| `asset.Placement` | 6,839 | 0 |
| `device.Device` | 6,661 | 0 |
| `document.ConfigurationFile` | 11,563 | 0 |
| `document.Document` | 6,661 | 0 |
| `document.File` | 11,563 | 0 |
| `location.AlternateKey` | 225 | 0 |
| `location.Node` | 12,077 | 0 |
| `location.NodeFunction` | 3,894 | 0 |
| `party.Entity` | 37 | 0 |
| `personnel.Person` | 32 | 0 |
| `process.BlockInstance` | 177,600 | 0 |
| `process.InstanceVersionSet` | 23,680 | 0 |
| `process.ProcedureInstance` | 11,840 | 0 |
| `process.StepInstance` | 71,040 | 0 |
| `process.WorkflowInstance` | 11,840 | 0 |
| `process.WorkflowTransition` | 11,840 | 0 |
| `record.Finding` | 19 | 0 |
| `record.Record` | 11,563 | 0 |
| `ref.AnsiFunction` | 801 | 0 |
| `ref.AssetType` | 1 | 0 |
| `ref.Manufacturer` | 37 | 0 |
| `ref.Model` | 1,528 | 0 |
| `scheme.CommissionedFunction` | 3,007 | 0 |
| `scheme.Scheme` | 1,769 | 0 |
| `scheme.SchemeMember` | 9,846 | 0 |
| `work.AlternateKey` | 11,880 | 0 |
| `work.WorkRequest` | 11,840 | 0 |

| Flag | Count | Examples |
|---|---|---|
| `NoTrackRows` | 6,721 | A0001 A0001/3: no legacy track row anywhere; landed complete with both tracks NA (#164); A0002 A0002/2144042: no legacy track row anywhere; landed complete with both tracks NA (#164); P0003 P0003/7268134: no legacy track |
| `RequestNoHeader` | 5,599 | 3 CR 3: no Settings Management row; work type SETTINGS_CHANGE assumed; 7268134 CR 7268134: no Settings Management row; work type SETTINGS_CHANGE assumed; 7759879 CR 7759879: no Settings Management row; work type SETTINGS |
| `TrackUnderOtherCr` | 3,398 | P0002 P0002/2141435: doc track found under CR 2144042 (SETTINGS and the track disagree) — card H; P0002 P0002/2141435: db track found under CR 2144042 (SETTINGS and the track disagree) — card H; P0004 P0004/3196082: doc  |
| `RequesterNotAUser` | 1,705 | 4193909 CR 4193909: requested by 'David LeBlanc', not in Users; 4198934 CR 4198934: requested by 'David LeBlanc', not in Users; 8074893 CR 8074893: requested by 'David LeBlanc', not in Users |
| `HeaderUnderOtherCr` | 1,672 | 2141435 CR 2141435/P0002: no header under this CR; the relay's header under CR 2144042 used (1 candidate CR(s)) — card H; 3196082 CR 3196082/P0004: no header under this CR; the relay's header under CR 3380710 used (2 can |
| `ChainLocationVaries` | 1,572 | 0002 base 0002: its rows name more than one (LOCATION, EQUIPMENT); the A0002 row's is used; 0003 base 0003: its rows name more than one (LOCATION, EQUIPMENT); the M0003 row's is used; 0004 base 0004: its rows name more t |
| `TechnologyAssumed` | 1,517 | ???? '????' (UNKNOWN) technology Electromechanical assumed from the manufacturer; the owner's W7 card decides; 10 40 60 80 100% TAPS '10 40 60 80 100% TAPS' (UNKNOWN) technology Electromechanical assumed from the manufac |
| `InServiceDateAdjusted` | 1,201 | P0005 P0005/3403318: VDATE 2010-10-25 is not after the prior revision's 2010-10-25; in service from 2010-10-25 00:00:01, quality 2; P0005 P0005/3430004: VDATE 2010-10-25 is not after the prior revision's 2010-10-25; in s |
| `CalculatedDateUnknown` | 919 | P0012 P0012/4190057: CDATE DateNull; VDATE used; P0021 P0021/9447944: CDATE DateNull; VDATE used; P0021 P0021/9606942: CDATE DateSentinel; VDATE used |
| `VerifiedDateUnknown` | 904 | A0018 A0018/9606963: VDATE DateNull; in service from the calculated date, quality 2; P0028 P0028/7213070: VDATE DateNull; in service from the calculated date, quality 2; P0032 P0032/1105133: VDATE DateNull; in service fr |
| `HeaderDuplicated` | 760 | 6161412 CR 6161412 has 2 header rows; the one naming this chain (else the first) is used; 3212819 CR 3212819 has 2 header rows; the one naming this chain (else the first) is used; 3212924 CR 3212924 has 2 header rows; th |
| `SerialNumberDuplicate` | 598 | 0063 0063: SerialNumber 'N/A' already belongs to another asset; no key written; 0067 0067: SerialNumber 'xxx' already belongs to another asset; no key written; 0109 0109: SerialNumber 'N/A' already belongs to another ass |
| `NoSettingsText` | 349 | P0025 P0025/9606944: SET1 is empty; an empty settings file was written; A0025 A0025/9617664: SET1 is empty; an empty settings file was written; P0043 P0043/9606948: SET1 is empty; an empty settings file was written |
| `StationNumberAssumed` | 214 | ABERDEEN STREET 'ABERDEEN STREET' station number 6100 from the dominant SETTINGS.ASSET (19 rows); ADEX MINERALS 'ADEX MINERALS' station number 5216 from the dominant SETTINGS.ASSET (2 rows); ALLARDVILLE SS 'ALLARDVILLE S |
| `StationGroupConflict` | 187 | ABERDEEN STREET 'ABERDEEN STREET' is listed under {'Eng': 1, 'Dist': 1}; the most frequent group placed it; ADEX MINERALS 'ADEX MINERALS' is listed under {'Eng': 1, 'Dist': 1}; the most frequent group placed it; ATLANTIC |
| `RequestTypeUnknown` | 32 | 9177900 CR 9177900: type None; work type SETTINGS_CHANGE assumed; 7992075 CR 7992075: type None; work type SETTINGS_CHANGE assumed; 8840935 CR 8840935: type None; work type SETTINGS_CHANGE assumed |
| `InServiceViolationChain` | 17 | P0011 P0011/7268077: archived row above the active row's CR 108636; left without an in-service period (the finding rules); P0069 P0069/9617585: archived row above the active row's CR 9607008; left without an in-service p |
| `ManufacturerFromLabel` | 9 | CADMI 'CADMI' is not in mappings/manufacturer.csv; created as found; Crompton 'Crompton' is not in mappings/manufacturer.csv; created as found; DATUM 'DATUM' is not in mappings/manufacturer.csv; created as found |
| `PrefixLowerCase` | 9 | a0193 a0193/686: the state prefix is lower case; read as A; a0547 a0547/953: the state prefix is lower case; read as A; a0566 a0566/1027: the state prefix is lower case; read as A |
| `SapWorkOrderDuplicate` | 7 | 8825579 CR 8825579: SapWorkOrder '000000' already belongs to another request; no key written; 911 CR 911: SapWorkOrder '3000040109' already belongs to another request; no key written; 8233397 CR 8233397: SapWorkOrder '30 |
| `StationNumberDuplicate` | 2 | MOBILE 35MVA 'MOBILE 35MVA' station number 6160 already belongs to 'MOBILE 15MVA'; no key written; a finding raised (card C); NEGUAC 'NEGUAC' station number 6100 already belongs to 'ABERDEEN STREET'; no key written; a fi |
| `TrackRowMissing` | 1 | M7043 M7043/2307330: documentation and database track row missing; branch left Running |

## Rows in the target tagged with these runs

| Table | Rows |
|---|---|
| `location.Node` | 12,077 |
| `location.NodeFunction` | 3,894 |
| `location.AlternateKey` | 225 |
| `asset.Asset` | 6,839 |
| `device.Device` | 6,661 |
| `asset.Placement` | 6,839 |
| `asset.AlternateKey` | 10,836 |
| `scheme.CommissionedFunction` | 3,007 |
| `scheme.Scheme` | 1,769 |
| `scheme.SchemeMember` | 9,846 |
| `work.WorkRequest` | 11,840 |
| `work.AlternateKey` | 11,880 |
| `document.Document` | 6,661 |
| `document.Revision` | 11,563 |
| `document.ConfigurationFile` | 11,563 |
| `document.File` | 11,563 |
| `record.Record` | 11,582 |
| `record.Finding` | 19 |
| `ref.AssetType` | 1 |
| `ref.AnsiFunction` | 801 |
| `ref.Model` | 1,528 |
| `ref.Manufacturer` | 37 |
| `party.Entity` | 37 |
| `personnel.Person` | 32 |
| `process.WorkflowInstance` | 11,840 |
| `process.ProcedureInstance` | 11,840 |
| `process.InstanceVersionSet` | 23,680 |
| `process.BlockInstance` | 177,600 |
| `process.StepInstance` | 71,040 |
| `process.WorkflowTransition` | 11,840 |
