# The procedure engine — design

**Status:** design v0.3, 2026-09-11. v0.1 was reviewed by the owner (twelve sections, all kept)
and by the specification review (`docs/review/SPEC-PANEL-REVIEW.md`, 24 findings). Eight
repair decisions were put to the owner as worked examples and ruled (#50–#58, v0.2); every
remaining open question was then closed on one card (#59–#72, v0.3). No code exists.

The engine is the part of the platform that the schema review found missing (`SCHEMA-REVIEW.md`
§3) and the part `REQUIREMENTS.md` §3 makes central. This document is its design: what a procedure
*is*, how it runs, how it joins the lifecycle layer, and what survives a change of version.

| Artefact | What |
|---|---|
| `procedure.schema.json` | The authoring contract for a procedure document |
| `workflow.schema.json` | The authoring contract for a workflow document |
| `examples/settings-change.procedure.json` | The fourteen-step settings change as one procedure |
| `examples/settings-change.workflow.json` | The work-request lifecycle that starts it |
| `examples/settings-lifecycle.workflow.json` | The package lifecycle its steps advance |

### What changed in v0.2

| Review finding | Owner's ruling | Where |
|---|---|---|
| C2 — electromechanical relays have no settings file | Fork on the device: a file for microprocessor relays, typed settings for the rest (#50) | §3, §9 |
| C1 — a readback difference ending in *Change raised* deadlocks the branch | That relay leaves the change as *Superseded by …*; the others continue (#51) | §3 `branchOutcome`, §9 |
| C3 — how a commit becomes a settings-book revision | Committing the step creates the revision and adds it to the package; step 1 creates the package (#52) | §5.1 |
| C4 — offline field work cannot commit | Captured offline, committed at check-in with the technician as actor and the reviewer as second person (#53) | §5.2 |
| H1 — when conditions are evaluated | On every commit, plus a scheduled sweep for anything time-based (#54) | §4.1 |
| H2 — two people, one draft | First to open claims it; others read-only; an engineer may take over with a reason (#55) | §4, §5 |
| H3 — where open legacy work lands | At the completion tracks with the legacy states; earlier steps recorded as migrated (#56) | §6, `CUTOVER-STRATEGY.md` |
| H5 — navigation by the tree | The tree is the model; the legacy Location / Protected Asset / Protection Function style is its default view, kept indefinitely (#57) | §10 |
| Owner, unprompted — the legacy software track | Dropped from the procedure; its rows migrate as notes (#58) | §9, §10 |
| M1–M9, L1–L6 | Clarifications, no ruling needed | throughout |
| **v0.3** — the open-questions card | Every device's settings are a file, native or text, parsed by a per-model template, read as `device.settings.<key>` (#61); draft reads logged (#68); a hold past its maximum raises an obligation (#69); the eight predecessor workflows discarded (#70); role codes settled (#66); fact names accepted (#67); the application is rewritten, not carried (#64) | §3, §4, §5.1, §9, §12 |

---

## 1. Thesis

> The engine is the only place a procedure lives, and it is the boundary between drafting and record.

Two jobs, in that order.

**Configurability (FR-1.1).** Every procedure the group follows is a document — versioned, approved,
interpreted at runtime. Changing how the group works is a new version of a document, never a
release. The engine has no knowledge of settings, tests or compliance; it knows blocks, steps,
roles, facts and records. The settings change in `examples/` is the first document it runs, not a
special case inside it.

**The commit boundary (FR-2.2).** Before a step commits, everything in it is a draft: editable by
its claimant, unlogged as evidence, visible to the claimant and the responsible role. When a step
commits, a `record.Record` is written and the step becomes immutable. The record is the platform's
existing immutable object — bi-temporal acceptance, evidence links, obligations already consume
it. This is how the work environment and the system of record coexist: they are the same rows, on
opposite sides of one event.

---

## 2. Two layers and the join

| Layer | Governs | Vocabulary | Subject |
|---|---|---|---|
| **Workflow** | The lifecycle of a *thing* | states · transitions · roles · guards | a work request, a settings package, a device… |
| **Procedure** | The *doing* | a tree of blocks; steps that capture, attest and commit | one run over one subject |

They are joined in both directions, and nowhere else.

**Workflow → procedure.** A state's `onEnter` may `startProcedure`. Entering *In progress* on a
settings-change request starts a `SETTINGS_CHANGE` instance over that request, pinned to the
procedure's approved version at that instant. A transition's `requires` may name a `procedure` and
an `outcome`: *Close* requires `SETTINGS_CHANGE` to have completed. The engine satisfies that guard
from the procedure instance's outcome, not from anything a person asserts.

**Procedure → workflow.** A step's `advances` names a workflow, a subject and a transition. When
the *Approve* step commits with outcome *Approved*, it fires *Approve* on the package's
`SETTINGS_LIFECYCLE` instance. The transition's own roles and guards still apply; the step is the
actor, the segregation rule still sees who.

This is what the predecessor never had — no column joined its two layers (`SCHEMA-REVIEW.md` §3).
Here the join is two declarative properties and two runtime columns.

---

## 3. The procedure document

One JSON document per version, held whole in `config.DefinitionVersion.PayloadText` (#38). An
authored document carries grammar-1 expressions as text so a person can write them; on approval the
engine parses every expression to its canonical AST and stores the canonical document, whose hash
is the version's identity. Both forms validate against `procedure.schema.json`.

The body is a **block tree**. Block-structured (#39): every block has one entry and one exit, nests
cleanly, and cannot express a structural deadlock or an unreachable step. That property is what
lets a later friendly editor render a procedure as an outline rather than a diagram.

| Block | What it does | Capability it delivers |
|---|---|---|
| `step` | One unit of work a person performs and commits | ordered steps · data capture · role and competency · sign-off · evidence · due · deviation · guard (`precondition`) |
| `sequence` | Items in order | ordered steps |
| `parallel` | Branches concurrently, rejoining on `all`, `any` or *n*; a branch may declare `applies` | parallel branches |
| `choice` | The first case whose `when` is true; optional `else` | conditional branching — including **per-device applicability** inside a `foreach` (#50) |
| `foreach` | The body once per member of a set, subject rebound to the member; `all`/`any`/*n* join | iteration over a set |
| `repeat` | The body again until a condition holds, with a maximum | rework, without a back-edge |
| `call` | Another procedure as a child instance, version pinned with the parent | sub-procedures |
| `hold` | A legitimate wait — outage, part, approval, external — released by condition or by hand, with a maximum | hold points and suspension |

### The step, in full

A step names a **role** (an alias resolved to a `security.Role` code, optionally with a
`requires` expression over `person.*` facts for competency). It may declare:

- `precondition` — a boolean that must be true before the step can start. Unknown holds it and
  names the facts that were unknown. **A precondition that is false is not a hold; it is a wait
  that may never end.** So every step with a precondition sits on a path where some other outcome
  can end the branch — enforced by the structural check in §8 and delivered by `branchOutcome`.
- `capture` — typed fields (`num` with unit and base, `text` with an allowed list, `bool`, `date`,
  `ref`, `set`, `file`), each optionally `required` and with a `validate` expression over `value`.
  Held as a draft; written as characteristic values on the record at commit.
- `record` — the `ref.RecordKind` the commit produces, and its template where it has one. **Every
  step produces a record** (#42). New record kinds are reference data, seeded with the procedure
  that needs them.
- `produces` — an entity the commit creates and binds to a procedure-scoped name (#52): the
  `REQUEST` step produces the settings-issue package as `package`, referenced afterwards as
  `procedure.package`.
- `outcomes` — the step's outcome vocabulary, chosen at commit. Default `Done`.
- `branchOutcome` — for a named outcome, **end the enclosing foreach member or parallel branch**
  with a branch outcome, skipping its remaining steps (#51). *Change raised* on the readback
  resolution ends that relay's branch as `Superseded`; the join counts it as complete.
- `signoff` — the segregation `action` this commit is (*Calculate*, *Check*, *Approve*…), and
  whether a `witness` must co-attest. Segregation is evaluated **instance-wide**: any of three
  engineers who calculated any of eleven devices is barred from the check.
- `evidence` — files bound to the record, with required kinds and a minimum.
- `due` — a cadence and an anchor step. **Derived on read, never stored** (#44).
- `deviation` — whether the person may `skip` or `vary`, and the finding category. **A deviation
  always requires a reason and always produces a `record.Finding`** (#48).
- `advances` — the transition to fire on a workflow instance at commit (§2).

---

## 4. Runtime — the `process` schema

A new schema, `process`, hosts both layers' runtime and the projections (#45). Every table carries
the four conventions of `CARRY-FORWARD-MAP.md` §2; only domain columns are listed. Instances and
steps are system-versioned so that "what did this step look like when it was committed" is
answerable.

### Definitions — projected on approval

| Table | Domain columns | Purpose |
|---|---|---|
| `ProcedureStep` | `DefinitionVersionRowId` · `StepId` · `BlockPath` · `Title` · `RoleAlias` · `RoleCode` · `RecordKindCode` · `SignoffAction` · `HasDue` · `AllowsDeviation` | One row per step; what screens list and what impact queries join |
| `ProcedureStepRole` | `ProcedureStepRowId` · `RoleCode` · `RequiresAst` | Who may perform it |
| `ProcedureFactUse` | `DefinitionVersionRowId` · `BlockPath` · `FactName` | Every fact any expression reads — the impact index |
| `ProcedureCall` | `DefinitionVersionRowId` · `BlockPath` · `CalleeKey` | The call graph, for pinning and impact |

The document is authoritative; these rows are derived and rebuilt on approval.

### Instances

| Table | Domain columns | Purpose |
|---|---|---|
| `WorkflowInstance` | `WorkflowDefinitionVersionRowId` · `SubjectKind` · `SubjectEntityId` · `CurrentState` · `StartedAt` · `StartedByActorId` · `CompletedAt` · `IsCancelled` | Re-homed from `work` with the same shape |
| `WorkflowTransition` | `WorkflowInstanceEntityId` · `OccurredAt` · `FromState` · `ToState` · `TransitionName` · `ActorId` · `Reason` · `FiredByStepInstanceEntityId` · `GuardEvaluation` (JSON) · `ActionLogId` | Every transition, with why it was allowed |
| `ProcedureInstance` | `DefinitionVersionRowId` · `ParentInstanceEntityId` · `CallBlockPath` · `WorkflowInstanceEntityId` · `InvokedAtState` · `SubjectKind` · `SubjectEntityId` · `WorkRequestEntityId` · `Inputs` (JSON) · `Produced` (JSON: name → EntityId) · `State` (Running · Held · Completed · Cancelled) · `Outcome` · `StartedAt` · `StartedByActorId` · `CompletedAt` | One run |
| `InstanceVersionSet` | `ProcedureInstanceEntityId` · `CalleeKey` · `DefinitionVersionRowId` | Every callee version resolved at the root's start (#40) |
| `BlockInstance` | `ProcedureInstanceEntityId` · `ParentBlockInstanceEntityId` · `BlockPath` · `BlockKind` · `IterationKey` · `Pass` · `MemberSubjectKind` · `MemberSubjectEntityId` · `State` · `Outcome` (incl. branch outcomes such as `Superseded`, `NotApplicable`) · `StartedAt` · `CompletedAt` | One row per activation; a `foreach` member or a `repeat` pass is its own row |
| `StepInstance` | `BlockInstanceEntityId` · `StepId` · `State` (Pending · Ready · Active · Held · Committed · Skipped · Varied) · `AssignedRoleCode` · **`ClaimedByActorId` · `ClaimedAt` · `ClaimExpiresAt`** · `Draft` (JSON) · `DraftModifiedAt` · **`CapturedAt` · `CapturedByActorId` · `CaptureSource` (Online · FieldPack) · `CaptureTimeQuality`** · `CommittedRecordEntityId` · `CommittedByActorId` · `WitnessedByActorId` · `AcceptedIntoPlatformByActorId` · `CommittedAt` · `Outcome` · `DeviationFindingEntityId` · `HeldReason` | The mutable side, then the pointer to the immutable side |
| `HoldInstance` | `BlockInstanceEntityId` · `Reason` · `HeldAt` · `HeldByActorId` · `ReleasedAt` · `ReleasedByActorId` · `ReleaseBasis` (Condition · Manual · Expired) | A hold is reportable as such |
| `InstanceMigration` | `ProcedureInstanceEntityId` · `FromDefinitionVersionRowId` · `ToDefinitionVersionRowId` · `Decision` (Keep · Migrate · Cancel) · `Reason` · `DecidedByActorId` · `DecidedAt` · `StepMapping` (JSON) | The outstanding-work decision (#41) |

`DueAt` is **not a column**; it is derived on read (#44).

### The claim (#55)

A step is assigned to a role; a **claim** makes it one person's. The first person to open a Ready
step claims it (`ClaimedByActorId`, with a lease that renews while they work and expires when they
stop). Everyone else in the role sees it read-only with *"R. Doucet is working this step"*. The
claimant may release it; the responsible engineer may take it over with a reason, which is logged.
The draft is writable only by the claimant, and readable by the claimant and the responsible
role. **Every read of a draft by anyone other than its claimant is audit-logged** (#68), as reads
of configuration files and evidence already are — so *"who looked at Doucet's readings before he
committed them"* has an answer.

### 4.1 The evaluation model (#54)

Two mechanisms, each simple:

- **On every commit** in an instance, the engine re-evaluates the readiness of every Pending step,
  every `choice`, every `repeat.until`, every `parallel` join and every `hold.until` in that
  instance. A commit is the event that can change any of them.
- **On a scheduled sweep** — every 15 minutes by default, a platform setting — the engine
  re-evaluates every `hold.until` and `parallel.applies` that reads `@at`, and derives due dates
  for escalation. Time passing is the other event, and nothing else notices it.

A person may force re-evaluation of an instance. `@at` in any procedure expression is **the
evaluation instant** — the commit's or the sweep's.

---

## 5. Commit

The one event that matters. In order, and atomically:

1. **Claim** — the committing person holds the claim.
2. **Precondition** — already true, or the step could not have started.
3. **Validation** — every `capture` field's `validate` expression with `value` bound. False or
   **Unknown** refuses the commit and names the unknown facts.
4. **Competency** — the role alias's `requires` expression for the committing person.
5. **Segregation** — `signoff.action` against `Program.SegregationRule` with the procedure
   instance as subject; WarnAndLog needs a reason, Block needs a second person's override.
6. **Witness** — where `signoff.witness` is true, a second attributed actor who **re-authenticates
   on the same device**; their identity is recorded, never a typed name.
7. **Record** — a `record.Record` of the declared kind: subject, work request, `PerformedByActorId`,
   `WitnessedByActorId`, `OccurredAt` = the capture instant, `OverallResult` = the outcome,
   `TemplateDefinitionVersionRowId` = the procedure version. Captured fields become
   `record.CharacteristicValue` rows; evidence files become `document.File` rows linked to it.
8. **Kind-specific rows** — §5.1.
9. **Acceptance** — where the record kind requires it, a `record.Acceptance` row is opened for the
   accepting role. Acceptance is bi-temporal; it is a later act.
10. **Produces** — the entity named by `produces` is created and bound in `Produced`.
11. **Branch outcome** — if the outcome has a `branchOutcome`, the enclosing member or branch
    completes with it and its remaining steps are Skipped with that as the reason.
12. **Advances** — the declared workflow transition is fired; its guards and roles apply.
13. **Immutability** — `State` = Committed; `Draft` retained as it stood; `CommittedRecordEntityId`
    set.

Correcting a committed step is a new valid-time assertion on the record, never an edit of it.

### 5.1 Commit into the document schema (#52)

The settings book is a consequence of commits, never edited by hand.

| Step commits with record kind | The commit also writes |
|---|---|
| `RequestConfirmation` with `produces: package` | a `document.SettingsIssuePackage` (the entity the lifecycle workflow governs), bound as `procedure.package`; its `SETTINGS_LIFECYCLE` instance starts in `Calculated` |
| `ConfigurationFileRevision` | a `document.Revision` on the device's configuration document; a `document.ConfigurationFile` row with `CaptureKind = Design`, `DeviceEntityId` = the member device, `ParseStatus` from the parser; a `document.SettingsIssuePackageItem` linking the revision to `procedure.package` |
| `ConfigurationFileRevision` from a **text settings file** (the electromechanical fork, #50, #61) | exactly the same as the row above — a `document.Revision`, a `ConfigurationFile` with `CaptureKind = Design` and `FileKind = SettingsText`, a `SettingsIssuePackageItem` — parsed by the text reader against the device model's template. A relay without a vendor file is a device whose file is text, not a different kind of thing |
| `Readback` | a `document.ConfigurationFile` row with `CaptureKind = Readback` from the readback file; a `record.Readback` comparing it (`ProducedConfigurationFileRevisionRowId`) with the approved design revision (`ComparedToConfigurationFileRevisionRowId`), `DifferenceCount` from the capture |
| `Finding` | a `record.Finding` with the declared category |
| `Approval` on the package | approval cascades to every revision in the package (PnCPlatform #60) |
| `Baseline` | the design revision's `InServiceFrom` is set from `RETURN_TO_SERVICE`'s capture instant (FR-3.3) |

**W4 note (2026-09-12, decision #108).** The deployed schema's values are `CaptureKind = Designed` (not *Design*)
and `AsLeftReadback` (not *Readback*), and the text file's kind is `SettingsText`; the table above reads with those
substitutions. The lifecycle's `Check` and `Apply` transitions are fired by the `CHECK` and `APPLY` steps (#112).

### 5.2 Deferred commit — field work (#53)

The field pack **captures; it does not authorise** (FR-7.1). A step performed offline is captured
as a draft with `CapturedAt` from the device clock, `CaptureTimeQuality = DeviceClock`,
`CapturedByActorId` = the technician, `CaptureSource = FieldPack`. It **commits at check-in**:

- `CommittedByActorId` = the technician who captured — the act is theirs;
- `AcceptedIntoPlatformByActorId` = the person checking in, who is the second attributed person;
- `OccurredAt` on the record = `CapturedAt`, not the check-in instant;
- competency and segregation are evaluated at check-in **against the technician**, not the
  reviewer;
- a witnessed step is witnessed in the field: the witness re-authenticates on the field device
  against the pack's credential store, and the attestation travels with the draft;
- a draft whose cited references were superseded while the pack was out is flagged for the
  reviewer, as the pack design already does.

---

## 6. Version pinning and migration

**Pinning (#40, FR-1.3).** When a root procedure instance starts, the engine resolves the approved
version of the root document and, walking `ProcedureCall` transitively, of every callee. All are
written to `InstanceVersionSet`. *Which procedure did this request follow?* has exactly one answer.

**A new version is approved (#41).** Nothing is silent:

1. Approval of version *n+1* computes the **affected instances**: every running instance whose
   `InstanceVersionSet` contains version *n*, directly or as a callee.
2. The engine opens a **migration list**.
3. A person rules on each, singly or in bulk: **Keep**, **Migrate**, or **Cancel and re-raise**,
   with a reason, into `InstanceMigration`.
4. **Migrate** re-plans: committed steps are matched between versions by
   **(`StepId`, `IterationKey`, `Pass`)**; their records are carried forward unchanged; a step
   whose `record.kind` changed between versions is carried and flagged, not re-done; a step present
   in *n* and absent in *n+1* is reported, not dropped; a step new in *n+1* and earlier than the
   current position is placed on the report as *not performed under this version* — a person
   decides whether that is acceptable.
5. Until ruled on, an affected instance continues on its pinned version and shows as *awaiting a
   version ruling*.

**Legacy work at cutover (#56)** uses the same mechanism: every open legacy change lands at the
`COMPLETION` block with its branch states set from the legacy tracks, and steps 1–12 recorded as
*migrated — not performed in this platform*. Detail in `CUTOVER-STRATEGY.md` §5.

---

## 7. Guards, conditions, due — the expression language

All expressions are grammar-1 (`docs/schema/FORMULA-GRAMMAR.md`, C# `src/PnC.Formula`), checked
at authoring against the fact catalogue and evaluated three-valued (#43).

| Where | Result type | Unknown means |
|---|---|---|
| `step.precondition` | Bool | held for a person; unknown facts named |
| `capture.*.validate` | Bool | commit refused |
| `roles.*.requires` | Bool | person refused |
| `choice.cases[].when` | Bool | all Unknown → held for the responsible role |
| `parallel.branches[].applies` | Bool | branch held open for the responsible role |
| `foreach.over` | Set | block held |
| `repeat.until` | Bool | held for the responsible role |
| `hold.until` | Bool | stays held |
| `advances.subject`, `call.subject` | Ref | commit refused |
| `step.due.cadence` | DateTime | `AnchorUnknown` |
| workflow `transition.requires[].when` | Bool | transition blocked; unknown facts named |

**Resolution scope.** Inside a `foreach`, the subject is the member, so a body step's expressions
read `device.*` facts directly. `step.*` facts resolve to **the current member and the current
pass** first, then the enclosing instance; `pass=` and `member=` parameters reach earlier ones.

### Facts the engine publishes

Proposed; names not yet agreed (OQ-14). `step.capture` and `input.*` / `procedure.*` take their
type **from the document**, so the checker consults the document being authored for them.

| Fact | Type | Subject | Parameters |
|---|---|---|---|
| `step.state` · `step.outcome` | Text | ProcedureInstance | `id`, `pass?`, `member?` |
| `step.committed_at` | DateTime | ProcedureInstance | `id`, `pass?`, `member?` |
| `step.committed_by` | Reference (Actor) | ProcedureInstance | `id`, `pass?`, `member?` |
| `step.capture` | the field's declared type | ProcedureInstance | `id`, `field`, `pass?`, `member?` |
| `branch.outcome` | Text | ProcedureInstance | `id`, `member?` |
| `procedure.outcome` | Text | ProcedureInstance | — |
| `procedure.<name>` | the produced entity's kind | ProcedureInstance | — |
| `input.<name>` | the input's declared type | ProcedureInstance | — |
| `work.outage_required` · `work.outage_window_start` | Bool · DateTime | WorkRequest | — |
| `package.revisions` · `package.revision_count` | Set · Number | SettingsIssuePackage | — |
| `record.last` — extend with `.performed_by` | Reference (Actor) | Any | existing fact, new path |

`device.technology` (Text: Microprocessor / Electromechanical / Static) already exists in the
catalogue and is what the electromechanical fork reads.

### Due dates

`due.cadence` is the obligation cadence sub-language unchanged; the due instant is derived when a
board or the sweep asks, never stored (#44). A board derives once per request, not per row.
`escalation` reuses `Program.NotificationType`'s `[{after, role}]` shape.

---

## 8. Authoring, version 1

The owner authors now; P&C engineers later (#28). The first surface is an expert's; the contract it
works to is the thing a friendlier surface will target (#46).

- **The document is edited as JSON** in the existing definitions screen, with
  `procedure.schema.json` enforced live.
- **Every expression is checked live** through `POST /api/v1/formula/check` against the catalogue
  extended with §7's facts and the document's own declared types.
- **Structural checks at save**: every `id` unique; every `role` alias declared; every expression
  reads only facts that exist; every `advances` names a workflow, a transition on it, and a
  subject of the right kind; every `call` names a procedure with an approved version; every
  `due.anchor` names an earlier step; **every step with a `precondition` sits inside a branch that
  some `branchOutcome` can end** (the C1 check); every `produces` name is unique.
- **Approval** through the existing `config.*` procedures with segregation.
- **Projection** on approval.

**W5 (2026-09-12), decisions #119–#122.** Built as `definitions.html` in the shell (API.md §9). The schema and the
structural checks are not two mechanisms: one **dry run** of the save (`POST definitions/documents?dryRun=true`)
answers both, live, with JSON paths, and stores nothing; the expression check stays as a bench for one expression. A
stored version is read back with its expressions **printed as text** (`Printer`), so what is edited is what was
written. `DRAWING_REVISION` v2 was the first procedure authored there (`examples/drawing-revision.procedure.json`).

In production at NB Power, until the friendly editor exists, procedures are authored by the
supplier at the client's request. `REQUIREMENTS.md` FR-1.5 says so, so the client reads FR-1.1
correctly.

---

## 9. The worked example — the settings change

`examples/settings-change.procedure.json`, v0.2. Fourteen steps; four things the legacy system
could not do.

**Every device's settings are a file (#50, #61).** The `BUILD` foreach's body is a `choice` on
`device.technology`: a microprocessor relay gets `BUILD_SETTINGS` — the vendor's native file,
required; anything else gets `RECORD_SETTINGS` — a **text settings file in name=value form**, the
legacy `SET1` format (`WDG1=2.9, WDG2=2.9, SLOPE=25 %, HARMONIC RESTRAINT = 20%`). Both commit as
configuration-file revisions in the settings book. Each device model has a **template** naming the
settings it carries; the file family's reader parses the file against the template; and every
setting on every device is read through **one accessor** — the grammar's existing
`device.settings.<key>` fact, which is the owner's `X('wdg1') = 2.9`. Adding a file type is
writing a reader; adding a model is writing a template; neither is a release.

**A relay can leave the change (#51).** `RESOLVE_DIFFERENCE` with outcome *ChangeRaised* ends that
member's branch as `Superseded`; the corrective request owns the relay; the other ten continue;
the request can close.

**Two completion tracks, not three (#58).** `COMPLETION` is a `parallel` block with two branches:
*Documentation* (a `call` to `DRAWING_REVISION`) and *Settings database* (`BASELINE`). The legacy
software track is gone from the procedure; its 1,906 non-NA rows migrate as notes on the change.

**The package is created by the procedure (#52).** `REQUEST` produces it; every later `advances`
names `procedure.package`.

| FR-3.1 step | Block | Delivers |
|---|---|---|
| 1 request | `REQUEST` | produces the package |
| 2 scope and design | `SCOPE` | the `devices` set |
| 3 study | `STUDY` | required evidence |
| 4 vendor tool | `BUILD` foreach → `choice` → `BUILD_SETTINGS` / `RECORD_SETTINGS` | iteration; the electromechanical fork |
| 5 rationale | `RATIONALE` | |
| 6 independent check | `CHECK` | segregation; `repeat` |
| 7 approval | `APPROVE` | `precondition`; `advances`; `repeat` |
| 8 issue | `ISSUE` | `advances` |
| — | `AWAIT_OUTAGE` | `hold` |
| 9 apply | `FIELD` foreach → `APPLY` | field capture, deferred commit |
| 10 readback | `READBACK` → `READBACK_RESULT` → `RESOLVE_DIFFERENCE` | `validate`; `choice`; `branchOutcome` |
| 11 test | `TEST` | `due`; `deviation` |
| 12 return to service | `RETURN_TO_SERVICE` | `witness`; `advances` |
| 13 baseline | `COMPLETION` → `BASELINE` | parallel track; `advances` |
| 14 drawings | `COMPLETION` → `UPDATE_DRAWINGS` | `call` |

---

## 10. Reporting parity — how the legacy views become queries

| Legacy | Platform |
|---|---|
| Grid state **Active** (`A`) | `SETTINGS_LIFECYCLE` in `InService` |
| Grid state **Outstanding** (`M`) | `SETTINGS_LIFECYCLE` in any non-terminal state |
| Grid state **Archived** (`P`) | `SETTINGS_LIFECYCLE` in `Superseded` |
| Track status **Complete / NA / In progress** — documentation, database | `BlockInstance` rows under `COMPLETION`: Completed / NotApplicable / Running |
| Track status — **software** | not modelled (#58); legacy values are notes on the migrated request |
| Action type **Change / Add / Delete / Verify** | four `Program.WorkType` keys |
| **Set Verified Date** | `step.committed_at[id='RETURN_TO_SERVICE']` |
| **Request Change** / **Post-Close** / **Cancel** | *Start* / *Close* (guarded) / *Cancel* with a reason |
| **Print** by state | the grid query, filtered |
| **Grid by Location / Protected Asset / Protection Function** | **the default view over the FLOC tree** (#57): a projection of `location.Node` → `asset.Placement` → `scheme.CommissionedFunction`, kept indefinitely. Navigation by station, panel, scheme and device type (FR-7.2) is the same tree, browsed |

---

## 11. Coverage

| Capability | Delivered by | Exercised in the example |
|---|---|---|
| Ordered steps | `sequence` | `MAIN` |
| Typed data capture | `step.capture` | `SCOPE`, `RECORD_SETTINGS`, `READBACK` |
| Conditional branching | `choice` | `DEVICE_KIND`, `READBACK_RESULT` |
| Guards and preconditions | `step.precondition`; workflow `requires` | `APPROVE`, `ISSUE`, `TEST`; *Close* |
| Role and competency | `roles.*` | `technician` |
| Sign-off with attribution | `step.signoff` + segregation | `CHECK`, `RETURN_TO_SERVICE` |
| Evidence at a step | `step.evidence` | `STUDY`, `BUILD_SETTINGS`, `READBACK`, `TEST` |
| Parallel branches | `parallel` | `COMPLETION` |
| Sub-procedures | `call` | `UPDATE_DRAWINGS` |
| Timing and due dates | `step.due` | `TEST` |
| Hold points | `hold` | `AWAIT_OUTAGE` |
| Recorded deviation | `step.deviation` | `TEST` |
| Iteration over a set | `foreach` | `BUILD`, `FIELD` |
| Branch exit | `step.branchOutcome` | `RESOLVE_DIFFERENCE` |

Requirements FR-1.1–1.5, FR-2.1–2.2, FR-3.1–3.4, FR-7.1 (shape), FR-7.2 are each satisfied by a
named section above.

---

## 12. Settled since v0.1, and what remains

Closed by the owner on 2026-09-11 (`DECISION-LOG.md` #59–#72):

- **The fact names in §7** — accepted as proposed (#67).
- **Electromechanical settings** — a text settings file parsed against a per-model template, read
  as `device.settings.<key>` (#61). Templates are seeded from the legacy `SET1` patterns; a card
  will put the per-model field sets to the owner.
- **The predecessor's eight draft workflow definitions** — discarded (#70).
- **A hold past its maximum raises an obligation** (#69). The sweep of §4.1 raises it.
- **Reads of a step's draft are audit-logged** (#68), like reads of evidence.
- **Role codes** — `PCEngineer` with scoped grants, `PCTechnician`, `Administrator`, `PCApprover`
  as a grant (#66).

Still not decided here:

- **API endpoints** — implied by the shapes above, not specified.
- **`DRAWING_REVISION`** — referenced, not authored.
- **The per-model templates' actual field sets** — a task, with a card, not a design question.
