# Requirements — NB Power P&C Platform

**Version 0.2** · 2026-09-11 · project VGS-PRJ-2026-001

Derived from seven structured interview rounds with the owner, the contract documents, and direct
measurement of the live databases. Every requirement carries its provenance. Nothing here is
invented to fill a gap — where something is unknown, `docs/OPEN-QUESTIONS.md` says so.

v0.1 was reviewed by the owner, who marked 29 requirements *keep* and 2 *change*. Both changes are
incorporated below and noted in the provenance.

## Phase markers

| Marker | Meaning |
|---|---|
| **P1** | In the binding four-week Phase 1 delivery |
| **shape** | Schema carries the structure now so it costs nothing later. No data, no screens, no build |
| **later** | A Phase 2–5 capability the architecture must not preclude |

---

## 1. What this system is

The platform is the P&C group's **engineering work environment**. Its distinguishing capability is
that **the procedures the group follows are authored in the application, not written in code** —
the settings-change process, the test procedures, the compliance routines. A change in group
practice is a new definition version, never a software release.

This is the answer to the question that started the rebuild. The legacy environment hard-codes the
settings lifecycle into three states, encoded in the primary key and in document filenames, and
that is the constraint the platform exists to remove.

The relay settings book is Phase 1 and is the first procedure the engine runs. It is not the
product; it is the proof.

### The tension this design carries

The owner named the **work environment** as the thing that must never be compromised, and then
named four **system-of-record** guarantees as must-never-fail. These pull opposite ways: a work
environment wants drafts, speed and mutability; a record wants immutability and as-of truth.

**How the design resolves it:** work is mutable until a procedure step commits it, and committed
facts are immutable thereafter. The procedure engine is the boundary between the two worlds —
that is its second job, after configurability. Every requirement below is consistent with that
rule, and where one would break it, it says so.

---

## 2. Actors

Seven account types are fixed by the SOW (§5.2.3). Two working populations use the system in
genuinely different ways: engineers at desks, technicians in the field and substantially offline.

| Account type | Primary use |
|---|---|
| Administrator | Authors and approves definitions — procedures, workflows, templates, rules. Grants access |
| Transmission P&C Engineer | Designs, calculates, checks, approves settings within scope |
| Distribution P&C Engineer | As above, distribution scope |
| Hydro Generation Engineer | As above, hydro generation scope |
| Belledune Generation Engineer | As above, Belledune scope |
| Coleson Generation Engineer | As above, Coleson scope |
| P&C Technician | Applies settings, performs tests, captures records — substantially offline |

Scope spans Transmission, Distribution and Generation, each with configurable read / modify /
approve / archive / report permissions.

---

## 3. The procedure engine

Two deliberate layers. A **workflow** governs the lifecycle of a thing; a **procedure** governs
the doing. A workflow step invokes a procedure, and the procedure's completion satisfies the
step's guard.

### FR-1.1 — Procedures are authored definitions, never code · **P1**

Every procedure the P&C group follows is a versioned, approved definition held as data and
interpreted at runtime. A change in group practice produces a new definition version. No
procedure, and no step of one, is expressed in application source.

> *Provenance:* Round 4 — *"There can be no hard coded procedures."* Agrees with PnCPlatform
> decision #45.

### FR-1.2 — The procedure vocabulary · **P1**

A procedure definition can express: ordered steps · typed data capture at a step · conditional
branching · guards and preconditions · role and competency per step · sign-off with attribution ·
evidence attached at a step · parallel branches · sub-procedures · timing and due dates · hold
points and suspension · recorded deviation.

> *Provenance:* Round 5 — twelve of fourteen offered capabilities selected.

### FR-1.3 — In-flight work is pinned to its procedure version · **P1**

Work already underway continues against the procedure version it started on. Revising a procedure
never alters running work. The version in force is recorded on the instance.

> *Provenance:* Round 6. The owner reversed his own Round 5 answer once the conflict with
> point-in-time truth (FR-4.1) was put to him.

### FR-1.4 — A procedure can iterate over a set · **P1**

A procedure can repeat a group of steps once per member of a set — the eleven relays in one
settings package — while remaining one instance reviewed and approved as a whole.

> *Provenance:* Round 6, reversing the Round 5 answer. Reinforces PnCPlatform decision #60, that
> the settings-issue package is the approval subject.

### FR-1.5 — Authoring is a first-class application surface · **P1**

An Administrator authors, versions, tests and approves procedure definitions inside the
application, without developer involvement and without database access. A definition that can only
be authored by a developer does not satisfy FR-1.1.

> *Provenance:* Derived from FR-1.1. The owner authors procedures now; P&C engineers are expected
> to author them in a later phase, so the **model must admit a friendly authoring UI later without
> being reshaped**, even though the first editor is an expert surface.
>
> *Measured:* the predecessor's front end does permit authoring — `definitions.js` edits a version
> payload and approves it, with segregation of duties enforced — but the editor is a raw JSON
> textarea. Architecturally true, practically false for anyone but the author.

### FR-2.1 — Workflows govern lifecycle; procedures govern doing · **P1**

A workflow definition holds states, transitions, the roles permitted at each, and whether a
transition requires a reason. It governs the lifecycle of a subject. A workflow step may invoke a
procedure; the procedure's completion satisfies the step's guard.

> *Provenance:* Round 5 — *"two layers, deliberately."*
>
> *Measured:* no column anywhere in the predecessor's 302 tables connects a workflow to a
> procedure. The two layers exist and have never been joined. This is the largest structural gap.

### FR-2.2 — Work is mutable until a step commits it · **P1**

The procedure engine is the boundary between drafting and record. Before a committing step, work
is freely editable. After it, the fact is immutable and only a new valid-time assertion can
supersede it.

> *Provenance:* Derived — this is how the work-environment versus system-of-record tension in §1
> is resolved.

---

## 4. Settings and configuration

### FR-3.1 — The fourteen-step path is an authored procedure · **P1**

Request · scope and design · study · vendor tool · rationale · independent check · approval ·
issue · field application · readback · test · return to service · baseline · drawings. All
fourteen are real and distinct, and all fourteen are expressed in definitions rather than code.

> *Provenance:* Round 3 — all fourteen confirmed real and distinct.

### FR-3.2 — Approval precedes field application, always · **P1**

Nothing reaches a relay until it is approved. The approval subject is the settings-issue package;
approval cascades to the configuration-file revisions within it.

> *Provenance:* SOW. Agrees with PnCPlatform decisions #55 and #60.

### FR-3.3 — In-service is a separate fact from approved · **P1**

What is on the relay is recorded from readback, independently of what was approved. A readback
that differs is recorded as-found, raises a finding, and is resolved by restoring the approved
settings or issuing a change. The unapproved-in-service state is a transient discrepancy, never a
steady state.

> *Provenance:* Agrees with PnCPlatform decision #55. Consistent with work steps 10 and 13.

### FR-3.4 — Non-microprocessor devices are first-class · **shape**

Between half and three quarters of the estate is not a microprocessor relay. The model must hold
the configuration of an electromechanical or solid-state device — taps, links, settings recorded
as characteristics rather than a vendor file — without treating it as a degenerate case of a relay
with a settings file.

> *Provenance:* Round 4 dials — microprocessor share 25–50%. The most consequential number given.
>
> *Correction:* v0.1 of this document asserted that the predecessor schema did not take this
> seriously. That was wrong and was withdrawn after checking. `record.CharacteristicValue` and
> `asset.CharacteristicValue` are generic and typed, and `ref.AssetType` carries 79 Secondary and
> 11 Hybrid types against 56 Primary. The requirement stands; the predecessor already meets it.

---

## 5. The four answers

The questions the data must answer cold, years later. All four marked must-never-fail.

### FR-4.1 — Point in time · **P1**

*"What settings were in service on this relay on 12 March 2019, who approved them, and what did we
believe at the time?"* Requires valid time and transaction time on every fact a question can
reach, and the rule and fact versions recorded on anything derived.

> *Provenance:* Round 2 — must never fail.

### FR-4.2 — Proof of obligation · **shape**

*"Show me the evidence that this obligation was met for this period, for every device it applied
to."* Evidence links cite records, never files directly, so the chain survives a document moving.

> *Provenance:* Round 2 — must never fail. Depends on test results being owned by the platform;
> see §6.

### FR-4.3 — Impact, the answer that must not fail · **shape**

Eight triggers must be traceable to every device, scheme, document and record they touch: a
standard changes · a vendor advisory · the power system changes under a study · a template
revision · primary plant changes · a device replaced with a different model · an error found in
something already issued · a misoperation.

Impact works only if the relationships are modelled as data. **A relationship that exists only on
a drawing is not traceable.**

> *Provenance:* Round 3 — all eight confirmed. Round 2 — the one whose failure the owner would
> call a serious professional problem.

### FR-4.4 — Reconstruction · **later**

*"This scheme misoperated. Given what was actually in service and the system state at that
instant, why?"* Requires events as first-class facts joined to the in-service configuration as of
the event instant.

> *Provenance:* Round 2 — must never fail. SOW Phase 5 capability; the shape is laid down earlier.

---

## 6. The boundary

Who is right when two systems disagree. Live integration is outside Phase 1 by the proposal's own
exclusions — this table governs design, not wiring.

| Domain | Authority | How it works |
|---|---|---|
| Relay settings and configuration files | **OURS** | The settings book. The platform decides |
| Protection schemes | **OURS** | What protects what; functions, devices, members |
| Device identity and serial numbers | **OURS** | Which physical relay is where, and its history |
| Everything below the panel | **OURS** | Bays, junction boxes, cable routes, structures. Not in Cascade |
| Events, faults, misoperations | **OURS** | Relay operations and disturbance records |
| People, qualifications, authorisations | **OURS** | Competency and authorisation are not HR facts, and not SAP's |
| Standards and obligations | **OURS** | What the standards require, as interpreted here |
| Power-system model | **OURS** | Platform is master; ASPEN consumes an export |
| Wiring, cables, terminations | **OURS** | Schema carries the shape from day one. No Phase 1 data |
| Functional locations | **THEIRS** | Cascade supplies Region → Station → Building → Room → Panel |
| Work orders | **SPLIT** | Cascade owns the scheduled order; the platform owns the P&C Work Request and links to it |
| Asset registers, spares, materials | **SPLIT** | Platform owns P&C engineering facts — condition, obsolescence, installed base, replacement planning. SAP keeps purchase, stock, cost, warranty |
| Test and commissioning records | **SPLIT** | The test tool keeps the raw artefact. The platform owns the accepted result, the readings and the acceptance, and cites the file |
| Drawings and schematics | **SPLIT** | The drawing system holds the file. The platform records what each sheet depicts, by drawing key |

> *Provenance:* Round 6 grid, with five conflicts resolved in Round 7. The four SPLIT rows were all
> reconciliations of a conflict between the owner's first answer and either the contract or another
> of his own answers.

### FR-5.1 — One vocabulary per system of record · **P1**

Where another system is authoritative, the platform holds a reference and does not compete. Where
the split is real, the platform states exactly which part it owns. The term "work order" belongs
to Cascade; the platform's unit of work is the **Work Request**.

> *Provenance:* Round 7. Agrees with PnCPlatform decision #36.

### FR-5.2 — Drawings are traced by depiction, not by link · **P1**

The drawing system holds the file. The platform records which entities each sheet depicts, keyed
by slot, designation, cable number or panel-plus-wire-number, so that FR-4.3 traces through
drawings the platform does not own.

> *Provenance:* Round 7. Agrees with PnCPlatform decision #53, which already implements exactly
> this in `document.RevisionLink`.

### FR-5.3 — Test evidence stays inside the platform · **P1**

The test tool keeps its raw artefact. The platform owns the accepted result, the readings and the
acceptance decision, and cites the file. Acceptance is bi-temporal; the readings themselves are
valid-time.

> *Provenance:* Round 7. Agrees with PnCPlatform decision #42. Required by FR-4.2.

### FR-5.4 — Integration is designed, not built · **later**

Interface design and integration readiness for Cascade, SAP, ASPEN OneLiner and Line Constants are
Phase 1 deliverables. Live production integrations are change-controlled and outside the fixed
price.

> *Provenance:* Proposal §2.2 and §9 Exclusions.

---

## 7. Security, evidence and the field

### FR-6.1 — Identity is the person; the account type is a platform grant · **P1**

NB Power Active Directory authenticates a person as themselves. The seven account types are **not
directory groups** — they are grants the platform holds, resolved from the authenticated identity
to a person and from that person to their roles, each carrying configurable read, modify, approve,
archive and report permissions scoped across Transmission, Distribution and Generation.

A person's authority can therefore change without touching the directory, and every act is
attributed to the person, not to a shared account type.

> *Provenance:* SOW §5.2 and §5.2.3 — binding. **Corrected at the owner's mark on v0.1:** *"users
> will authenticate as themselves and then within the application they will be tied to the account
> types."* The first draft conflated directory identity with the account type.

### FR-6.2 — Read scope is as strict as write scope · **P1**

Visibility is governed by role, functional location and device type, for reads exactly as for
writes. The breadth of information held makes visibility itself a security concern.

> *Provenance:* Agrees with PnCPlatform decision #59, recorded there as the owner's position.

### FR-6.3 — No hard deletes; everything attributable · **P1**

Soft delete only. Created, modified and deleted by whom and when, on everything. Every act is
attributed to an actor — a person as themselves, under delegation, or a sponsored non-user — so
contractors and departed staff stay attributable.

> *Provenance:* Standing project rule. Agrees with PnCPlatform decision #44.

### FR-6.4 — Reads of configuration files and evidence are logged · **P1**

Read logging is on from day one for configuration files and evidence packages. Other reads are not
logged by default.

> *Provenance:* Agrees with PnCPlatform decision #65, where the owner changed position on the
> compliance lead's advice.

### FR-7.1 — The field pack · **later**

A technician checks out a scoped, time-limited, encrypted working set before going to site,
captures records offline, and checks in on return. Approvals, settings issue, model changes,
grants and definitions are **never** offline — the pack captures, it does not authorise. A pack
carries the row versions it was built from; a record citing a superseded reference is flagged for
the reviewer, never silently accepted.

> *Provenance:* Round 1 — field laptops, often offline. Design carried forward from PnCPlatform
> `PLATFORM-ARCHITECTURE.md` §7. Mobile **application** development is excluded by the proposal;
> this is the PWA, not an app.

### FR-7.2 — Browser-based access for all end users · **P1**

All end-user access is through a web browser, with filtering, search and navigation by station,
terminal, asset, functional location, protection scheme and device type.

The legacy application's Location / Protected Asset / Protection Function view is **a view over
the functional-location tree, kept indefinitely** — not a separate navigation mechanism. Engineers
and technicians continue to work in that style; it is a projection of the tree, and tree
navigation is the same data browsed another way.

> *Provenance:* SOW §5.2 — binding, and stated as "all". The view ruling is the owner's, decision
> #57: *"Protection Engineers and Techs will always operate off of Location/Protected
> Asset/Protection function and that really should just be a particular view on the new FLOC
> segmentation."*

---

## 8. Non-functional

Measured, not assumed.

| Dimension | Figure | Consequence |
|---|---|---|
| Stations and sites | 50 – 150 | |
| Protection devices | 2 000 – 10 000 | |
| Settings records | 10 000 – 100 000 | |
| Documents | 50 000 – 250 000 | |
| Named users | 25 – 75 | |
| Peak concurrent users | under 10 | **A complexity problem, not a volume problem** |
| Settings changes per year | 100 – 500 | The fourteen-step path runs a few hundred times a year. Optimise for correctness and traceability |
| Test records per year | 200 – 1 000 | Capture is mostly offline, in the field |
| History to migrate | 15 – 25 years | Doble test history from roughly 2001 is evidence and baseline, not archive |
| Microprocessor share | 25 – 50% | **The majority of devices are not microprocessor relays.** Any model assuming a settings file per device is wrong for most of the estate |

> *Provenance:* Round 4 dials, given by the owner.

### NFR-1 — Microsoft SQL Server as the authoritative repository · **P1**

A single authoritative repository within the application boundary, with referential integrity,
auditability and readiness for phases 2–5.

> *Provenance:* SOW §5.2 — binding.

### NFR-2 — Architectural weight may be spent freely; the interface may not be slow · **P1**

Two distinct budgets. At under ten concurrent users and a few hundred settings changes a year, no
reasonable architectural choice is excluded by throughput — full temporal history and an
interpreted definition engine are affordable, and where structural clarity and machine efficiency
conflict, clarity wins with the reason recorded.

That licence **does not extend to the interface**: the application must feel immediate to the
person using it. Ordinary screens settle within a second, a search within two, and anything longer
shows progress and stays usable. A technician waiting on a screen is not consoled by an elegant
schema.

> *Provenance:* Round 4 dials for the first half. **Second half corrected at the owner's mark on
> v0.1:** *"while true, the application must be responsive for usability's sake."*

### NFR-3 — Comprehensibility is a requirement, not a preference · **P1**

The system must remain understandable by one person. Every design decision is recorded with its
rationale in a single numbered register. A mechanism that cannot be explained in a paragraph is a
defect.

> *Provenance:* Round 1 — *"I can no longer hold it in my head"*, the stated reason for the
> rebuild. `docs/reference/CARRY-FORWARD-MAP.md` is the working answer to this requirement.

### NFR-4 — Timestamps carry offset and source quality · **P1**

Every instant is stored with its UTC offset, and record and event rows carry the quality of their
time source, so that a relay's local-time report and an approval's effective date are never
collapsed into one column.

> *Provenance:* Agrees with PnCPlatform decision #63. Required by FR-4.4.

---

## 9. Migration

### FR-8.1 — Migration of legacy content and rationale documents · **P1**

Basic migration of the current flat database content and rationale documents sufficient to
commence cutover, to an agreed mapping with review cycles to identify gaps before production use.
Unbounded cleanup and reclassification are excluded.

> *Provenance:* Proposal §2.2 and §9.

### FR-8.2 — Reporting parity is the acceptance gate · **P1**

Reporting and views equivalent to the legacy application, delivered and validated by NB Power
reviewers. This, not feature count, is what "replacement" means contractually.

The legacy functional surface is now fully measured — see `docs/review/LEGACY-SYSTEM.md`. Parity
is against that surface and nothing more.

> *Provenance:* Proposal §5 Acceptance Criteria.

### FR-8.3 — Legacy state is decoded, never inferred · **P1**

Migration decodes record state from the `OLD_NO` prefix **and** from document filenames, which
encode the same states independently. `D` records — work requests deleted before completion — are
dropped with a counted, recorded reason. The two malformed rows and the seventeen revision-ordering
violations are reconciled explicitly, never dropped silently.

> *Provenance:* Measured against `dbRelayManagement_Legacy`; `D` semantics confirmed by the owner.
> Full detail in `docs/review/LEGACY-SYSTEM.md` and `docs/migration/CUTOVER-STRATEGY.md`.

---

## 10. What Phase 1 actually is

### The commercial risk, stated once

Fourteen work steps, eight impact triggers, thirteen procedure capabilities and a fourteen-domain
boundary is a maximal system. The contract is **$48,000 fixed for four weeks**, and the proposal's
own §8 names *Phase 1 scope expansion* as its first risk. Architecting for the full shape is
right. Building it in four weeks is not possible, and this document does not pretend otherwise.

**The resolution is subset, not substitute.** Phase 1 ships a genuine slice of the final
architecture — the same engine, the same model, fewer definitions and fewer screens — so nothing
built now is thrown away and nothing later requires a migration.

### Proposed Phase 1 delivery

Each item traces to a binding SOW requirement.

- **The procedure and workflow engine**, with the settings-change process as its single authored
  instance. Proves the capability that matters and satisfies *"workflow states sufficient to
  emulate the current completion-tracking process"*.
- **The relay settings book** — active, historical and archived records, cradle-to-grave document
  history, controlled storage and publishing for Word/PDF settings documentation.
- **Active Directory authentication and the seven account types**, with read / modify / approve /
  archive / report permissions.
- **Legacy migration** of the flat database content and rationale documents, to the agreed mapping.
- **Reporting parity** with the legacy application — the acceptance gate, now fully specified.
- **Shape-only schema** for wiring, compliance obligations, asset lifecycle, events and the model,
  so phases 2–5 add data and screens rather than tables.

### Explicitly not in Phase 1

Live integration with Cascade, SAP, ASPEN or Line Constants (design readiness only) · the
compliance engine running in anger · event warehousing · analytics · mobile applications · wiring
data capture.

---

## Change history

| Version | Date | Change |
|---|---|---|
| 0.1 | 2026-09-11 | First draft from interview rounds 1–7 |
| 0.2 | 2026-09-11 | FR-6.1 and NFR-2 corrected at the owner's review marks; FR-3.4 correction recorded; FR-8.3 added after the legacy system was measured |
