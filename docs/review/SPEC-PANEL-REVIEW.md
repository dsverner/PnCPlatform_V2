# Specification review — requirements v0.2 and procedure-engine design v0.1

**2026-09-11 · reviewed against `LEGACY-SYSTEM.md`, `SCHEMA-REVIEW.md`, `DECISION-LOG.md`, the two JSON
Schemas and the three example documents.**

The author of both documents under review is the same assistant that produced this review. That
is a limitation, stated up front: what follows is what a second pass through four different
review methods found, not an independent review. The methods — requirements testability (Wiegers),
executable examples (Adzic), production failure modes (Nygard), interface and boundary design
(Fowler), and "how would we test it" (Crispin) — are used as lenses. No expert is quoted; no score
is assigned; nothing is measured that was not measured.

**Nothing in the reviewed documents has been changed.** Findings are for the owner's mark-up.

Twenty-four findings. Four would produce a wrong or stuck system as designed. Five are gaps that
implementation would hit in the first week. The rest are clarity, assumption and traceability.

---

## Critical — the design as written produces a wrong or stuck outcome

### C1 — The FIELD branch deadlocks when a readback difference leads to a change
**Where:** `examples/settings-change.procedure.json` — `READBACK_RESULT`, `RESOLVE_DIFFERENCE`,
`TEST.precondition`. Design §3 (`choice`), §7 (Unknown semantics).
**Lens:** failure modes.

`TEST.precondition` is `differenceCount = 0 or step.outcome[id='RESOLVE_DIFFERENCE'] = 'Restored'`.
When readback finds differences and the engineer resolves with outcome **`ChangeRaised`**, the
precondition is `false or false` = **false** — not Unknown, so it does not hold for a person; it
simply never becomes true. `TEST` is never Ready, the `FIELD` member never completes, `join: all`
never fires, and the whole instance waits forever with every board showing it as running.

Block structure prevents *structural* deadlock (design §3) but not a precondition that can never
become true. The example has no path out of `ChangeRaised`.

**Fix in the example:** the `ChangeRaised` case must lead to a terminal outcome for that member —
a branch-level outcome such as `Superseded` that satisfies the join. **Fix in the design:** §3
should state that every `choice` case and every step outcome must reach either the block's exit
or an explicit branch outcome; §8's structural checks should include *"no precondition references
an outcome that can only arise on a path that does not lead to this step"* — or, more simply,
require every step with a precondition to declare what happens if it is never met.

### C2 — The example demands a settings file from every device, contradicting FR-3.4 for most of the estate
**Where:** `examples/settings-change.procedure.json` — `BUILD_SETTINGS` (`evidence.required: true,
kinds: ["SettingsFile"]`, `record.kind: ConfigurationFileRevision`). `REQUIREMENTS.md` FR-3.4.
**Lens:** executable examples against the measured estate.

FR-3.4 says 25–50% of devices are microprocessor relays and the rest have no settings file. The
`BUILD` foreach runs `BUILD_SETTINGS` over *every* device in scope and **requires a settings file to
commit**. For an electromechanical relay the step cannot be committed as written, so `join: all`
never fires.

The vocabulary has the tool for this — `parallel.branches[].applies` — but `foreach` has no
per-member applicability and `step` has no `applies`. The example therefore cannot express *"for
each device, if it has a settings file build one, otherwise record the taps as characteristics"*
without a `choice` inside the foreach body, which the example does not have.

**Fix in the example:** the foreach body becomes a `choice` on `device.technology`: one case
builds a file, the `else` captures characteristics. **Fix in the design:** either add `applies` to
`step` (the step is recorded NotApplicable, with a reason, and counts as complete), or state in §9
that per-member applicability is expressed by a `choice`. The former is cleaner; it also gives
FR-3.4 a first-class handle.

### C3 — How a step commit becomes a configuration-file revision is not specified, and the settings book depends on it
**Where:** Design §5 (commit, action 6–7), §9. `REQUIREMENTS.md` FR-3.2, FR-3.3, FR-8.2.
**Lens:** interface and boundary.

§5 action 7 names the kind-specific rows a commit writes: `record.Readback`, `record.Finding`.
It does **not** say what a commit with `record.kind: ConfigurationFileRevision` writes into
`document.ConfigurationFile` / `document.Revision` / `document.SettingsIssuePackageItem`, nor how
the readback file at `READBACK` becomes a `ConfigurationFile` revision with `CaptureKind =
Readback` so that `record.Readback.ComparedToConfigurationFileRevisionRowId` has anything to point
at. Yet that chain — file → revision → package item → approval cascade (FR-3.2) → in-service fact
(FR-3.3) — *is* the relay settings book.

Related: **nothing creates the `SettingsIssuePackage`.** `SETTINGS_CHANGE_REQUEST.onEnter` binds
`package: work.settings_package`, assuming the work request already has one; no step in the
procedure creates it; `SETTINGS_LIFECYCLE` starts at `Calculated` with no creator. The example's
`Approve` guard `package.revision_count > 0` is coherent only once this is defined.

**Fix:** a §5.1 — *commit into the document schema* — mapping record kinds to `document.*` writes
(a `ConfigurationFileRevision` commit creates the `Revision`, the `ConfigurationFile` row with its
`CaptureKind`, and the `SettingsIssuePackageItem`); a statement of who creates the package (the
`REQUEST` or `SCOPE` step, or the workflow's `onEnter`); and the readback capture as a
`ConfigurationFile` revision of kind Readback.

### C4 — Offline field work cannot commit, and the design does not say what happens instead
**Where:** `REQUIREMENTS.md` FR-7.1 versus FR-2.2; design §1, §5. Example steps `APPLY`,
`READBACK`, `TEST` (role `technician`).
**Lens:** failure modes; contradiction between requirements.

FR-7.1: *"Approvals, settings issue, model changes, grants and definitions are never offline — the
pack captures, it does not authorise."* Design §5: a step commit is an attested act — competency,
segregation, witness, an immutable record. The technician's three steps are performed **in the
field, substantially offline** (`REQUIREMENTS.md` §2). So either the pack can commit — which
contradicts *"it does not authorise"* — or the technician's steps stay drafts until check-in, and
the commit happens online, by whom, with what `CommittedAt`, and with a witness who was present
in the field but is not present at check-in.

FR-7.1 is marked *later*, but the design must not preclude it (the requirement's own words), and
as written the commit model does. This is the same tension §1 says the engine resolves, and for
field work it does not yet.

**Fix:** a §5.2 — *deferred commit* — stating that an offline step is captured as a draft with the
capture instant and device-clock `TimeSourceQuality`, and **commits at check-in with the field
technician as `CommittedByActorId`** and the check-in reviewer as a second attributed actor; that
segregation and competency are evaluated at check-in against the person who captured; and that
the witness attestation is captured offline as a signed field on the draft (a person's name and a
re-authentication) and verified at check-in. The predecessor's field-pack design (its
`PLATFORM-ARCHITECTURE.md` §7.3) already has "reference superseded" flags on check-in; the same
mechanism carries the draft-to-commit step.

---

## High — implementation will hit these in the first week

### H1 — Nothing says *when* conditions are evaluated
**Where:** Design §3 (`hold.until` "releases itself"), §7 (due derived on read), example
`AWAIT_OUTAGE.until` (`work.outage_window_start <= @at`).
**Lens:** failure modes.

`hold.until` becomes true when the clock passes the outage window start. Who evaluates it at
03:00? The design has no evaluation model: neither *event-driven* (re-evaluate on every commit and
fact change) nor *scheduled* (a periodic tick). A hold with a time-based `until` needs the latter;
a `choice` on a just-committed capture needs the former. The predecessor has a
`RuleEvaluationRun` with `once`/`interval` cadences (`RuleEvaluation.cs`) — that is the scheduled
half — and nothing event-driven.

**Fix:** §4.1 — *the evaluation model*: on every commit, re-evaluate the readiness of every
Pending step and Held block in the same instance (event-driven); a periodic run re-evaluates every
Held block whose `until` references `@at` and derives due dates for escalation (scheduled). State
the interval and that a person may force re-evaluation.

### H2 — Drafts have no owner, so two people in the same role edit the same draft
**Where:** Design §4 (`StepInstance.AssignedRoleCode`, `Draft`), §1 ("visible only to those
working it").
**Lens:** failure modes; `FR-6.2` read scope.

A step is assigned to a *role*. Eleven `APPLY` members in parallel and three technicians: nothing
says who has which. `Draft` is a JSON column with last-writer-wins. Two technicians open the same
member's `READBACK`, both save — one's readings are gone, silently, before commit ever sees them.
And "visible only to those working it" is undefined when "working it" is a role.

**Fix:** a claim: `StepInstance.ClaimedByActorId`, `ClaimedAt`, with a lease the way the
predecessor's `acquire()` pattern works; a draft is editable only by its claimant; a claim can be
released or taken over by the responsible engineer with a reason; draft reads are scoped to
claimant plus the responsible role (which also answers OQ-15's question about who can read a
draft).

### H3 — Open legacy work has no landing position in a procedure instance
**Where:** `CUTOVER-STRATEGY.md` §5 (`M` rows → *"open work in flight"*); design §10.
**Lens:** executable examples.

357 `M` rows become in-progress `SETTINGS_CHANGE` instances at cutover. **At which step?** The
legacy three-track statuses (Complete / NA / Change In Progress) map neatly onto the `COMPLETION`
block's three branches — but only for a change that has reached `COMPLETION`. A legacy `M` record
with all three tracks `NA` has not started field work; one with document track Complete and the
others in progress is somewhere inside `COMPLETION`. The legacy data cannot say whether
`APPROVE`, `ISSUE` or `APPLY` happened.

**Fix:** a migration rule, agreed with the owner: every `M` instance lands at the start of
`COMPLETION` with earlier steps recorded as *migrated, not performed under this version* (the
same mechanism the migration list uses in §6 step 4), and the three branch states set from the
three tracks. Anything else is invention.

### H4 — No requirement has an acceptance criterion except parity
**Where:** `REQUIREMENTS.md` throughout; FR-8.2 is the exception.
**Lens:** testability.

Every requirement carries provenance; none but FR-8.2 carries a test. *"Point in time must never
fail"* (FR-4.1) has no stated question-and-expected-answer; *"eight triggers must be traceable"*
(FR-4.3) says traceable to what and how completely; *"ordinary screens settle within a second"*
(NFR-2) is the only measurable sentence in the non-functional section. For Phase 1's binding
requirements this is the difference between a specification and a description.

**Fix:** for each **P1** requirement, one acceptance criterion in Given / When / Then form,
derived from the worked example where one exists — e.g. FR-4.1: *Given* the settings-change
example has run to `InService` and a later change superseded it, *When* the settings in service on
the day between `RETURN_TO_SERVICE` and the supersession are asked for, *Then* the first
package's revisions are returned with the `APPROVE` commit's actor and instant.

### H5 — The SOW's navigation requirement is not in the Phase 1 delivery
**Where:** `REQUIREMENTS.md` FR-7.2 versus §10; design §10 (parity mapping).
**Lens:** traceability to contract.

FR-7.2 carries the SOW's binding words: *"filtering, search and navigation by station, terminal,
asset, functional location, protection scheme, device type."* The Phase 1 delivery list in §10 and
the parity mapping in design §10 are shaped by the legacy application — a grid by a location
string. Navigation by the functional-location tree and by scheme is a binding Phase 1 requirement
with no delivery item and no estimate line.

**Fix:** a delivery item in §10 and a package in the estimate; the `location` and `scheme` schemas
are carried, so the data is there.

---

## Medium — clarity and unstated assumptions

### M1 — A held `repeat` at its maximum has no exit
**Where:** Design §3 (`repeat.max` "holds for a person"), §4 (`ProcedureInstance.State`).
The person can cancel the whole instance. There is no *branch-level* cancellation or *"accept
after n passes with a reason"* action. Add one: a held block may be **resolved** by the
responsible role with an outcome and a reason, producing a `Finding`.

### M2 — `step.*` facts across `repeat` passes are undefined
**Where:** Design §7. §7 says `step.*` resolve to the enclosing member first, then the instance.
It does not say which **pass** of a `repeat` — `until: step.outcome[id='CHECK'] = 'Pass'` must
mean the current pass. State it: within a `repeat`, `step.*` facts resolve to the current pass;
`pass=` is a parameter for reaching earlier ones.

### M3 — Migration matching by `StepId` alone is ambiguous inside `foreach` and `repeat`
**Where:** Design §6 step 4. A `StepId` inside a foreach occurs once per member; inside a repeat,
once per pass. Matching must be by (`StepId`, `IterationKey`, pass). And a step whose
`record.kind` changed between versions has a carried record of the old kind — say whether that is
a match.

### M4 — Segregation is instance-wide, and that should be said
**Where:** Design §5 action 4. With eleven `BUILD_SETTINGS` members possibly calculated by three
engineers, *any* of them is barred from `CHECK` — because the segregation subject is the procedure
instance. That is the right behaviour; it is currently implicit. State it, and note the
consequence for small groups.

### M5 — Who authors at NB Power, in production?
**Where:** `REQUIREMENTS.md` FR-1.5, decision #28. The owner authors now; NB Power's engineers
later. The owner is the *supplier*. Until the later phase, "no hard-coded procedures" is true of
the architecture and not of the client's ability to change anything. The requirements should say
so plainly, because the client will read FR-1.1 as a promise about *them*.

### M6 — Record kinds are assumed to exist
**Where:** Example `record.kind` values: `RequestConfirmation`, `ScopeDecision`,
`EngineeringCheck`, `Approval`, `SettingsIssue`, `FieldApplication`, `ReturnToService`,
`Baseline`, `SoftwareArchive`. **UNVERIFIED** against `ref.RecordKind`. Reference data is rows,
not releases (decision #89 in the predecessor), so this is a seeding task — but the design should
say new record kinds are seeded with the procedure that needs them, and whether each has a
`RecordTemplate`.

### M7 — Witness attestation has no mechanism
**Where:** Design §3 (`signoff.witness`), §5 action 5 ("a second attributed actor"). Two people,
one session. The predecessor's `SegregationOverride` (second person approves an override) is the
nearest mechanism. Specify: the witness re-authenticates on the same device, or attests from their
own session within a window. Compounds with C4 offline.

### M8 — `foreach.over` is fixed at block start
**Where:** Design §3. `SCOPE.devices` is captured once and both foreaches iterate it. A device
added to scope after `BUILD` starts has no path. Probably correct — scope changes are a new
change — but say so, and say what `SCOPE` being outside the `DESIGN_AND_CHECK` repeat means: a
check cannot send it back to re-scope.

### M9 — The must-never-fail answers are not testable in Phase 1
**Where:** `REQUIREMENTS.md` §5 (FR-4.2, 4.3, 4.4 are *shape* or *later*) versus Round 2's
"must never fail". Not a contradiction — shape now, capability later — but acceptance in Phase 1
cannot exercise them, and the client should not be led to expect it. Say which of the four
Phase 1 demonstrates (FR-4.1) and which it only prepares for.

---

## Low

- **L1** `@at` for a procedure instance is undefined. The grammar defines it as "the run's
  instant"; for a precondition evaluated on commit or on a tick it is the evaluation instant. Say
  so in §7.
- **L2** Due dates derived on read: a board listing hundreds of steps derives hundreds of cadences
  per load. Fine at this scale (NFR-2), but derive once per board request, not per row render.
- **L3** The legacy `Verify Order` type (77 rows) has no named `Program.WorkType` in the design;
  the parity table maps `Type → WorkType` generically. Name the four.
- **L4** `parallel.branches[].applies` Unknown "holds the branch open for a person" — say who.
- **L5** `SETTINGS_LIFECYCLE` has no transition from `Verified` back on a failed baseline, and
  `InService → Superseded` is manual with a reason while every other transition is fired by a
  step. Consistent design would have the *next* package's `BASELINE` step supersede the old one.
- **L6** `procedure.schema.json` allows `outcomes` on a procedure but nothing in the document sets
  the procedure's outcome; the engine presumably derives it. State the rule (all blocks complete →
  first outcome; cancelled → `Cancelled`).

---

## What this review did not do

- It did not run anything. The 18 expressions were verified earlier by the reference checker; the
  block semantics have never executed.
- It did not review `CUTOVER-STRATEGY.md`, `CARRY-FORWARD-MAP.md` or the schema review as
  specifications — only as ground truth for the two documents under review.
- It is one author's second pass. The findings the author *cannot* see remain unseen; C1 and C2
  were found only by walking the example against the estate figures, which suggests walking every
  future example the same way.

## Suggested order of repair

1. C2, C1 — both are example defects with a one-line design consequence each; fix before the
   example is shown to anyone.
2. C3 — the commit-into-document mapping. Without it the settings book is not designed.
3. C4, H1, H2 — the three runtime semantics gaps (offline commit, evaluation timing, draft
   ownership). One section each.
4. H3 — needs an owner ruling, then a paragraph.
5. H4, H5 — requirements-level; H5 also changes the estimate.
6. The rest with the v0.2 mark-up.
