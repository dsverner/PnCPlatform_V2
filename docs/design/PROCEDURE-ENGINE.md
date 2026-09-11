# The procedure engine — design

**Status:** design v0.1, 2026-09-11, for the owner's mark-up. No code exists.

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

Five forks were put to the owner before this was written and are recorded as decisions #38–#42.
Everything else here is proposed and open to mark-up.

---

## 1. Thesis

> The engine is the only place a procedure lives, and it is the boundary between drafting and record.

Two jobs, in that order.

**Configurability (FR-1.1).** Every procedure the group follows is a document — versioned, approved,
interpreted at runtime. Changing how the group works is a new version of a document, never a
release. The engine has no knowledge of settings, tests or compliance; it knows blocks, steps,
roles, facts and records. The settings change in `examples/` is the first document it runs, not a
special case inside it.

**The commit boundary (FR-2.2).** Before a step commits, everything in it is a draft: editable,
unlogged as evidence, visible only to those working it. When a step commits, a `record.Record` is
written and the step becomes immutable. The record is the platform's existing immutable object —
bi-temporal acceptance, evidence links, obligations already consume it. This is how the work
environment and the system of record coexist: they are the same rows, on opposite sides of one
event.

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
cleanly, and cannot express a deadlock or an unreachable step. That property is what lets a later
friendly editor render a procedure as an outline rather than a diagram.

| Block | What it does | Capability it delivers |
|---|---|---|
| `step` | One unit of work a person performs and commits | ordered steps · data capture · role and competency · sign-off · evidence · due · deviation · guard (`precondition`) |
| `sequence` | Items in order | ordered steps |
| `parallel` | Branches concurrently, rejoining on `all`, `any` or *n*; a branch may declare `applies` | parallel branches |
| `choice` | The first case whose `when` is true; optional `else` | conditional branching |
| `foreach` | The body once per member of a set, subject rebound to the member; `all`/`any`/*n* join | iteration over a set |
| `repeat` | The body again until a condition holds, with a maximum | rework, without a back-edge |
| `call` | Another procedure as a child instance, version pinned with the parent | sub-procedures |
| `hold` | A legitimate wait — outage, part, approval, external — released by condition or by hand, with a maximum | hold points and suspension |

### The step, in full

A step names a **role** (an alias resolved to a `security.Role` code, optionally with a
`requires` expression over `person.*` facts for competency). It may declare:

- `precondition` — a boolean that must be true before the step can start. Unknown holds it and
  names the facts that were unknown.
- `capture` — typed fields (`num` with unit and base, `text` with an allowed list, `bool`, `date`,
  `ref`, `set`, `file`), each optionally `required` and with a `validate` expression over `value`.
  Held as a draft; written as characteristic values on the record at commit.
- `record` — the `ref.RecordKind` the commit produces, and its template where it has one. **Every
  step produces a record** (#42).
- `outcomes` — the step's outcome vocabulary, chosen at commit. Default `Done`.
- `signoff` — the segregation `action` this commit is (*Calculate*, *Check*, *Approve*…), and
  whether a `witness` must co-attest. `Program.SegregationRule` already carries actionA/actionB
  pairs and the WarnAndLog / Block modes; the engine adds rows for its actions and calls the
  existing check.
- `evidence` — files bound to the record, with required kinds and a minimum.
- `due` — a cadence and an anchor step. **Derived on read, never stored** (#44).
- `deviation` — whether the person may `skip` or `vary`, and the finding category. **A deviation
  always requires a reason and always produces a `record.Finding`** on the instance (#48).
- `advances` — the transition to fire on a workflow instance at commit (§2).

---

## 4. Runtime — the `process` schema

A new schema, `process`, hosts both layers' runtime and the projections (#45). Every table carries
the four conventions of `CARRY-FORWARD-MAP.md` §2; only domain columns are listed. All temporal
classes as the conventions require; instances and steps are system-versioned so that "what did
this step look like when it was committed" is answerable.

### Definitions — projected on approval

| Table | Domain columns | Purpose |
|---|---|---|
| `ProcedureStep` | `DefinitionVersionRowId` · `StepId` · `BlockPath` · `Title` · `RoleAlias` · `RoleCode` · `RecordKindCode` · `SignoffAction` · `HasDue` · `AllowsDeviation` | One row per step; what screens list and what impact queries join |
| `ProcedureStepRole` | `ProcedureStepRowId` · `RoleCode` · `RequiresAst` | Who may perform it |
| `ProcedureFactUse` | `DefinitionVersionRowId` · `BlockPath` · `FactName` | Every fact any expression in the document reads — the impact index: *which procedures read `device.technology`?* |
| `ProcedureCall` | `DefinitionVersionRowId` · `BlockPath` · `CalleeKey` | The call graph, for pinning and impact |

The document is authoritative; these rows are derived and rebuilt on approval. Nothing writes to
them otherwise.

### Instances

| Table | Domain columns | Purpose |
|---|---|---|
| `WorkflowInstance` | `WorkflowDefinitionVersionRowId` · `SubjectKind` · `SubjectEntityId` · `CurrentState` · `StartedAt` · `StartedByActorId` · `CompletedAt` · `IsCancelled` | Re-homed from `work` with the same shape |
| `WorkflowTransition` | `WorkflowInstanceEntityId` · `OccurredAt` · `FromState` · `ToState` · `TransitionName` · `ActorId` · `Reason` · `FiredByStepInstanceEntityId` · `GuardEvaluation` (JSON: each guard, its result, its unknowns) · `ActionLogId` | Every transition, with why it was allowed |
| `ProcedureInstance` | `DefinitionVersionRowId` · `ParentInstanceEntityId` · `CallBlockPath` · `WorkflowInstanceEntityId` · `InvokedAtState` · `SubjectKind` · `SubjectEntityId` · `WorkRequestEntityId` · `Inputs` (JSON) · `State` (Running · Held · Completed · Cancelled) · `Outcome` · `StartedAt` · `StartedByActorId` · `CompletedAt` | One run. `ParentInstanceEntityId` is set for a `call` |
| `InstanceVersionSet` | `ProcedureInstanceEntityId` · `CalleeKey` · `DefinitionVersionRowId` | Every callee version resolved at the root's start (#40). The whole tree is one version set |
| `BlockInstance` | `ProcedureInstanceEntityId` · `ParentBlockInstanceEntityId` · `BlockPath` · `BlockKind` · `IterationKey` · `MemberSubjectKind` · `MemberSubjectEntityId` · `State` · `Outcome` · `StartedAt` · `CompletedAt` | One row per activation of a structural block; a `foreach` member or a `repeat` pass is its own row |
| `StepInstance` | `BlockInstanceEntityId` · `StepId` · `State` (Pending · Ready · Active · Held · Committed · Skipped · Varied) · `AssignedRoleCode` · `Draft` (JSON) · `DraftModifiedAt` · `CommittedRecordEntityId` · `CommittedByActorId` · `WitnessedByActorId` · `CommittedAt` · `Outcome` · `DeviationFindingEntityId` · `HeldReason` | The mutable side, then the pointer to the immutable side |
| `HoldInstance` | `BlockInstanceEntityId` · `Reason` · `HeldAt` · `HeldByActorId` · `ReleasedAt` · `ReleasedByActorId` · `ReleaseBasis` (Condition · Manual · Expired) | A hold is reportable as such, never as an abandoned step |
| `InstanceMigration` | `ProcedureInstanceEntityId` · `FromDefinitionVersionRowId` · `ToDefinitionVersionRowId` · `Decision` (Keep · Migrate · Cancel) · `Reason` · `DecidedByActorId` · `DecidedAt` · `StepMapping` (JSON) | The outstanding-work decision (#41) |

`DueAt` is **not a column**. It is derived on read from the step's cadence and the anchor step's
`CommittedAt`, by the application, exactly as obligations' due dates are (#44).

### What is not here

The seven predecessor tables (`config.TestPlanStep`, `TestPlanReading`, `work.WorkflowInstance`,
`WorkflowTransition`, their registries) are **not imported**. `record.TestSheet` keeps its
`TestPlanDefinitionVersionRowId` column name for now; it will point at a `Program.Procedure`
version whose document is a test procedure. That rename is a migration-time decision, not a
design one.

---

## 5. Commit

The one event that matters. In order, and atomically:

1. **Precondition** — already true, or the step could not have started.
2. **Validation** — every `capture` field's `validate` expression is evaluated with `value` bound.
   A false or **Unknown** result refuses the commit and names the unknown facts
   (`FORMULA-GRAMMAR.md` §5: a value that cannot be validated is not accepted).
3. **Competency** — the role alias's `requires` expression for the committing person.
4. **Segregation** — `signoff.action` against `Program.SegregationRule` for this procedure instance
   as subject; WarnAndLog needs a stated reason, Block needs a second person's override
   (`security.SegregationOverride`), as the definitions screen already does today.
5. **Witness** — a second attributed actor where `signoff.witness` is true.
6. **Record** — a `record.Record` of the declared kind: `SubjectKind` / `SubjectEntityId` = the
   step's subject (the foreach member where inside one), `WorkRequestEntityId`, `PerformedByActorId`,
   `WitnessedByActorId`, `OccurredAt`, `OverallResult` = the outcome,
   `TemplateDefinitionVersionRowId` = the procedure version. Captured fields become
   `record.CharacteristicValue` rows; evidence files become `document.File` rows linked to it.
7. **Kind-specific rows** — a `Readback` step writes `record.Readback`; a deviation writes
   `record.Finding` with the declared category and the reason; a `Finding` record kind writes one
   directly.
8. **Acceptance** — where the step's record kind requires acceptance, a `record.Acceptance` row is
   opened for the accepting role. Acceptance is bi-temporal; it is a later act, not part of commit.
9. **Advances** — the declared workflow transition is fired with the step instance as the actor's
   basis; its guards and roles apply; `WorkflowTransition.FiredByStepInstanceEntityId` records it.
10. **Immutability** — `StepInstance.State` = Committed; `Draft` is retained as it stood (system
    versioning keeps the history) but is no longer writable; `CommittedRecordEntityId` is set.

Before step 1 there is a draft and nothing else. After step 10 there is a record and a pointer.
Correcting a committed step is a new valid-time assertion on the record, never an edit of it.

---

## 6. Version pinning and migration

**Pinning (#40, FR-1.3).** When a root procedure instance starts, the engine resolves the approved
version of the root document and, walking its `ProcedureCall` rows transitively, of every callee.
All are written to `InstanceVersionSet`. From then on the run reads only those versions. A `call`
reached later starts its child against the pinned version, not the current one. *Which procedure did
this request follow?* has exactly one answer per instance.

**A new version is approved (#41).** The owner's concern, verbatim from the design interview:
*"if I have 1000 outstanding work requests dealing with compliance issues based on a particular
standard requirement and that requirement changes… will those changes not fall through the
cracks?"* They do not, because nothing is silent:

1. Approval of version *n+1* computes the **affected instances**: every running instance whose
   `InstanceVersionSet` contains version *n* of this document, directly or as a callee. This is
   the impact trigger *a template revision* / *a standard changes* of FR-4.3, applied to work.
2. The engine opens a **migration list** — the affected instances, their current step, and how far
   each has progressed.
3. A person with the Administrator or responsible-engineer role **rules on each**, singly or in
   bulk: **Keep** (finish on the pinned version), **Migrate** (continue on *n+1* from the current
   step), or **Cancel and re-raise**. Every ruling carries a reason and lands in
   `InstanceMigration`.
4. **Migrate** re-plans: the engine matches committed steps by `StepId` between the two versions,
   carries the committed records forward unchanged (they are facts; they do not move), records the
   mapping in `StepMapping`, and resumes at the first step of *n+1* not satisfied by a carried
   commit. A step present in *n* and absent in *n+1* is reported, not dropped. A step new in *n+1*
   and earlier than the current position is placed on the migration list's report as *not
   performed under this version* — a person decides whether that is acceptable, and the decision
   is the reason.
5. Until ruled on, an affected instance continues on its pinned version and shows as *awaiting a
   version ruling* on every board that lists it.

An instance that was never affected is never touched. The thousand each end with a cited version
and a cited decision.

---

## 7. Guards, conditions, due — the expression language

All expressions are grammar-1 (`docs/schema/FORMULA-GRAMMAR.md`, C# `src/PnC.Formula`), checked at
authoring against the fact catalogue and evaluated three-valued (#43). This is not a new language;
it is the one the predecessor already uses for obligation scope, validation and transforms, and its
§7 already prescribes an AST under `"when"` for workflow guards.

| Where | Expression | Result type | Unknown means |
|---|---|---|---|
| `step.precondition` | boolean | Bool | held for a person; unknown facts named |
| `capture.*.validate` | boolean over `value` | Bool | commit refused |
| `roles.*.requires` | boolean over `person.*` | Bool | person refused |
| `choice.cases[].when` | boolean | Bool | all Unknown → held for a person |
| `parallel.branches[].applies` | boolean | Bool | branch held open for a person |
| `foreach.over` | set of Reference | Set | block held; cannot iterate an unknown set |
| `repeat.until` | boolean | Bool | held for a person |
| `hold.until` | boolean | Bool | stays held |
| `advances.subject`, `call.subject` | Reference | Ref | commit refused |
| `step.due.cadence` | cadence | DateTime | `AnchorUnknown`, as obligations do |
| workflow `transition.requires[].when` | boolean | Bool | transition blocked; unknown facts named |

### Facts the engine publishes

The catalogue holds 45 facts today, six of them under `record.*`, `person.*` and `work.*`
(`compliance.vFactCatalogue`, read 2026-09-11). Procedures need to reason about their own state
and about work. The engine contributes the following; names and types are **proposed** (OQ-14).

| Fact | Type | Subject | Parameters |
|---|---|---|---|
| `step.state` | Text | ProcedureInstance | `id` |
| `step.outcome` | Text | ProcedureInstance | `id` |
| `step.committed_at` | DateTime | ProcedureInstance | `id` |
| `step.committed_by` | Reference (Actor) | ProcedureInstance | `id` |
| `step.capture` | the field's declared type | ProcedureInstance | `id`, `field` |
| `foreach.outcome` | Text | ProcedureInstance | `id`, `member` |
| `procedure.outcome` | Text | ProcedureInstance | — |
| `procedure.instances` | Set (ProcedureInstance) | WorkflowInstance | `key` |
| `input.<name>` | the input's declared type | ProcedureInstance | — |
| `work.outage_required` | Bool | WorkRequest | — |
| `work.outage_window_start` | DateTime | WorkRequest | — |
| `work.settings_package` | Reference (SettingsIssuePackage) | WorkRequest | — |
| `package.revisions` | Set (ConfigurationFileRevision) | SettingsIssuePackage | — |
| `package.revision_count` | Number | SettingsIssuePackage | — |
| `record.last` — extend with `.performed_by` path | Reference (Actor) | Any | existing fact, new path |

Inside a `foreach`, the subject is the member, so a body step's expressions read `device.*` facts
directly; `step.*` facts resolve within the member's own branch first, then the enclosing instance.

### Due dates

`due.cadence` is the obligation cadence sub-language unchanged: `within 30 d of event` anchored at
the named step's commit, `every 6 mo from …`, `once`. The due instant is derived when a board or
a notification run asks, never stored, exactly as obligations after the owner's 2026-09-10 ruling.
`escalation` reuses `Program.NotificationType`'s `[{after, role}]` shape.

---

## 8. Authoring, version 1

The owner authors now; P&C engineers later. So the first surface is an expert's, and the contract
it works to is the thing a friendlier surface will target (#46).

- **The document is edited as JSON**, in the existing definitions screen's editor, with
  `procedure.schema.json` enforced live: wrong key, missing required, bad enum — marked in place.
- **Every expression is checked live** through the existing `POST /api/v1/formula/check` against
  the fact catalogue extended with §7's facts: the error position, the canonical form and the
  inferred type shown, as `expression.js` already does for formulas.
- **Structural checks at save**: every `id` unique; every `role` alias declared; every
  `precondition`/`when`/`until` reads only facts that exist; every `advances` names a workflow key,
  a transition on it, and a subject whose kind matches the workflow's; every `call` names a
  procedure that has at least one approved version; every `due.anchor` names an earlier step.
- **Approval** through the existing `config.*` procedures: a different person from the author
  (`Program.SegregationRule` Author/Approve on DefinitionVersion already exists), a change note, the
  canonical document and its hash stored.
- **Projection** on approval into `process.ProcedureStep`, `ProcedureStepRole`,
  `ProcedureFactUse`, `ProcedureCall`.

What a later friendly editor does is render the same document as an outline of blocks, offer the
allowed children at each point, and build expressions from the fact catalogue — and produce
exactly the JSON this schema accepts. Nothing in the model changes for it to exist.

---

## 9. The worked example — the settings change

`examples/settings-change.procedure.json` is the fourteen-step path of FR-3.1 as one document. It
exists to prove the vocabulary is sufficient, and it does three things the legacy system could not.

**The three tracks are one block.** `LEGACY-SYSTEM.md` §6 found the change request completed
across three hard-coded tables — documentation, settings database, settings software — each
independently Complete / NA / In progress. Here that is `COMPLETION`, a `parallel` block with three
branches and `join: all`. One branch is a `call` to a drawing-revision procedure; two are steps.
Adding a fourth track is adding a branch.

**Rework is a loop, not a back-edge.** `DESIGN_AND_CHECK` is a `repeat` around build → rationale →
check, `until` the check's outcome is *Pass*, with a maximum of five passes. Each pass is its own
set of committed steps; the second check does not overwrite the first. `APPROVAL` is a second
`repeat` around the approval step for the *Rejected* case.

**The join runs both ways.** The request's own workflow starts the procedure on *In progress* and
cannot *Close* until it completes. Inside, four steps `advance` the package's lifecycle — Approve,
Issue, Verify, Baseline — so the package's state is always a consequence of committed, attributed
work and never something a person sets.

| FR-3.1 step | Block | Delivers |
|---|---|---|
| 1 request | `REQUEST` | capture with an allowed list |
| 2 scope and design | `SCOPE` | the `devices` set every `foreach` iterates |
| 3 study | `STUDY` | required evidence of a kind |
| 4 vendor tool | `BUILD` foreach → `BUILD_SETTINGS` | iteration; signoff action *Calculate* |
| 5 rationale | `RATIONALE` | |
| 6 independent check | `CHECK` | signoff action *Check* — segregated from *Calculate*; outcomes; `repeat` |
| 7 approval | `APPROVE` | `precondition` on the check; signoff *Approve*; `advances`; `repeat` |
| 8 issue | `ISSUE` | `precondition`; `advances` |
| — | `AWAIT_OUTAGE` | `hold` with a release condition and a maximum |
| 9 apply | `FIELD` foreach → `APPLY` | per device; competency on the technician role |
| 10 readback | `READBACK` | `validate` on a captured number; `choice` on its value; a `Finding` |
| 11 test | `TEST` | `precondition` on the readback outcome; `due` anchored at `APPLY` with escalation; `deviation: vary` |
| 12 return to service | `RETURN_TO_SERVICE` | `witness`; `advances` |
| 13 baseline | `COMPLETION` → `BASELINE` | one of three parallel tracks; `advances` |
| 14 drawings | `COMPLETION` → `UPDATE_DRAWINGS` | `call` to `DRAWING_REVISION` |

`DRAWING_REVISION` is referenced and not yet authored. It is the next document.

---

## 10. Reporting parity — how the legacy views become queries

`FR-8.2` makes parity with the legacy application the acceptance gate. Every legacy view maps to a
query over `process.*` and the carried schemas.

| Legacy | Platform |
|---|---|
| Grid state **Active** (`A`) | `SETTINGS_LIFECYCLE` instances in `InService` |
| Grid state **Outstanding** (`M`) | `SETTINGS_LIFECYCLE` instances in any non-terminal state; equivalently `SETTINGS_CHANGE` instances Running or Held |
| Grid state **Archived** (`P`) | `SETTINGS_LIFECYCLE` instances in `Superseded` |
| Track status **Complete / NA / Change In Progress** | `BlockInstance` rows under `COMPLETION`: Completed / NotApplicable / Running |
| Action type **Change / Add / Delete / Verify** | `Program.WorkType` key on the work request |
| **Set Verified Date** | the commit instant of `RETURN_TO_SERVICE` — `step.committed_at[id='RETURN_TO_SERVICE']` |
| **Request Change** | *Start* on `SETTINGS_CHANGE_REQUEST` |
| **Post Request / Close** | *Close*, guarded by the procedure's completion |
| **Cancel / Delete Work Request** | *Cancel* with a reason; nothing is deleted |
| **Print** by state | the same grid query, filtered by lifecycle state |

The legacy `D` rows have no counterpart; they are dropped at cutover (#31).

---

## 11. Coverage

### The thirteen capabilities

| Capability | Delivered by | Exercised in the example |
|---|---|---|
| Ordered steps | `sequence` | `MAIN` |
| Typed data capture | `step.capture` | `SCOPE`, `READBACK` |
| Conditional branching | `choice` | `READBACK_RESULT` |
| Guards and preconditions | `step.precondition`; workflow `requires` | `APPROVE`, `ISSUE`, `TEST`; *Close* |
| Role and competency per step | `step.role` → `roles.*.role` + `requires` | `technician` |
| Sign-off with attribution | `step.signoff` + segregation | `CHECK` vs `BUILD_SETTINGS`; `RETURN_TO_SERVICE` witness |
| Evidence at a step | `step.evidence` | `STUDY`, `BUILD_SETTINGS`, `READBACK`, `TEST` |
| Parallel branches | `parallel` | `COMPLETION` |
| Sub-procedures | `call` | `UPDATE_DRAWINGS` |
| Timing and due dates | `step.due` | `TEST` |
| Hold points | `hold` | `AWAIT_OUTAGE` |
| Recorded deviation | `step.deviation` → `Finding` | `TEST` |
| Iteration over a set | `foreach` | `BUILD`, `FIELD` |

### Requirements

| Requirement | Where |
|---|---|
| FR-1.1 procedures are definitions, never code | §1, §3, §8 |
| FR-1.2 the vocabulary | §3, this table |
| FR-1.3 in-flight work pinned | §6 |
| FR-1.4 iteration | §3 `foreach`; `BUILD`, `FIELD` |
| FR-1.5 authoring surface | §8 |
| FR-2.1 workflow invokes procedure; completion satisfies guard | §2; both example workflows |
| FR-2.2 mutable until commit | §1, §5 |
| FR-3.1 the fourteen steps | §9 |
| FR-3.2 approval precedes application | `APPLY` follows `ISSUE` follows `APPROVE` in sequence; `ISSUE.precondition` |
| FR-3.3 in-service separate from approved | `READBACK` → `Readback` record → `RESOLVE_DIFFERENCE` |

---

## 12. Not decided here

- **The fact names in §7** — proposed, not agreed. OQ-14.
- **Read logging of a step's draft** — decision #65 logs configuration files and evidence; a draft
  is neither yet. OQ-15.
- **The predecessor's eight draft `Program.Workflow` definitions** — this design recommends
  discarding them and authoring fresh; `SETTINGS_LIFECYCLE` already supersedes `SETTINGS_APPROVAL`.
  Not ruled. OQ-16.
- **Whether a `hold` past its `maxDuration` raises an obligation** or only escalates. OQ-17.
- **`security.Role` codes for V2** — `PCEngineer`, `PCApprover`, `PCTechnician` are placeholders
  pending the seven account types' mapping. OQ-18.
- **Document-aware typing.** `step.capture[id=…, field=…]` and `input.<name>` have the type the
  document declares for that field or input, not one fixed catalogue type. The generic checker
  cannot know this: in verification, `foreach.over` expressions type-checked as `num` against a
  placeholder entry, which is not a type check at all. The C# checker therefore needs a
  document-aware catalogue hook — given the document being authored, it resolves those facts'
  types from it. Without that hook, `over`, `advances.subject` and `call.subject` are not
  genuinely type-checked at authoring. Part of OQ-14.
- **API endpoints** — the shapes above imply them; they are not specified.
- **The `DRAWING_REVISION` procedure** — referenced, not authored.
- **How `record.TestSheet.TestPlanDefinitionVersionRowId` is renamed** at migration.
