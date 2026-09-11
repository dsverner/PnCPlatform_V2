# Schema review — what survives the rewrite

**`PnCPlatform_DEV` judged against `REQUIREMENTS.md` v0.2.**

| | |
|---|---|
| Database | `PnCPlatform_DEV` on 10.10.70.25 |
| Engine | SQL Server 2022, 16.0.4265.3 |
| Read | 2026-09-11, by direct catalogue query |
| Requested | Interview round 1 — *"a full review of the schema based upon an exhaustive interview of the desired outcomes"* |

Measured, not remembered. Every claim below was read from the catalogue or the data.

---

## 1. Verdict

> **Keep the foundation. Replace the procedure layer.**
> The part that fails the central requirement is **7 tables and 124 rows**.
> The part that works holds **1,182,939**.

| | Rows | What |
|---|---:|---|
| Subsystems that work | **1 182 939** | Temporal machinery, identity, locations, assets, documents, records, evidence, definitions. Mature, populated, satisfying nine requirements outright |
| The layer that fails | **124** | The whole procedure and workflow subsystem: 7 tables, never activated, expressing 2 of 13 required capabilities |

Total: 302 tables, 1 183 063 rows, 510 stored procedures, 365 views, 32 functions.

The rebuild was decided because the system had grown beyond what one person could hold in their
head. The measurement says the problem is **narrower than the decision implied** — and that a
clean-sheet rewrite would discard 1.18 million rows of working, migrated data to fix a subsystem
holding 124.

**Decision taken (Round 7): carry forward.** See `docs/reference/CARRY-FORWARD-MAP.md`.

---

## 2. What the schema already does well

Nine requirements are met by structures that exist and hold data.

| Req | What it needs | What exists | Verdict |
|---|---|---|---|
| FR-1.1 | Procedures as authored definitions, not code | `config.Definition` / `DefinitionVersion` / `DefinitionAppliesTo` — 17 kinds, 1 821 definitions, versioned, approved, scoped | **built** |
| FR-1.3 | In-flight work pinned to its version | `WorkflowInstance.WorkflowDefinitionVersionRowId` · `Record.TemplateDefinitionVersionRowId` · `TestPlanStep.DefinitionVersionRowId` | **built** |
| FR-3.3 | In-service separate from approved | `document.ConfigurationFile` — `CaptureKind`, `InServiceFrom` / `To`, `DifferentialRecordEntityId` | **built** |
| FR-3.4 | Non-microprocessor devices first-class | `asset.CharacteristicValue` and `record.CharacteristicValue`, typed and generic by host · `ref.AssetType`: Secondary 79, Primary 56, Hybrid 11, NonEnergised 1 | **built** |
| FR-4.1 | Point-in-time truth | Two-level identity (`EntityId` / `RowId`) · 161 of 302 tables system-versioned · 108 carry valid time | **built** |
| FR-5.1 | Work Request distinct from Cascade order | `work.WorkRequest` — 11 879 rows · `WorkRequestCascadeLink` · `CascadeWorkOrder` | **built** |
| FR-5.2 | Drawings traced by depiction, not link | `document.RevisionLink` — `LinkKind`, `SubjectKind`, `SubjectEntityId`, **`DrawingKey`**. Exactly the model the requirement specifies | **built** |
| FR-5.3 | Test evidence owned inside the platform | `record.Record` · `Acceptance` (bi-temporal, `SupersededByRecordEntityId`) · `TestSheet` / `TestResult` / `TestReading` | **built** |
| FR-6.3 | No hard deletes; everything attributable | `IsDeleted` / `DeletedBy` / `DeletedAt` and `CreatedBy` / `ModifiedBy` on every table · `personnel.Actor` | **built** |

### A correction recorded

An earlier draft of the requirements asserted that this schema did not take non-microprocessor
devices seriously, reasoning from `config.SettingDefinition` (996 rows) and
`Transform.SettingsParse` assuming parseable vendor files.

**That was wrong, and was withdrawn after checking.** The characteristic model is generic and
typed, and the asset taxonomy carries 79 Secondary and 11 Hybrid types against 56 Primary. An
electromechanical relay's taps are held as characteristics, not as a degenerate settings file.
FR-3.4 is already satisfied.

The claim was made before the check. It is recorded here because the review's value depends on the
difference between those two things.

---

## 3. Where it fails — the procedure vocabulary

The only step model in the database is `config.TestPlanStep`. Its entire expressive vocabulary is
eight columns:

```
Sequence · Description · Instruction · SubjectKind · SubjectSelector
ExpectedResult · IsRequired · ServesObligationRuleDefinitionEntityId
```

Measured against the thirteen capabilities required by `REQUIREMENTS.md` FR-1.2 and FR-1.4:

| Capability | Status | Evidence |
|---|---|---|
| Ordered steps | **built** | `TestPlanStep.Sequence` |
| Typed data capture at a step | **built** | `TestPlanReading` → `record.TestReading` |
| Iteration over a set | *partial* | `SubjectKind` + `SubjectSelector` target a subject; they do not repeat a group of steps per member |
| Sign-off with attribution | *partial* | `record.Acceptance` attaches to a record, not to a step |
| Evidence attached at a step | *partial* | `compliance.EvidenceLink` cites records; no step-level binding |
| Conditional branching | **absent** | No condition, predicate or next-step column anywhere |
| Guards and preconditions | **absent** | No guard expression on step or transition |
| Role and competency per step | **absent** | Roles exist per workflow *state*, in JSON, never per step |
| Parallel branches | **absent** | `Sequence` is a single integer ordering |
| Sub-procedures | **absent** | No step may reference another definition |
| Timing and due dates | **absent** | Due dates exist on obligations, not on steps |
| Hold points and suspension | **absent** | No suspended state; only `IsCancelled` on the instance |
| Recorded deviation | **absent** | `IsRequired` is a boolean with nowhere to record why it was not met |

**2 built · 3 partial · 8 absent.**

### The structural gap — bigger than any missing column

Round 5 settled that a workflow step invokes a procedure. **No column anywhere in the database
connects the two.** Every column in all 302 tables was searched for a reference from a workflow or
a state to a procedure or test plan; the only matches tie test *records* back to test plans:

```
config.TestPlanReading.TestPlanStepRowId
record.TestReading.TestPlanReadingRowId
record.TestResult.TestPlanStepRowId
record.TestSheet.TestPlanDefinitionVersionRowId
```

The two layers exist and have never been joined.

Further, the `Program.TestPlan` definition payload is, in full:

```json
{"steps":"see config.TestPlanStep"}
```

The definition does not contain the procedure — it points at relational rows. A procedure
therefore cannot be versioned, diffed or approved as one document, which is what FR-1.1 requires.

### None of it has ever run

All eight `Program.Workflow` definitions are `Status=Draft` with no effective date, migrated from
a legacy `workflow.WorkflowTemplate` table. `work.WorkflowInstance` holds 10 rows, all over work
requests, in three states (Assigned, Closed, Done).

`SETTINGS_APPROVAL`, the closest thing to the settings lifecycle, expresses six states —
Calculated → Checked → Approved → Applied → Verified → Archived — with roles per state and a
reason required on rework. Against the fourteen-step path of FR-3.1, that is a lifecycle skeleton,
not a procedure.

---

## 4. On the size problem

`NFR-3` makes comprehensibility a requirement. It deserves a measured answer.

| Count | What it is |
|---:|---|
| 302 | Tables, as reported |
| 190 | Actual entity tables |
| 112 | Mechanical `…Registry` twins — one per entity, generated by a single pattern, carrying no domain meaning of their own |

**Thirty-seven per cent of the apparent size is one repeated pattern.** That does not make the
system small, but it means the thing to understand is **190 entities and one convention**, not 302
independent tables. The 510 stored procedures are largely the same story — generated accessors.

This changes the diagnosis. The schema is not incoherent; it is **undocumented at the level a
person reads at**. A subsystem map recovers far more comprehensibility per hour than a rewrite
would. That map is `docs/reference/CARRY-FORWARD-MAP.md`, and maintaining it is a standing
obligation under `CLAUDE.md`.

---

## 5. What was not checked

Stated so this review is not read as more complete than it is.

- **The application layer.** The catalogue and definition payloads were read. The 510 stored
  procedures, the C# API and the front end were not. One targeted exception: `definitions.js` was
  read to establish whether authoring is possible at all — it is, through a raw JSON textarea,
  with segregation of duties enforced on approval.
- **Data quality.** Rows were counted. Whether the 296 200 asset rows or 208 357 location rows are
  correct, complete or trustworthy was not assessed.
- **`PnCPlatform_QA`.** Only `PnCPlatform_DEV` was read. The QA database may differ.
- **The 258 predecessor decisions** were read as a register, not audited individually against the
  schema that implements them.
