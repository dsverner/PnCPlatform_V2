# Applicability — one flowchart, every standard attached where it binds

Started 2026-09-19 (#197) at the owner's request; rebuilt the same day (#199) after his corrections and a reading of the
texts: *"These 'layers' of applicability for the various standards are incredibly important as they are the kick off point
for the various requirements … the next logical step in these flowcharts is to incorporate all of them into a single
flowchart with the various standards attached to them at the appropriate locations."*

**Nothing here is from memory** (the owner, 2026-09-19, #198). Every box that states what a standard says was read from
the text named in *Sources* at the end, in the version in force in New Brunswick on 2026-09-19 (nbeub.ca), and names the
clause. A box marked **to read** names a document not yet read and asserts nothing of its content. A box marked **rule
differs** is where the platform's rule today (`tools/compliance_rules.py`) reads the standard wrongly; those are the next
increment, listed at the end.

Colour key of the drawn page (the same words are in the boxes here): *fact* — a fact a rule reads or a test the standard
sets; *binds* — requirements attach here; *does not apply* — with the reason kept; *undetermined* — a fact nobody has
recorded; *open / to read* — a layer not modelled or a text not read.

## The chart

```mermaid
flowchart TD
    DEV["A protection device at its position<br/>asset.vPlacedAsset · the scheme it belongs to · the element the scheme protects"]

    %% ───────────────── cyber security: CIP ─────────────────
    DEV --> EX{"CIP-002 / 005 / 006 … 4.2.3 exemptions<br/>Cyber Assets at a Facility regulated by the Canadian Nuclear Safety Commission (4.2.3.1);<br/>Cyber Assets of communication networks and data links between discrete ESPs (4.2.3.2)"}
    EX -->|exempt| EXO["exempt from the CIP standards — open: nothing marks a CNSC-regulated Facility or an inter-ESP link"]
    EX -->|not exempt| T{"device.technology (ref.Model.Technology)<br/>Glossary: a Cyber Asset is a programmable electronic device"}
    T -->|Electromechanical or Static| NCA["not a Cyber Asset — no CIP requirement attaches to the device"]
    T -->|Microprocessor or IEC61850| CA["Cyber Asset"]
    CA --> BCAQ{"BES (BPS) Cyber Asset test — NB appendix CIP-002-5.1a-NB-0 §G:<br/>if unavailable, degraded or misused, would it within 15 minutes adversely impact a Facility<br/>whose loss affects the reliable operation of the bulk power system? Redundancy not considered.<br/>Platform proxy today: protects an element classified BES (BesStatus) — the 15-minute judgement itself is not modelled"}
    BCAQ -->|yes| BCA["BES Cyber Asset (BesCyberAsset = BCA, derived) — grouped into a BES Cyber System, CIP-002 R1"]
    BCAQ -->|no| PCAQ{"connected using a routable protocol within or on the ESP of a BES Cyber System?<br/>Glossary PCA, in force to 2028-06-30 — open: no ESP is modelled; network.port / network.vlan exist"}
    BCAQ -->|element's BES status unrecorded| U1["undetermined"]
    PCAQ -->|yes| PCA["Protected Cyber Asset — takes the impact rating of the highest BES Cyber System in the same ESP<br/>(from 2028-07-01: protected by an ESP, or sharing CPU or memory with the BCS; TCAs excluded)"]
    PCAQ -->|no| NOC["no CIP requirement (a device connected 30 days or less for maintenance is a Transient Cyber Asset — CIP-010 R4 plans, not these rules)"]
    BCA --> RATE{"impact rating — CIP-002 Attachment 1, evaluated per station or substation (the platform holds it on the building, #195)<br/>High 1.1–1.4: Control Centers only · Medium 2.4: Facilities at 500 kV and above · 2.5: 200–499 kV at a station connected at 200 kV+ to 3 or more other stations, weighted value over 3000 (700 per 200–299 kV line, 1300 per 300–499 kV line) · 2.6 IROL-critical · 2.7 NPIR · 2.8 generation interconnection · 2.9 SPS/RAS · 2.10 UFLS/UVLS 300 MW+<br/>Low 3.2: every other BES Cyber System at a transmission station (R1.3: no discrete list required)"}
    PCA --> RATE
    RATE -->|no station criterion met, no rating recorded| U2["undetermined"]
    RATE -->|Low| LOW["Low impact — CIP-003-8-NB-0 in force, CIP-003-9-NB-0 effective 2026-10-01 — to read"]
    RATE -->|High| HIGH["High impact — a Control Center's systems; not a substation relay"]
    RATE -->|Medium| MED["Medium impact BES Cyber System (and its PCA)"]
    MED --> MALL["binds, ERC or not — BCS + EACMS + PACS + PCA unless noted:<br/>CIP-004 R1.1 (BCS only) · CIP-005 R1.1 (BCS + PCA) · CIP-006 R1.1 (BCS without ERC: procedural physical controls)<br/>CIP-007 R2.1–2.4, R3.1–3.3, R4.1, R5.2, R5.4, R5.5 · CIP-010 R1.1–1.4, R1.6, R3.1, R3.4, R4 (BCS + PCA)<br/>CIP-011 R1.1–1.2 (BCS + EACMS + PACS — not PCA), R2.1–2.2"]
    MED --> ERC{"External Routable Connectivity — of the BCS through its ESP, not of the relay<br/>Glossary: access to a BCS from a Cyber Asset outside its ESP via a bi-directional routable protocol connection<br/>platform: device.classification.ExternalRoutableConnectivity, by hand"}
    ERC -->|ERC| MERC["binds with ERC — adds:<br/>CIP-004 R2.1–2.3, R3.1–3.5, R4.1–4.3, R5.1–5.2, R6.1–6.3 (BCS + EACMS + PACS — not PCA)<br/>CIP-005 R1.2 (BCS + PCA), R2.1–2.5 (BCS + PCA), R3.1–3.2 (EACMS + PACS)<br/>CIP-006 R1.2, R1.4, R1.5, R1.8, R1.9, R2.1–2.3, R3.1 (BCS + EACMS + PCA; PACS for 1.6, 1.7, 3.1)<br/>CIP-007 R1.1, R4.2, R5.1, R5.3, R5.6"]
    ERC -->|No ERC| MNOE["with No ERC these do not apply: the CIP-004 R2–R6 parts, CIP-005 R1.2 and R2, CIP-006 R1.2–1.9 and R2, CIP-007 R1.1, R4.2, R5.3, R5.6"]
    ERC -->|unrecorded| U3["undetermined"]
    MED --> MCC["Medium at Control Centers only — not a substation relay:<br/>CIP-005 R1.5 · CIP-006 R1.10 · CIP-007 R1.2, R4.3, R5.1, R5.7"]
    HIGH --> HONLY["High only: CIP-004 R5.3–5.4 · CIP-006 R1.3 · CIP-007 R4.4 · CIP-010 R1.5, R2.1, R3.2, R3.3"]
    MED --> DIAL["Dial-up Connectivity: CIP-005 R1.4 (BCS + PCA) — open: not modelled"]

    %% ───────────────── protection settings: PRC-023-6 ─────────────────
    DEV --> P["device.protects — the element the scheme protects (compliance.fDeviceProtects)"]
    P --> V{"PRC-023-6 4.2 circuits"}
    V -->|"line operated at 200 kV and above (4.2.1.1) — except an element connecting a GSU used only to export a BES generator"| C1["circuit in scope"]
    V -->|"transformer whose LOW-voltage terminal connects at 200 kV and above (4.2.1.4) — rule differs: the rule reads one terminal's voltage"| C1
    V -->|"100–200 kV, or below 100 kV and BES, on the Planning Coordinator's R6 list (4.2.1.2/3/5/6) — device.protects.classification.Prc023 = Listed"| C1
    V -->|neither| NO1["PRC-023 does not apply — the circuit"]
    C1 --> F{"4.1 / Attachment A — the elements in service at the position (device.functions)<br/>included A.1: phase distance 1.1 · out-of-step 1.2 · switch-on-to-fault 1.3 · overcurrent 1.4 · comms-aided POTT/PUTT/DCB/DCUB 1.5 · phase OC supervision of current-based pilot schemes that trip on loss of comms 1.6<br/>excluded A.2: enabled only when other relays fail, e.g. on loss of potential 2.1 · ground fault detection 2.2 · RAS-only 2.5 · 15-minute-or-slower 2.6 · thermal emulation 2.7 · dc lines 2.8 · dc converter transformers 2.9"}
    F -->|"an element ruled load-responsive (21 · 78 · SOTF · 50 · 51 · 67, not ground)"| R1["PRC-023 R1 binds — any one of criteria 1–13 at 0.85 pu and 30°"]
    F -->|"every element ruled not (ground A 2.2; 87T, 25, 27, 59, 79, 50BF not listed) — rule differs: 87 is blanket-ruled; A 1.6 brings a line differential scheme's phase OC supervision in"| NO2["does not apply — no in-service load-responsive element; device.functions.note says which and why"]
    F -->|an element nobody has ruled| U4["undetermined — 1 437 of 3 203 commissioned rows on DEV"]
    F --> X3["open: A 2.8 / 2.9 — Eel River HVDC's dc-side and converter-transformer relays are excluded; nothing marks them"]
    F --> X4["open: A 2.1 — an element enabled only on loss of potential or loss of communications; open: enablement from the settings masks (SEL-221F MTU/MPT/MTO)"]
    R1 --> CRIT["asset.formula.prc023_criterion — the group applies 1, then 2, then 13, then 12 (owner, 2026-09-16)"]
    CRIT -->|"7, 8, 9, 12 or 13 — rule differs: the rule reads 13 only"| R3["PRC-023 R3 — the calculated capability becomes the Facility Rating, agreed with PC, TOP, RC"]
    CRIT -->|2| R4["PRC-023 R4 — yearly circuit list to PC, TOP, RC (15 months at most)"]
    CRIT -->|12| R5["PRC-023 R5 — yearly circuit list to the Regional Entity (NB appendix: NPCC)"]

    %% ───────────────── design: NPCC Directory 4 ─────────────────
    P --> D{"NPCC A-10: device.protects.classification.NpccBulkPowerSystem — the element's declaration, else the bus's at the protected terminal (#196)"}
    D -->|BPS| D4["NPCC Directory 4 R5.1 binds — a design criterion; TFSP evidence kept outside the platform (text read at #184, not re-read)"]
    D -->|Not BPS| NO3["does not apply"]
    D -->|nothing declared| U5["undetermined — open: the studies group's bus database and a connectivity model"]
```

## Where each requirement sits — read from the Applicable Systems columns

| Standard (NB version in force) | Applies to Medium **without** ERC | Applies to Medium **with** ERC only | Medium at Control Centers only | High only | Reaches PCA? |
|---|---|---|---|---|---|
| CIP-004-7 | R1.1 | R2.1–2.3, R3.1–3.5, R4.1–4.3, R5.1–5.2, R6.1–6.3 | — | R5.3, R5.4 | No (EACMS, PACS only) |
| CIP-005-7 | R1.1 | R1.2, R2.1–2.5, R3.1–3.2 (EACMS, PACS) | R1.5 (EAPs) | — | Yes (R1, R2) |
| CIP-006-6 | R1.1 | R1.2, R1.4, R1.5, R1.6–1.7 (PACS), R1.8, R1.9, R2.1–2.3, R3.1 | R1.10 | R1.3 | Yes (R1, R2) |
| CIP-007-6 | R2.1–2.4, R3.1–3.3, R4.1, R5.2, R5.4, R5.5 | R1.1, R4.2, R5.1, R5.3, R5.6 | R1.2, R4.3, R5.1, R5.7 | R4.4 | Yes (all) |
| CIP-010-4 | R1.1–1.4, R1.6, R3.1, R3.4, R4 | — | — | R1.5, R2.1, R3.2, R3.3 | Yes (R1, R3, R4) |
| CIP-011-3 | R1.1–1.2, R2.1–2.2 | — | — | — | R2 yes; R1 no |
| PRC-023-6 | R1 where 4.2 and Attachment A both hold; R3 for criteria 7, 8, 9, 12, 13; R4 for criterion 2; R5 for criterion 12 | | | | |
| CIP-003-8 (Low) | to read | | | | |

"Medium" here means a Medium impact BES Cyber System and, where the column says so, its associated EACMS, PACS and PCA.
A relay that is a PCA in a Medium ESP takes the PCA-reaching parts and none of CIP-004 or CIP-011 R1.

## What the platform's rules must change (the next increment)

Read against the texts above, five of the thirteen CIP rules and two PRC-023 pieces are wrong today:

1. `cip004_r2`, `cip004_r4` — bind only with ERC at Medium (they bind every Medium BCA today).
2. `cip005_r1` — part 1.1 binds every Medium BCS and its PCA, ERC or not; only 1.2 carries ERC (the rule carries ERC for all of R1).
3. `cip007_r1` — part 1.1 binds Medium only with ERC (the rule binds without).
4. `cip010_r2` — High only; never at a Medium substation (the rule opens it there).
5. `prc023_r3` — criteria 7, 8, 9, 12 or 13 (the rule reads 13 only).
6. `ref.AnsiFunction` ruling for 87 — right for 87T; A 1.6 brings the phase overcurrent supervision of a current-based pilot
   scheme (line differential included) in when the scheme trips on loss of communications: rule 87L's supervising elements
   per scheme, not by the number.
7. The rules are written per requirement; the standards bind per **part**. The honest shape is one rule per part-group
   (the rows of the table above), so an obligation names the parts it stands for.

Also open, with no rule yet: the PCA layer (needs an ESP model); the exemptions (CNSC facility; inter-ESP links); Low
impact (CIP-003, to read); Dial-up; the NB Regulation's definition of the bulk power system, which is what "BES" means in
every NB appendix (to read); the NB appendices of CIP-004 to CIP-011 (their §G definitions not read this session).

## Sources read (2026-09-19)

- PRC-023-6 — https://www.nerc.com/pa/Stand/Reliability%20Standards/PRC-023-6.pdf (4.1, 4.2, R1–R6, Attachment A, B).
- CIP-002-5.1a — https://www.nerc.com/pa/Stand/Reliability%20Standards/CIP-002-5.1a.pdf (4.2, 4.2.3, R1, Attachment 1, Background p. 5–6) and NB Appendix CIP-002-5.1a-NB-0 (§G BPS Cyber Asset / BPS Cyber System; "BES" means the NB Regulation's bulk power system; in force 2017-06-07).
- CIP-004-7, CIP-005-7, CIP-006-6, CIP-007-6, CIP-010-4, CIP-011-3 — the NERC texts at the same host, Requirements and Measures tables (every part's Applicable Systems); 4.2.3 exemptions of CIP-005-7 and CIP-006-6.
- NERC Glossary of Terms (https://www.nerc.com/glossary-of-terms, read 2026-09-19): Cyber Assets, BES Cyber Asset, BES Cyber System, Protected Cyber Assets, External Routable Connectivity, Electronic Security Perimeter, EACMS, PACS, Transient Cyber Asset — the definitions in force (inactive 2028-06-30) and their 2028-07-01 successors.
- nbeub.ca/reliability-standards — versions and effective dates (CIP-002-5.1a-NB-0, CIP-003-8-NB-0, CIP-004-7-NB-0, CIP-005-7-NB-0 in force; CIP-003-9-NB-0 effective 2026-10-01; the -8/-9/-10/-11 CIP versions effective 2028-10-01).
- NPCC Directory 4 — read at #184 from npcc.org; not re-read this session.
