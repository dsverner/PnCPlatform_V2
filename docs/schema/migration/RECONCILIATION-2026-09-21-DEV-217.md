# Reconciliation — dbRelayManagement_Legacy → PnCPlatform_V2_DEV — 2026-09-21

Run `D4F31998-30F8-4EE3-8B4E-03901B8FA5B6` · 46602 procedure calls · 1045 s · limit none

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
| (LOCATION, EQUIPMENT) → Scheme (equipment group) | 1,769 |
| A row with no track rows → its change landed complete, both tracks NA (#164) | 5,636 |
| A row with track rows → its change landed at COMPLETION with the two tracks (card H, #148) | 2 |
| A row → the current revision, in service now | 5,530 |
| CONTROL SWITCH row: asset only, no configuration file (mappings/asset_type.csv) | 277 |
| Change Request ID (of an A/M/P row) → work.WorkRequest | 11,841 |
| D row: dropped, counted (#31) | 2,360 |
| DEVICE → ref.Model (existing) | 1,552 |
| LOCATIONS row → its station's USERNAME groups | 825 |
| M row → a Draft revision (the open change) | 350 |
| M row → a SETTINGS_CHANGE run landed at COMPLETION with its two tracks (#56) | 357 |
| MANUFACTURER → ref.Manufacturer (existing) | 46 |
| P row with no track rows → its change landed complete, both tracks NA (#164) | 1,085 |
| P row with track rows → its change landed at COMPLETION with the two tracks (card H, #148) | 4,596 |
| P row → a superseded revision with its in-service period | 5,684 |
| Relay Document Management row of a dropped or unknown chain: counted, not written | 4,236 |
| Relay Document Management row → a completion-track state on its request | 4,173 |
| SAP Work Order Numer → SapWorkOrder key | 40 |
| Setting Database Management row of a dropped or unknown chain: counted, not written | 4,235 |
| Setting Database Management row → a completion-track state on its request | 4,173 |
| Setting Software Management non-NA row → a note on the request (#58) | 1,729 |
| Setting Software Management row of a dropped or unknown chain: counted, not written | 4,236 |
| Setting Software Management row of an A/M/P chain: NA (nothing to carry) or a note (#58) | 4,172 |
| Settings Management duplicate row (same CR): folded into its request | 761 |
| Settings Management row of a dropped chain (D / 2440): counted, not written | 2,477 |
| Settings Management row with no SETTINGS row: counted, not written | 602 |
| Settings Management row → the request's type, requester, notes | 6,241 |
| Users → personnel.Person | 32 |
| a Word file not named by the rotation → not loaded | 84 |
| a Word lock file or recovery copy → skipped | 556 |
| a change-request document whose folder is not its revision's station → loaded onto that revision, flagged | 100 |
| a document in a folder that names no legacy location → not loaded | 105 |
| a document whose change request belongs to a dropped D record → not loaded (R-06) | 1,190 |
| a document whose number and change request match no revision → not loaded | 555 |
| a document whose number has no legacy row → not loaded | 23 |
| a relay setting file beside the documents → skipped (not a document) | 387 |
| a rotation-named document → the rationale of the revision with its number and change request | 3,427 |
| an A document whose folder holds no row of its number → not loaded, flagged | 224 |
| an A document whose folder holds only a dropped record of its number → not loaded (R-06) | 34 |
| an A document whose number now serves elsewhere → the last superseded revision of the number at the folder's station (the retired device's record) | 12 |
| an A document → the in-service revision of its number at the folder's station | 3,161 |
| base number → DevicePosition + Asset (+ Device, Installed) | 6,839 |
| base number → member of its equipment group (asset + protection functions) | 6,839 |
| chain where an archived CR exceeds the active CR → a finding (#59) | 18 |
| duplicate station number → a finding on the station left without one (card C) | 2 |
| row keyed '2…' (2440): dropped, counted (#60) | 2 |
| row of a base with no LOCATION/EQUIPMENT panel: counted, not written | 8 |
| station created / confirmed | 232 |
| station placed under the owner's marked division (card A) | 231 |
| the same document filed twice for one revision → loaded once | 44 |

### SETTINGS arithmetic

A 5,530 + M 350 + P 5,684 + control-switch rows 277 + D 2,360 + 2440 2 + no-panel 8 = 14,211

## Target rows written / skipped (idempotent)

| Target | Written | Skipped |
|---|---:|---:|
| `asset.Asset` | 0 | 331 |
| `document.ConfigurationFile` | 0 | 11,563 |
| `document.Document` | 6,656 | 0 |
| `document.File` | 6,656 | 0 |
| `document.RevisionLink` | 6,656 | 0 |
| `location.AlternateKey` | 0 | 225 |
| `location.Node` | 0 | 9,072 |
| `personnel.Person` | 0 | 32 |
| `process.ProcedureInstance` | 0 | 11,676 |
| `record.Finding` | 0 | 20 |
| `scheme.Scheme` | 0 | 1,769 |
| `scheme.SchemeMember` | 0 | 6,839 |
| `work.AlternateKey` | 0 | 11,881 |
| `work.WorkRequest` | 0 | 11,841 |

## Flags

| Flag | Count | Examples |
|---|---:|---|
| `ChainLocationVaries` | 1,572 | 0002 base 0002: its rows name more than one (LOCATION, EQUIPMENT); the A0002 row's is used; 0003 base 0003: its rows name more than one (LOCATION, EQUIPMENT); the M0003 row's is used; 0004 base 0004: its rows name more than one (LOCATION, EQUIPMENT); the A0004 row's is used; 0005 base 0005: its rows |
| `HeaderDuplicated` | 760 | 6161412 CR 6161412 has 2 header rows; the one naming this chain (else the first) is used; 3212819 CR 3212819 has 2 header rows; the one naming this chain (else the first) is used; 3212924 CR 3212924 has 2 header rows; the one naming this chain (else the first) is used; 8078295 CR 8078295 has 2 heade |
| `HeaderUnderOtherCr` | 1,672 | 2141435 CR 2141435/P0002: no header under this CR; the relay's header under CR 2144042 used (1 candidate CR(s)) — card H; 3196082 CR 3196082/P0004: no header under this CR; the relay's header under CR 3380710 used (2 candidate CR(s)) — card H; 3196025 CR 3196025/P0005: no header under this CR; the r |
| `LandingNotRepaired` | 165 | P0007 P0007/3195512: landed earlier under other track states; a landed run is not re-shaped; P0007 P0007/3212924: landed earlier under other track states; a landed run is not re-shaped; P0028 P0028/3195968: landed earlier under other track states; a landed run is not re-shaped; P0028 P0028/3217685:  |
| `NoTrackRows` | 6,721 | A0001 A0001/3: no legacy track row anywhere; landed complete with both tracks NA (#164); A0002 A0002/2144042: no legacy track row anywhere; landed complete with both tracks NA (#164); P0003 P0003/7268134: no legacy track row anywhere; landed complete with both tracks NA (#164); A0004 A0004/6793753:  |
| `PrefixLowerCase` | 9 | a0193 a0193/686: the state prefix is lower case; read as A; a0547 a0547/953: the state prefix is lower case; read as A; a0566 a0566/1027: the state prefix is lower case; read as A; a0635 a0635/6594: the state prefix is lower case; read as A; a1236 a1236/5466: the state prefix is lower case; read as  |
| `RationaleFolderMismatch` | 324 | M5316_3558170.doc Edmundston Terminal/M5316_3558170.doc: the revision with this number and change request is at Grand Lake Terminal; loaded there, the folder disagrees; M5430_5303515.doc Edmundston Terminal/M5430_5303515.doc: the revision with this number and change request is at Eel River Term 230; |
| `RationaleFolderUnknown` | 6 | Grand Lake Plant Grand Lake Plant: the folder names no legacy location; its documents are not loaded; Grand Lake Unit 8 Grand Lake Unit 8: the folder names no legacy location; its documents are not loaded; Great Falls Plant Great Falls Plant: the folder names no legacy location; its documents are no |
| `RequestNoHeader` | 5,600 | 3 CR 3: no Settings Management row; work type SETTINGS_CHANGE assumed; 7268134 CR 7268134: no Settings Management row; work type SETTINGS_CHANGE assumed; 7759879 CR 7759879: no Settings Management row; work type SETTINGS_CHANGE assumed; 6793753 CR 6793753: no Settings Management row; work type SETTI |
| `RequestTypeUnknown` | 32 | 9177900 CR 9177900: type None; work type SETTINGS_CHANGE assumed; 7992075 CR 7992075: type None; work type SETTINGS_CHANGE assumed; 8840935 CR 8840935: type None; work type SETTINGS_CHANGE assumed; 5834222 CR 5834222: type 'add Order'; work type SETTINGS_CHANGE assumed; 6228376 CR 6228376: type 'add |
| `RequesterNotAUser` | 1,706 | 4193909 CR 4193909: requested by 'David LeBlanc', not in Users; 4198934 CR 4198934: requested by 'David LeBlanc', not in Users; 8074893 CR 8074893: requested by 'David LeBlanc', not in Users; 8078994 CR 8078994: requested by 'David LeBlanc', not in Users; 8078592 CR 8078592: requested by 'David LeBl |
| `SapWorkOrderDuplicate` | 7 | 8825579 CR 8825579: SapWorkOrder '000000' already belongs to another request; no key written; 911 CR 911: SapWorkOrder '3000040109' already belongs to another request; no key written; 8233397 CR 8233397: SapWorkOrder '3000019301' already belongs to another request; no key written; 3440 CR 3440: SapW |
| `StationGroupConflict` | 186 | ABERDEEN STREET 'ABERDEEN STREET' is listed under {'Eng': 1, 'Dist': 1}; the most frequent group placed it; ADEX MINERALS 'ADEX MINERALS' is listed under {'Eng': 1, 'Dist': 1}; the most frequent group placed it; ATLANTIC WALLBOARD 'ATLANTIC WALLBOARD' is listed under {'Eng': 1, 'Dist': 1}; the most  |
| `StationNumberAssumed` | 214 | ABERDEEN STREET 'ABERDEEN STREET' station number 6100 from the dominant SETTINGS.ASSET (19 rows); ADEX MINERALS 'ADEX MINERALS' station number 5216 from the dominant SETTINGS.ASSET (2 rows); ALLARDVILLE SS 'ALLARDVILLE SS' station number 4498 from the dominant SETTINGS.ASSET (11 rows); ATLANTIC WALL |
| `StationNumberDuplicate` | 2 | MOBILE 35MVA 'MOBILE 35MVA' station number 6160 already belongs to 'MOBILE 15MVA'; no key written; a finding raised (card C); NEGUAC 'NEGUAC' station number 6100 already belongs to 'ABERDEEN STREET'; no key written; a finding raised (card C) |
| `TrackUnderOtherCr` | 3,398 | P0002 P0002/2141435: doc track found under CR 2144042 (SETTINGS and the track disagree) — card H; P0002 P0002/2141435: db track found under CR 2144042 (SETTINGS and the track disagree) — card H; P0004 P0004/3196082: doc track found under CR 3380710 (SETTINGS and the track disagree) — card H; P0004 P |
