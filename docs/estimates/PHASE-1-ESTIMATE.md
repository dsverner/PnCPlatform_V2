# Phase 1 — effort estimate

**Estimate v0.1 · 2026-09-11 · hours, solo owner with Claude Code · not a commitment**

Scope estimated: the Phase 1 delivery proposed in `REQUIREMENTS.md` §10, against the contract in
`docs/contract/sow-baseline.md` — **180–240 hours, four weeks from start, $48,000 CAD fixed.**

Method: work packages from the design and the measured legacy surface, each with a low and a high
in hours and the assumption that drives the spread. No confidence percentages — there is no
calibrated history to derive one from. No productivity multipliers.

---

## 1. The one benchmark that exists

The proposal itself priced Phase 1 by deliverable (§4). Its **Phase 1a baseline — core
application and database, basic migration, reporting parity — was ~80 hours.** The added Phase 1
deliverables were priced at ~104–163 hours, almost all of them documentation packages.

That 80-hour baseline was priced for a settings book with *"workflow states sufficient to emulate
the current completion-tracking process"* (SOW). It was **not** priced for a general procedure
engine. The engine is the owner's architectural decision for phases 2–5, being built first. That
is the right decision and it is also the reason the numbers below do not fit the baseline.

One observed velocity figure, offered as context and deliberately not used as a multiplier:
`PnCPlatform` went from an empty repository on 2026-08-30 to release 0.10.5 on 2026-09-10 —
302 tables, 510 procedures, an API, a PWA, a QA environment, 258 decisions — in eleven days
(`docs/decisions/DECISION-LOG.md`, `_handoff.md` in that repository). That output also failed the
central requirement, which is why it is not a multiplier.

---

## 2. Work packages

| # | Package | Low | High | What drives the spread |
|---|---|---:|---:|---|
| A | **Repository bring-up and application rewrite** — import the carried schema DDL and deploy pipeline (`deploy.py`, sqlpackage, `Roles.sql`, the 252-check smoke) and `PnC.Formula`; **rewrite the API and PWA** on the same stack; subsystem-map lines; build green; deployed to DEV | 72 | 124 | **Owner's ruling #64 (v0.3): the application is rewritten, against the recommendation to carry it.** Was 12–24 on the carry assumption; the rewrite adds 60–100. The generic dispatcher, forms, definitions editor, expression checker and Windows auth are all rebuilt |
| B1 | **`process` schema DDL** — 12 tables with the four conventions, temporal classes, generated views and accessors | 16 | 24 | *UNVERIFIED whether the predecessor's 510 procedures and 365 views come from a generator or were hand-written. If a generator exists, the low end; if not, the high.* |
| B2 | **Document validation and projection** — schema enforcement, structural checks (§8 of the design), canonical AST on approval, projection into `ProcedureStep`, `ProcedureStepRole`, `ProcedureFactUse`, `ProcedureCall` | 12 | 20 | The schema exists; the structural checks are enumerated. Spread is the document-aware typing hook (OQ-14) |
| B3 | **The interpreter** — block-tree execution for all eight kinds; step lifecycle; the thirteen-action commit through `record.*`, segregation and acceptance | 40 | 60 | The largest single package. `foreach` with parallel members, `repeat` passes, and `parallel` joins are where the hours go. The commit pipeline reuses existing machinery |
| B4 | **Published facts** — the fifteen engine facts into `compliance.vFactCatalogue`, resolvable by `PnC.Formula` | 8 | 14 | Names are proposed (OQ-14); if they change late, rework |
| B5 | **Workflow layer** — instances, transitions, guard evaluation (`procedure` and `when`), `onEnter.startProcedure`, `advances` | 12 | 20 | Shape carried from the predecessor; the join is new |
| B6 | **Version pinning** — `InstanceVersionSet` at start | 4 | 6 | The migration list (rulings, re-plan by StepId) is **not** needed until a second version is approved. Estimated separately below as deferrable |
| B7 | **Authoring v1** — the existing definitions editor with schema enforcement and live expression check; approval with segregation | 8 | 14 | Assumed the predecessor's `definitions.js` and `expression.js`; #64 did not carry them, so W5 wrote the editor new (`definitions.js`, 2026-09-12) — within the range |
| C | **The settings-change procedure and two workflows** authored, plus `DRAWING_REVISION`, run end to end on DEV | 8 | 14 | The documents exist and verify; this is exercising them against the live engine and fixing what that finds |
| D | **Parity screens** — grid with state toggle, column chooser and print; change-request status with the three tracks; setting display; verified-date action; user administration | 30 | 50 | The legacy surface is small and fully specified (`LEGACY-SYSTEM.md` §8). The PWA's generic dispatcher exists; `forms.js` did not survive #64 — W6 (2026-09-12) wrote the screens new over five read-model views, two tracks per #58, user administration dropped per option 4 pending the owner's card; spread is how much the grid and print need that is not generic |
| E | **Migration** — legacy mapping (base → device; `P` → revisions; `A` → current; `M` → open instances; `D` dropped and counted; filenames decoded; overflow columns → characteristics), the hash-diff cutover tool, and reconciliation reports for the 17 ordering violations, 2 malformed rows and 617 pre-numbering rows | 30 | 50 | *(W7, 2026-09-12: the predecessor's `Run`/provenance machinery applied and was carried (#137); none of its loaders did — the importer, the landing procedure and the hash-diff tool were written new.)* The reconciliation rules also need the owner's rulings (OQ-7, OQ-8) |
| D2 | **Navigation by the tree** — the Location / Protected Asset / Protection Function view as a projection of `location.Node` → `asset.Placement` → `scheme.CommissionedFunction`, plus browse by station, panel, scheme and device type (FR-7.2, binding; decision #57) | 12 | 20 | Added after the specification review (H5). The `location` and `scheme` schemas are carried; this is screens, not schema. Spread is the projection query's complexity against 208k location rows |
| F | **Authentication and the seven account types** — Windows/Kerberos auth exists (`Auth.Mode: Windows`, app-pool SPN registered); map the seven types to `security.Role` grants with functional-location and device-type scope; read-scope enforcement | 8 | 14 | Role codes undecided (OQ-18). Auth itself is carried |
| H | **Testing, UAT support, defect fixing, cutover rehearsal** | 24 | 40 | The predecessor's relocation rehearsal found five defects DEV structurally could not show. Expect the same shape |
| | **Build subtotal (A–F, H)** | **284** | **470** | *v0.2: +12–20 for D2 (specification review). v0.3: +60–100 for the application rewrite (#64)* |

### Documentation packages in the fixed price

Proposal §4 lists these as Phase 1 deliverables. Priced there by band; what already exists is
credited.

| Package | Proposal band | Status | Remaining |
|---|---:|---|---:|
| Requirements specification | 10–15 | **Done** — `REQUIREMENTS.md` | 0 |
| Functional design document | 12–18 | Not started | 12–18 |
| Technical architecture | 8–12 | Partly — `PROCEDURE-ENGINE.md`, `CARRY-FORWARD-MAP.md` | 4–6 |
| Integration design | 10–16 | Not started — Cascade, SAP, ASPEN, Line Constants readiness | 10–16 |
| Document control framework | 8–12 | Not started | 8–12 |
| Testing documentation | 10–16 | Not started | 10–16 |
| Training materials | 6–10 | Not started | 6–10 |
| Operations documentation | 6–10 | Partly — the predecessor's runbook material exists and is carried | 3–6 |
| Database documentation package | 16–24 | Partly — `SCHEMA-REVIEW.md`, `CARRY-FORWARD-MAP.md`; ERDs, data dictionary and object catalogue not done | 10–16 |
| | | **Documentation remaining** | **63–100** |

### Deferrable

| Package | Low | High | Why deferrable |
|---|---:|---:|---|
| B6' — the migration list: affected-instance computation, rulings UI, re-plan by StepId | 12 | 20 | Needed only when a second version of a procedure is approved. Phase 1 ships one version |
| Geographic mapping | 12 | 20 | Proposal: *"only to the extent required by the approved Phase 1 implementation scope"*. Nothing in the parity surface needs a map |

---

## 3. The totals

| | Low | High |
|---|---:|---:|
| Build (A–F, H) | 284 | 470 |
| Documentation remaining | 63 | 100 |
| **Phase 1 as scoped in `REQUIREMENTS.md` §10** | **347** | **570** |
| Contracted effort basis | 180 | 240 |
| Four weeks at 40 h/week | 160 | 160 |

**The scope as proposed is roughly 1.4× the contract's high end at the low estimate, and 2.4× at
the high.** Against the four-week calendar at forty hours it is 2.2–3.6×. The judgement stated in
`REQUIREMENTS.md` §10 and `OPEN-QUESTIONS.md` OQ-11 — that the full scope does not fit — is now a
number, and the owner has ruled on it (#63): the engine is built inside Phase 1 anyway, the excess
is investment in phases 2–5, the documentation packages are delivered at acceptance, and the owner
works more than forty hours a week for this phase (#71).

Where the excess comes from: the engine (B1–B7, 100–158 h) and, from v0.3, the application rewrite
(60–100 h, #64). Without either, C + D + D2 + E + F + H plus a 12–24 h bring-up is 124–216 h —
inside the contract's band and consistent with the proposal's own 80-hour Phase 1a baseline plus
documentation. Both additions are the owner's deliberate choices, recorded with their cost.

---

## 4. Ways to bring it in — options, not recommendations

These are the owner's choices. Each is stated with what it costs.

| Option | Hours saved | What it costs |
|---|---:|---|
| **1. Reduced block set for Phase 1.** Ship `sequence`, `step`, `parallel`, `choice`, `foreach`; defer `repeat`, `call`, `hold` to Phase 2 as shape only | 20–30 | The settings-change procedure loses its rework loop (`repeat`), the drawing sub-procedure (`call`) and the outage hold. Rework becomes cancel-and-re-raise. The example document changes |
| **2. Defer the migration list (B6')** | already excluded | None in Phase 1 — it is only needed from the second approved version. Recommended regardless |
| **3. Migration: base, revisions and current only.** Defer the overflow-column → characteristic mapping and the three-track history | 10–18 | `DESC1–4`, `REMARKS1–5`, `CT_*`/`PT_*` arrive as free text on the revision, typed later. The legacy three-track statuses are not reconstructed as branch instances |
| **4. User administration screen dropped.** AD authenticates; roles are grants an Administrator sets in the existing security screens | 4–8 | The legacy `prog_frmUsers` has no parity screen. Defensible: its 31 stored passwords are exactly what AD replaces |
| **5. Documentation packages re-sequenced.** Functional design, testing docs, training and ops docs delivered at acceptance rather than with the build; integration design and document-control framework as Phase 1 deliverables on their proposal timeline | 0 saved; ~40–60 moved | Changes when the client sees them, not whether. Needs the client's agreement; the proposal ties acceptance to "documentation … authorized for the selected commercial scope" |
| **6. Recognise the engine as investment.** Build it as designed inside Phase 1; treat ~100–160 h of it as unfunded, recovered in phases 2–5 where every phase reuses it | 0 | Commercial, not technical. The engine is what makes phases 2–5 cheap; the SOW's Phase 2 (*settings automation, logic exports*) and Phase 4 (*compliance*) are procedures |
| **7. Re-baseline with the client.** Present the measured scope and this estimate; propose Phase 1 at its real size or split it | 0 | The proposal's own §8 lists *Phase 1 scope expansion* as its first risk and prescribes change control for it |

Options 1–4 together: **34–56 h saved**, bringing the build to roughly 250–414 and the whole to
313–514. Still above 240 at the low end once documentation is included. **No combination of
technical descoping alone brings the full scope inside 240 hours while keeping the engine.**
That leaves 5, 6 or 7, which are the owner's to make.

**Ruled 2026-09-11 (#63): option 6 with option 5** — the engine is built inside Phase 1 as
investment, and the documentation packages are delivered at acceptance. Options 1–4 were not
taken. The owner will work more than forty hours a week for the phase (#71).

---

## 5. Risks that move the number

Named, with which package they hit.

| Risk | Hits | Direction |
|---|---|---|
| The predecessor's code cannot be carried cleanly and needs rewriting rather than importing | A, D | +60–100 |
| No DDL generator; 12 tables' procedures and views by hand | B1 | toward the high end |
| The document-aware typing hook is harder than a catalogue lookup | B2, B4 | +6–10 |
| The legacy migration machinery does not apply; importer from scratch | E | toward the high end |
| The 17 ordering violations and 617 pre-numbering rows need per-row human rulings rather than a rule | E | +8–16, plus owner time |
| The fact names change after the example is authored | B4, C | rework, +4–8 |
| UAT participation and review cycles slip — the proposal's own §8 risk | H, calendar | calendar, not hours |
| Cutover copy differs structurally from ours despite the client's assurance | E | +8–20 |

---

## 6. What this estimate does not know

- **Whether code is carried — ruled.** Decision #64, 2026-09-11: the application is rewritten;
  only `PnC.Formula` and the deploy tooling are carried. A is 72–124. The single largest
  uncertainty in v0.1 is now the single largest deliberate addition.
- **The predecessor's tooling.** UNVERIFIED: a DDL/procedure generator; the applicability of its
  migration machinery to the legacy relay database. Both were assumed favourable at the low end
  and absent at the high.
- **The owner's hours per week — partly ruled.** Decision #71: more than forty a week for this
  phase, unquantified. Four weeks at 40 is 160; at 55 it is 220. Against 347–570 h, the calendar
  is still the constraint, not the rate. Start date not given.
- **What the client will accept as parity.** `LEGACY-SYSTEM.md` §8 is the measured surface; the
  client's reviewers have not confirmed it is the whole of what they use.
