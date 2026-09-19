# What the obsolete database's fields mean

**Owner-written. This is the authority on meaning; everything else about these tables is measured.**

Skeleton generated 2026-09-09 by `scratchpad/mkfields.py` from
`dbRelayManagement_Legacy` on VM01, capture 2026-04-22. Every column is listed with what the data
looks like. Fill in the **Meaning** line under each one; leave `TODO` where you do not know.

Why this exists: the migration has been guessing at field meaning and asking one question at a
time. `OLD_NO`'s prefix carries the asset's state and the loader threw it away, which nobody
noticed until the screen showed 12,055 assets all in service. A written source of meaning stops
that repeating.

Companion to `SOURCES.md`, which is machine-generated structure. This one is meaning, by hand.

---

## `dbo.SETTINGS` — 14,211 rows

### `OLD_NO`

`char(5)`, not null · 14,211 of 14,211 populated · 11,718 distinct

Prefix counts: `A` 5,641 · `P` 3,536 · `D` 2,183 · `M` 357 · one beginning with a digit.

| Most common value | Rows |
|---|---|
| `P0439` | 11 |
| `P0214` | 10 |
| `P1087` | 10 |
| `P1072` | 9 |
| `P5599` | 9 |
| `P0005` | 9 |

**Meaning:** The record number. Its first letter is the state (owner, 2026-09-09):

| Prefix | Records | State |
|---|---|---|
| `A` | 5,641 | `InService` |
| `M` | 357 | `Planned` — outstanding in the old database |
| `P` | 3,536 | `OutOfService` — archived. The old database drew no line between out of service and retired, and the owner chose `OutOfService` for the import |
| `D` | 2,183 | **Not imported.** An older designation, superseded |
| `2…` | 1 | **Not imported.** One record number begins with a digit and has no state |

**Notes:** The loader kept the whole string as a `LegacyRecordNumber` alternate key and never read
the prefix, so all 12,055 assets came through `InService`. Fixed 2026-09-09.

Dropping `D` is safe on the evidence, not just on assertion: **2,173 of the 2,183 `D` records have a
`P` record carrying the same digits**, only six have neither a `P` nor an `A` twin, and dropping
them empties just 4 of 1,773 positions. 1,566 device rows are recorded under both `D` and `P` with
the same location, equipment and device, which is the bulk of the duplicate assets reported from the
screens.

The digits alone are not an identity: the same stem appears on unrelated devices at different
stations, so `D1500` and `P1500` being the same relay does not generalise from the number.

### `Change Request ID`

`bigint(8)`, not null · 14,211 of 14,211 populated · 14,211 distinct

| Most common value | Rows |
|---|---|
| `1` | 1 |
| `2` | 1 |
| `3` | 1 |
| `4` | 1 |
| `5` | 1 |
| `6` | 1 |

**Meaning:** With `OLD_NO` it forms the unique identifier that the other four tables use as their
linking mechanism — Relay Document Management, Setting Database Management, Setting Software
Management and Settings Management. Together they give the history of the device
(owner, 2026-09-09).

**Notes:** The loader already groups by `OLD_NO` and orders by this column, writing one asset fact
version per row, so device history is built the way the owner describes. It reads `Settings
Management` in full and takes a single `MAX(Status)` per change request from `Setting Database
Management`. **`Setting Software Management` and `Relay Document Management` are not read at all**,
16,817 rows between them, and the per-step notes and dates of all three step tables are discarded.
All four carry `Relay ID Number`, which is the prefixed record number, so anything built on them
must skip the dropped `D` records too.

### `LOCATION`

`char(30)`, not null · 14,211 of 14,211 populated · 227 distinct

| Most common value | Rows |
|---|---|
| `BELLEDUNE PLANT` | 1,152 |
| `KESWICK TERMINAL` | 1,042 |
| `EEL RIVER TERM 230` | 981 |
| `SALISBURY TERMINAL` | 628 |
| `BATHURST TERMINAL` | 565 |
| `MEMRAMCOOK TERMINAL` | 499 |

**Meaning:** TODO

**Notes:**

### `ASSET`

`smallint(2)` · 14,211 of 14,211 populated · 239 distinct

| Most common value | Rows |
|---|---|
| `740` | 1,137 |
| `4134` | 1,068 |
| `4403` | 838 |
| `4592` | 618 |
| `4499` | 581 |
| `4590` | 497 |

**Meaning:** TODO

**Notes:**

### `EQUIPMENT`

`char(50)`, not null · 14,211 of 14,211 populated · 782 distinct

| Most common value | Rows |
|---|---|
| `UNDERFREQUENCY` | 762 |
| `SYNCHRONIZING` | 485 |
| `TRANSFORMER T1` | 471 |
| `ANNUNCIATORS & RECORDERS` | 359 |
| `BREAKERS 138 KV` | 355 |
| `CONTROL TONES` | 335 |

**Meaning:** TODO

**Notes:**

### `DEVICE`

`char(125)` · 14,210 of 14,211 populated · 1,502 distinct

| Most common value | Rows |
|---|---|
| `SEL-551` | 474 |
| `SEL-2440` | 448 |
| `CONTROL SWITCH` | 321 |
| `CNT 35-96 .1 S-9990 HR 24-240 VAC/VDC` | 268 |
| `SEL-311C` | 258 |
| `SEL-221F Z1-3=.125-64 OHMS` | 208 |

**Meaning:** TODO

**Notes:**

### `FUNCTIONS`

`char(75)` · 14,210 of 14,211 populated · 4,761 distinct

| Most common value | Rows |
|---|---|
| `PHASE DIST GROUND DIST & FAULT LOCATOR` | 355 |
| `UNDERFREQ LOADSHEDDING` | 242 |
| `PHASE DIST GROUND DIST & FAULT LOCATOR` | 237 |
| `GROUND O/C` | 225 |
| `PHASE DIST GROUND DIST & FAULT LOCATOR` | 193 |
| `PHASE O/C` | 152 |

**Meaning:** TODO

**Notes:**

### `SERIAL_NUMBER`

`char(25)` · 4,541 of 14,211 populated · 1,427 distinct

| Most common value | Rows |
|---|---|
| `N/A` | 604 |
| `NA` | 252 |
| `` | 235 |
| `xxx` | 85 |
| `TBD` | 27 |
| `2005132301` | 14 |

**Meaning:** TODO

**Notes:**

### `SOFTWARE_VERSION`

`char(50)` · 4,406 of 14,211 populated · 343 distinct

| Most common value | Rows |
|---|---|
| `N/A` | 1,323 |
| `` | 210 |
| `7.41` | 200 |
| `NA` | 153 |
| `SEL-121F-R411-V656mpsssu2-D950712-E2` | 126 |
| `SEL-2440-R212-V0-Z005003-D20131217` | 117 |

**Meaning:** TODO

**Notes:**

### `CT_MAIN1`

`char(8)` · 8,378 of 14,211 populated · 88 distinct

| Most common value | Rows |
|---|---|
| `1200-5` | 1,645 |
| `800-5` | 1,374 |
| `200-5` | 670 |
| `600-5` | 600 |
| `2000-5` | 537 |
| `400-5` | 440 |

**Meaning:** TODO

**Notes:**

### `PT_MAIN`

`char(8)` · 4,768 of 14,211 populated · 89 distinct

| Most common value | Rows |
|---|---|
| `1200-1` | 1,187 |
| `600-1` | 600 |
| `3000-1` | 465 |
| `120-1` | 336 |
| `` | 306 |
| `????` | 206 |

**Meaning:** TODO

**Notes:**

### `SET1`

`nvarchar` · 13,810 of 14,211 populated · 4,686 distinct

| Most common value | Rows |
|---|---|
| `*** SEE SETTINGS DOCUMENT FOR DETAILS ` | 567 |
| `SEE WORD DOCUMENT` | 355 |
| `STATUS = IN SERVICE` | 290 |
| `MODE=B, TDDO=5.0 SECONDS` | 214 |
| `*** SEE SETTINGS DOCUMENT FOR DETAILS ` | 179 |
| `TDDO=5.0 SECONDS` | 175 |

**Meaning:** TODO

**Notes:**

### `SETTINGS2`

`nvarchar` · 2,855 of 14,211 populated · 927 distinct

| Most common value | Rows |
|---|---|
| `` | 490 |
| `PART NUM = 24402311A1A14840` | 54 |
| `GND CT RATIO=XXX:5, GND CURR CT PRIM=1` | 49 |
| `*** NEW RELAY ADDITION ***` | 32 |
| `ALTMP1=ALTMP2=ALTMP3=ALTMP4=ALTMP5=ALT` | 30 |
| `PART NUM = 24402312A1A14840` | 29 |

**Meaning:** TODO

**Notes:**

### `DESC1`

`char(4)` · 1,749 of 14,211 populated · 29 distinct

| Most common value | Rows |
|---|---|
| `HV` | 751 |
| `` | 498 |
| `PHA` | 158 |
| `LV` | 105 |
| `PH` | 95 |
| `T1` | 21 |

**Meaning:** TODO

**Notes:**

### `DESC2`

`char(4)` · 1,334 of 14,211 populated · 28 distinct

| Most common value | Rows |
|---|---|
| `` | 510 |
| `LV` | 439 |
| `GND` | 253 |
| `HV` | 25 |
| `X` | 12 |
| `NA` | 11 |

**Meaning:** TODO

**Notes:**

### `DESC3`

`char(4)` · 724 of 14,211 populated · 27 distinct

| Most common value | Rows |
|---|---|
| `` | 523 |
| `TV` | 90 |
| `T1LV` | 12 |
| `Y` | 12 |
| `0008` | 11 |
| `NA` | 11 |

**Meaning:** TODO

**Notes:**

### `DESC4`

`char(4)` · 620 of 14,211 populated · 16 distinct

| Most common value | Rows |
|---|---|
| `` | 539 |
| `NA` | 37 |
| `0018` | 11 |
| `34.5` | 5 |
| `TG` | 4 |
| `LVN` | 3 |

**Meaning:** TODO

**Notes:**

### `CT_MAIN2`

`char(8)` · 1,885 of 14,211 populated · 50 distinct

| Most common value | Rows |
|---|---|
| `` | 417 |
| `2000-5` | 285 |
| `2000-1` | 155 |
| `1200-5` | 145 |
| `1600-5` | 98 |
| `6000-5` | 90 |

**Meaning:** TODO

**Notes:**

### `CT_MAIN3`

`char(8)` · 929 of 14,211 populated · 35 distinct

| Most common value | Rows |
|---|---|
| `` | 489 |
| `2000-5` | 114 |
| `1600-5` | 33 |
| `1200-5` | 32 |
| `0` | 26 |
| `4000-5` | 25 |

**Meaning:** TODO

**Notes:**

### `CT_MAIN4`

`char(8)` · 750 of 14,211 populated · 24 distinct

| Most common value | Rows |
|---|---|
| `` | 506 |
| `NA` | 50 |
| `1` | 42 |
| `1600-5` | 20 |
| `600-5` | 20 |
| `1200-5` | 18 |

**Meaning:** TODO

**Notes:**

### `CT_AUX1`

`char(8)` · 927 of 14,211 populated · 33 distinct

| Most common value | Rows |
|---|---|
| `` | 526 |
| `100-5` | 143 |
| `NA` | 60 |
| `3/5` | 49 |
| `2000-5` | 22 |
| `2/5` | 16 |

**Meaning:** TODO

**Notes:**

### `CT_AUX2`

`char(8)` · 605 of 14,211 populated · 21 distinct

| Most common value | Rows |
|---|---|
| `` | 539 |
| `NA` | 16 |
| `31/36` | 8 |
| `200-5` | 7 |
| `5/10 Y` | 4 |
| `5/2.5` | 4 |

**Meaning:** TODO

**Notes:**

### `CT_AUX3`

`char(8)` · 583 of 14,211 populated · 12 distinct

| Most common value | Rows |
|---|---|
| `` | 541 |
| `NA` | 15 |
| `2.5-5` | 8 |
| `5-2.5` | 5 |
| `20/5` | 4 |
| `5/0.75` | 2 |

**Meaning:** TODO

**Notes:**

### `CT_AUX4`

`char(8)` · 562 of 14,211 populated · 3 distinct

| Most common value | Rows |
|---|---|
| `` | 545 |
| `NA` | 15 |
| `WYE` | 2 |

**Meaning:** TODO

**Notes:**

### `PT_AUX`

`char(8)` · 1,124 of 14,211 populated · 67 distinct

| Most common value | Rows |
|---|---|
| `` | 457 |
| `NA` | 110 |
| `115/100V` | 46 |
| `120/208` | 44 |
| `600-1` | 41 |
| `1200-1` | 35 |

**Meaning:** TODO

**Notes:**

### `REMARKS1`

`char(25)` · 1,521 of 14,211 populated · 98 distinct

| Most common value | Rows |
|---|---|
| `` | 516 |
| `DELTA` | 184 |
| `WYE` | 149 |
| `PHASE` | 95 |
| `ISOLATION` | 83 |
| `NA` | 58 |

**Meaning:** TODO

**Notes:**

### `REMARKS2`

`char(25)` · 1,180 of 14,211 populated · 72 distinct

| Most common value | Rows |
|---|---|
| `` | 525 |
| `DELTA` | 207 |
| `Neutral` | 68 |
| `WYE` | 59 |
| `NA` | 57 |
| `IWDG2` | 29 |

**Meaning:** TODO

**Notes:**

### `REMARKS3`

`char(25)` · 769 of 14,211 populated · 36 distinct

| Most common value | Rows |
|---|---|
| `` | 537 |
| `WYE` | 37 |
| `NA` | 36 |
| `CORE BALANCE CT` | 13 |
| `DELTA` | 11 |
| `L0008` | 11 |

**Meaning:** TODO

**Notes:**

### `REMARKS4`

`char(25)` · 660 of 14,211 populated · 19 distinct

| Most common value | Rows |
|---|---|
| `` | 543 |
| `NA` | 36 |
| `T1` | 13 |
| `CORE BALANCE CT` | 12 |
| `L0018` | 11 |
| `UT1  Neutral` | 7 |

**Meaning:** TODO

**Notes:**

### `CDATE`

`datetime(8)` · 13,023 of 14,211 populated · 2,339 distinct

| Most common value | Rows |
|---|---|
| `2012-02-29 00:00:00` | 287 |
| `1989-02-28 00:00:00` | 114 |
| `1979-04-01 00:00:00` | 112 |
| `1985-01-16 00:00:00` | 109 |
| `1989-10-20 00:00:00` | 102 |
| `1976-06-01 00:00:00` | 102 |

**Meaning:** TODO

**Notes:**

### `VDATE`

`datetime(8)` · 12,938 of 14,211 populated · 2,483 distinct

| Most common value | Rows |
|---|---|
| `2006-05-10 00:00:00` | 102 |
| `2012-09-16 00:00:00` | 93 |
| `2025-06-09 00:00:00` | 88 |
| `2025-04-25 00:00:00` | 88 |
| `2013-02-20 00:00:00` | 81 |
| `1899-12-30 00:00:00` | 75 |

**Meaning:** TODO

**Notes:**

### `REMARKS5`

`nvarchar` · 1,980 of 14,211 populated · 529 distinct

| Most common value | Rows |
|---|---|
| `` | 531 |
| `U/F PANEL=S001. 125 VDC` | 66 |
| `NA` | 31 |
| `GROUNDING RESISTOR=480 OHMS.` | 24 |
| `DC GROUND DETECTION NOT USED.` | 20 |
| `PANEL 2728` | 18 |

**Meaning:** TODO

**Notes:**

### `CLASS`

`char(2)` · 13,892 of 14,211 populated · 5 distinct

| Most common value | Rows |
|---|---|
| `MP` | 5,097 |
| `EM` | 4,839 |
| `SS` | 3,949 |
| `` | 4 |
| `M` | 3 |

**Meaning:** **Dropped at cutover — untrusted (#194, owner 2026-09-19: "all can go … I do not trust any of the data in those fields").** Not the relay technology: on DEV, MP sits on 286 electromechanical models and EM on 917 microprocessor ones; SS splits 1,638 / 1,529. Meaning never established.

**Notes:**

### `USE`

`char(1)` · 13,879 of 14,211 populated · 11 distinct

| Most common value | Rows |
|---|---|
| `M` | 9,166 |
| `T` | 2,470 |
| `D` | 959 |
| `B` | 700 |
| `A` | 212 |
| `R` | 139 |

**Meaning:** **Dropped at cutover — untrusted (#194, owner 2026-09-19: "all can go … I do not trust any of the data in those fields").** By the models it sits on it reads as a device function class (M protection relays, T timers, D differentials, B breaker failure, A auxiliaries, R reclosers) — the platform's per-relay capability checklist (#181) is finer and true per device.

**Notes:**

### `RESPONSIBILITY`

`char(15)` · 13,880 of 14,211 populated · 17 distinct

| Most common value | Rows |
|---|---|
| `Bathurst` | 4,411 |
| `Saint John` | 3,051 |
| `Fredericton` | 2,470 |
| `Moncton` | 2,374 |
| `Grand Falls` | 1,509 |
| `All` | 25 |

**Meaning:** **Dropped at cutover — untrusted (#194, owner 2026-09-19: "all can go … I do not trust any of the data in those fields").** The five regional offices (plus "All" and typos); 142 of 223 stations carry more than one across their records, so it was per record, not per station.

**Notes:**

### `Bulk_Power_Element`

`bit(1)` · 14,210 of 14,211 populated · 2 distinct

| Most common value | Rows |
|---|---|
| `False` | 11,185 |
| `True` | 3,025 |

**Meaning:** **Dropped at cutover — untrusted (#194, owner 2026-09-19: "all can go … I do not trust any of the data in those fields").** The platform's fact is the NPCC A-10 classification on the protected bus (#170, #184); this flag is not used to seed it.

**Notes:**

### `Protection_Group`

`char(1)` · 14,211 of 14,211 populated · 3 distinct

| Most common value | Rows |
|---|---|
| `O` | 9,214 |
| `A` | 2,889 |
| `B` | 2,108 |

**Meaning:** **Dropped at cutover — untrusted (#194, owner 2026-09-19: "all can go … I do not trust any of the data in those fields").** A/B agree with the scheme name (…A-PROT / …B-PROT) about 85 % of the time and disagree otherwise; the scheme is the home of a group, when one is recorded.

**Notes:**

### `ELEMENT`

`char(1)` · 13,865 of 14,211 populated · 7 distinct

| Most common value | Rows |
|---|---|
| `O` | 6,374 |
| `L` | 4,702 |
| `Y` | 1,990 |
| `U` | 789 |
| `` | 5 |
| `T` | 3 |

**Meaning:** **Dropped at cutover — untrusted (#194, owner 2026-09-19: "all can go … I do not trust any of the data in those fields").** L sits on line schemes, Y on transformer (T1/T2) schemes and differential relays, U on underfrequency schemes; the platform's fact is what the scheme protects (SchemeProtects).

**Notes:**

### `MANUFACTURER`

`char(50)` · 13,655 of 14,211 populated · 46 distinct

| Most common value | Rows |
|---|---|
| `CGE` | 3,440 |
| `SEL` | 3,414 |
| `Westinghouse` | 1,488 |
| `GEC` | 771 |
| `Agastat` | 760 |
| `ABB` | 654 |

**Meaning:** TODO

**Notes:**

### `LINE_TYPE`

`char(50)` · 3,904 of 14,211 populated · 12 distinct

| Most common value | Rows |
|---|---|
| `G` | 2,577 |
| `R` | 747 |
| `` | 442 |
| `N/A` | 113 |
| `0` | 12 |
| `na` | 4 |

**Meaning:** **Dropped at cutover — untrusted (#194, owner 2026-09-19: "all can go … I do not trust any of the data in those fields").** G/R, only on lines, meaning never established; a line property would belong on the line asset.

**Notes:**

### `NUMBER OF RELAYS`

`int(4)` · 13,882 of 14,211 populated · 5 distinct

| Most common value | Rows |
|---|---|
| `1` | 12,515 |
| `3` | 1,343 |
| `2` | 18 |
| `0` | 5 |
| `11` | 1 |

**Meaning:** **Dropped at cutover — untrusted (#194, owner 2026-09-19: "all can go … I do not trust any of the data in those fields").** One settings file for three single-phase relays (the owner, 2026-09-19). In the platform that is one settings-bearing asset with three components (asset.AssetComponent) — a derived count, not a typed one; the legacy count is not migrated.

**Notes:**

### `VOLTAGE`

`int(4)` · 4,595 of 14,211 populated · 12 distinct

| Most common value | Rows |
|---|---|
| `138` | 1,964 |
| `69` | 889 |
| `345` | 816 |
| `0` | 558 |
| `230` | 310 |
| `13` | 18 |

**Meaning:** TODO

**Notes:**

### `IDATE`

`datetime(8)` · 0 of 14,211 populated · 0 distinct

**Meaning:** TODO

**Notes:**

---

## `dbo.LOCATIONS` — 825 rows

### `Location`

`nchar(30)`, not null · 825 of 825 populated · 231 distinct

| Most common value | Rows |
|---|---|
| `MACTAQUAC PLANT TERMINAL` | 48 |
| `PENNFIELD TERMINAL` | 47 |
| `BEECHWOOD PLANT TERMINAL` | 46 |
| `EEL RIVER TERM 138` | 30 |
| `EEL RIVER TERMINAL` | 23 |
| `COLESON COVE UNIT 1` | 19 |

**Meaning:** TODO

**Notes:**

### `USERNAME`

`nchar(20)` · 825 of 825 populated · 5 distinct

| Most common value | Rows |
|---|---|
| `Eng` | 607 |
| `Dist` | 142 |
| `Gen` | 46 |
| `Hydro` | 20 |
| `CCove` | 10 |

**Meaning:** TODO

**Notes:**

