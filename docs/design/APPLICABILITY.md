# Applicability — the layers that decide which standards bind a device

Started 2026-09-19 (#197) at the owner's request: *"These 'layers' of applicability for the various standards are incredibly
important as they are the kick off point for the various requirements … it would be valuable to start some form of
applicability flowchart for each of the standards so that we can build off of them … These are the things that we need to
ensure we get correct, so that devices don't fall through the cracks."*

One chart per standard. Every box names the fact the rule reads (`tools/compliance_rules.py` is the source of the rules;
`compliance.vFactCatalogue` of the facts). A box marked **open** is a layer the standard has and the platform does not
model yet; it is listed so it is not forgotten, not because a rule reads it. Nothing in a chart is a rule: the rules are
`Program.ObligationRule` definitions and the derivations `Program.ClassificationDerivation` definitions; the charts describe
them.

Conventions the charts share (rulings on record in `docs/decisions/DECISION-LOG.md`):

- **Nothing here is from memory** (the owner, 2026-09-19: *"when dealing with compliance, never go by memory, all must be
  verified against the particular standard in question"*). A box states what a standard says only when that standard's
  text, in the version in force in New Brunswick, was read and the clause is named. A layer the standard is believed to
  have but whose text has not been read is a **to read** box: it names the document to open, not what it says.
- **Applicability comes from the primary asset and the device's own nature** (#171, memory
  `feedback-applicability-from-primary-assets`): the element the scheme protects carries the BES status, the PRC-023 listing
  and the A-10 declaration; the building carries the CIP impact rating (#195); the device carries what only it can — its
  technology, its routable connectivity, its elements in service.
- **Unknown is not false** (#171, #197): a fact nobody has recorded leaves the standard *undetermined* and the device on the
  undetermined list; the platform never declares a standard inapplicable on a fact it cannot read.
- **A standard that does not bind must not appear against the device** (#173) — but **the reason must** (#197): the
  Compliance tab lists each standard that does not apply with what the rule read.

## CIP-002 → CIP-004/005/006/007/010/011 (cyber security)

```mermaid
flowchart TD
    T[device.technology<br/>ref.Model.Technology] -->|Microprocessor or IEC61850| CA[Cyber Asset]
    T -->|Electromechanical or Static| NCA[not a cyber asset<br/>no CIP requirement]
    CA --> E{device.protects.classification.BesStatus<br/>the protected element}
    E -->|BES| BCA[BesCyberAsset = BCA<br/>derived, never typed]
    E -->|Not BES| NB[BesCyberAsset = Not BCA]
    E -->|unrecorded| U1[undetermined]
    BCA --> R{device.location.classification.CipImpactRating<br/>the BUILDING the device is in, #195}
    R -->|High or Medium| CIP[CIP-004 R2 R4 · CIP-006 R1 · CIP-007 R1-R5 · CIP-010 R1-R3 · CIP-011 R1]
    R -->|Low| LOW[to read: whether a Low rating carries requirements of its own — CIP-003, not in the seed; its NB version not yet recorded]
    R -->|no building rated| U2[undetermined]
    CIP --> PARTS[to read: whether ERC selects requirement parts within CIP-005 / 007 / 010 — from those standards' texts]
    CIP --> ERC{device.classification.ExternalRoutableConnectivity<br/>recorded by hand}
    ERC -->|ERC| C5[CIP-005 R1]
    ERC -->|No ERC| C5N[CIP-005 R1 does not apply]
    CA --> PCA[open: Protected Cyber Asset —<br/>a Cyber Asset on the same network as a BCA<br/>takes the BCA's requirements though it is not 15-minute impactful]
    BCA --> FIFTEEN[open: the 15-minute test of the BES Cyber Asset definition —<br/>today every microprocessor relay protecting a BES element is taken as one]
```

What the rules read today (`CIP_SCOPE`): `device.classification.BesCyberAsset = 'BCA' and
device.location.classification.CipImpactRating in {'High', 'Medium'}`; CIP-005 R1 adds
`and device.classification.ExternalRoutableConnectivity = 'ERC'` (`CIP_ERC_SCOPE`). The BCA flag is the derivation
`bes_cyber_asset`: BCA when `device.technology in {'Microprocessor', 'IEC61850'} and
device.protects.classification.BesStatus = 'BES'`, else Not BCA; undetermined while the element's BES status is unrecorded.

Open layers, in the owner's words (2026-09-19): *"Once a building has been deemed to be a particular level … then all devices
in that building will need to be categorized, no matter whether or not they are '15-minute impactful' or not to the BES …
any device which is located on the same network, whether or not it is impactful, has much the same requirements … these
devices would be categorized as PCA (protected cyber asset) since … if they were compromised, that would be a door into the
BCAs which are on the same network."* The platform has the facts a PCA layer needs in outline — `network.port`,
`network.vlan`, `network.services` on a device, and `device.connections` — but no rule reads them for this yet and no
classification kind `ProtectedCyberAsset` exists. To read before anything is built on them: whether external routable
connectivity selects requirement *parts* within CIP-005/007/010 (the note of 2026-09-19 that said so was from memory and
does not count), and what a Low impact rating carries (CIP-003). The PCA definition itself is to be read from the NERC
Glossary and CIP-002 before a rule is written; the owner's description above is the requirement, not the text.

## PRC-023-6 (transmission relay loadability)

```mermaid
flowchart TD
    P[device.protects — the element the scheme protects<br/>compliance.fDeviceProtects] --> V{4.2 Circuits}
    V -->|device.protects.terminal.voltage >= 200 kV| C1[4.2.1.1 / 4.2.1.4 in scope]
    V -->|device.protects.classification.Prc023 = Listed<br/>the Planning Coordinator's R6 list| C1
    V -->|neither| NO1[R1 does not apply — the circuit]
    C1 --> F{4.1 / Attachment A — the elements in service<br/>device.functions = scheme.CommissionedFunction at the position}
    F -->|any element ruled load-responsive<br/>21 · 78 · SOTF · 50 · 51 · 67, not ground| R1[PRC-023 R1 binds]
    F -->|every element ruled not — 50N 51N 67N ground A 2.2,<br/>87 · 25 · 27 · 59 · 79 · 50BF not listed| NO2[R1 does not apply — no in-service load-responsive element<br/>device.functions.note says which and why]
    F -->|an element nobody has ruled| U[undetermined — 1 437 of 3 203 commissioned rows on DEV]
    R1 --> CRIT[asset.formula.prc023_criterion<br/>criterion 1, then 2, then 13, then 12]
    CRIT -->|13| R3[PRC-023 R3]
    CRIT -->|2| R4[PRC-023 R4 yearly list]
    CRIT -->|12| R5[PRC-023 R5 yearly list to NPCC]
    V --> X1[open: 4.2.1.4 transformers — the LOW-voltage terminal's connection at 200 kV, not the element's voltage]
    V --> X2[open: 4.2.1.1 GSU-to-transmission elements used only to export a BES generator are excluded]
    F --> X3[open: Attachment A 2.8 / 2.9 — relay elements of dc lines and dc converter transformers are excluded<br/>Eel River HVDC: nothing marks a dc line or a converter transformer yet]
    F --> X4[open: Attachment A 2.1 — elements enabled only on loss of potential or loss of communications]
    F --> X5[open: enablement from the settings themselves — the SEL-221F's MTU/MPT/MTO masks decide which elements trip;<br/>decoded from the manual's 3-20 table, they fill CommissionedFunction.EnabledFromConfigurationFileRevisionRowId]
```

What the rule reads today (`PRC_R1_SCOPE`, #197): `(device.protects.terminal.voltage >= 200kV or
device.protects.classification.Prc023 = 'Listed') and device.functions[load_responsive='true'] is not empty`. The function
ruling lives on `ref.AnsiFunction.LoadResponsive` / `LoadResponsiveBasis` (the core seed, each with its Attachment A
clause); a legacy code such as `50/51N` or `21-B` is judged by `ref.fAnsiLoadResponsive` (its numbers, ground when N or G
follows the digits). Read from PRC-023-6 itself (FERC letter order 2024-01-24), the copy `Seed_compliance_Standards_NB.sql`
cites.

## NPCC Directory 4 (bulk power system protection design)

```mermaid
flowchart TD
    P[device.protects — the element the scheme protects] --> D{device.protects.classification.NpccBulkPowerSystem<br/>the element's own A-10 declaration, #196}
    D -->|declared on the element| DV{value}
    D -->|no declaration| B{the bus at the terminal the scheme protects from<br/>fDeviceProtects.BusAssetEntityId}
    B -->|bus declared| DV
    B -->|nothing declared| U[undetermined]
    DV -->|BPS| D4[NPCC D4 R5.1 binds — a design criterion; the TFSP evidence is kept outside the platform]
    DV -->|Not BPS| NO[does not apply]
    D --> X1[open: the studies group's bus database and a connectivity model replace the hand entry; a hand-entered element that disagrees is flagged, not overwritten]
```

## How a layer gets added

1. The fact first: a column, a classification kind, or a derivation — and its row in `compliance.vFactCatalogue` with the
   branch in `fFactRead` / `fFixedFactValue` that reads it.
2. Then the rule term, in `tools/compliance_rules.py`, regenerated into `Seed_config_ObligationRules.sql` (a new rule version
   by payload; the old obligations close on the next Effective run, with the reads that closed them).
3. Then the screen shows the fact where the rating is shown, and the reason line names it when the rule reads false.
4. Then this file: the box moves from **open** to a fact.
