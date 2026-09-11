# Carry-forward map — the schema in one head

**This document exists because of `NFR-3`.** The predecessor grew past what one person could hold
in their head. This map is the working answer: what the schema is made of, what generates its
apparent size, and — for each subsystem — whether V2 carries it forward and why.

It is **maintained, not written once.** Anything imported gets a line here.

Source: `PnCPlatform_DEV` on 10.10.70.25, read 2026-09-11. All counts measured.

---

## 1. The size, explained

| Count | What |
|---:|---|
| 302 | Tables, as reported |
| **190** | Entity tables — the things to understand |
| **112** | `…Registry` twins — one per entity, mechanical, no domain meaning of their own |
| 510 | Stored procedures — largely generated accessors over the entities |
| 365 | Views — current / as-of / history views generated from each table's temporal class |
| 1 183 063 | Rows |

**Thirty-seven per cent of the tables are one repeated pattern.** Understanding the schema means
understanding **190 entities and four conventions**, not 302 tables.

## 2. The four conventions that generate the volume

Learn these once; they explain most of what you will see.

1. **Registry twin.** Every entity table `X` has an `XRegistry` holding one row per `EntityId` —
   the stable identity of the thing, separate from the versioned rows that describe it. 112 of
   them. Never carry domain columns.
2. **Two-level identity.** Every row has an `EntityId` (the thing) and a `RowId` (this version of
   a fact about the thing), clustered on a hidden `RowSeq`. `RowId` is the "fact version" that a
   derived result records.
3. **Two clocks.** 161 of 302 tables are system-versioned (transaction time: when did we believe
   this). 108 also carry `ValidFrom` / `ValidTo` / `ValidFromQuality` (valid time: when was this
   true in the world). Point-in-time answers (FR-4.1) come from the pair.
4. **Universal audit columns.** `CreatedBy` · `CreatedAt` · `ModifiedBy` · `ModifiedAt` ·
   `IsDeleted` · `DeletedBy` · `DeletedAt` · `MigrationRunId` on every table. The `By` columns
   reference `personnel.Actor`, never a user.

Two lesser patterns: an **`AlternateKey`** table per schema where things have external numbers
(7 schemas), and a **`CharacteristicValue`** table per schema that hosts typed, definition-governed
attributes (`asset`, `document`, `record`).

All instants are `DATETIMEOFFSET(7)`; record and event rows carry `TimeSourceQuality`.

---

## 3. The subsystems

Twenty schemas. For each: what it owns, its size, the requirement it serves, and the V2 verdict.

**Verdicts:** `carry` — import, deliberately, with a decision-log entry ·
`shape` — import the structure; no Phase 1 data or screens · `replace` — designed new.

### Foundation

| Schema | Entities | Rows | Owns | Serves | Verdict |
|---|---:|---:|---|---|---|
| `ref` | 28 | 747 | Reference data — asset classes and types, node types, manufacturers, models, units, kinds of everything. New types are rows, never releases | FR-3.4 | **carry** |
| `personnel` | 10 | 218 | `Actor`, `Person`, `Position`, `PositionHolder`, qualifications, training, `Authorisation`. Who did a thing, and whether they were allowed to | FR-6.1, FR-6.3 | **carry** |
| `security` | 10 | 426 | `User`, `Role`, `Permission`, `Grant`, `Group`, `Delegation`, `SegregationOverride`. Who may do a thing | FR-6.1, FR-6.2 | **carry** |
| `party` | 2 | 214 | `Entity` (organisational units, the ownership relation) and agreements between them | Boundary | **carry** |
| `audit` | 3 | 409 | `ActionLog`, `BackupRun`, `RestoreTest` | FR-6.3, FR-6.4 | **carry** |
| `platform` | 2 | 10 | `Release`, `Deployment` — what the platform knows about itself | — | **carry** |
| `archive` | 2 | 8 | `Manifest`, `Retention` | — | **carry** |
| `migration` | 4 | 400 800 | `Run`, `Provenance`, `StationCatalogue`, `PositionCatalogue`. Every migrated row cites its run | FR-8.1 | **carry** — and re-examine before reuse: 400 800 rows is the largest schema and describes migrations already done, not ones to come |

### The power system — what exists and where

| Schema | Entities | Rows | Owns | Serves | Verdict |
|---|---:|---:|---|---|---|
| `location` | 8 | 208 357 | The functional-location tree: `Node` (parent + materialised path), `NodeFunction`, `Adjacency` and `Segment` for linear nodes, `Route` / `RouteStep`, `CustodyLocation` for things outside the tree | Boundary: FLOC is Cascade's to the panel, ours below | **carry** |
| `asset` | 7 | 296 200 | `Asset`, `AssetComponent`, `Placement` (bi-temporal position assignment), `OwnershipLink` (role-bearing, valid-time), `Classification` (BES status), `CharacteristicValue` | FR-3.4, FR-4.3 | **carry** |
| `device` | 7 | 9 924 | The physical relay: `Device`, `FirmwareHistory`, `LifecycleEvent` (append-only), `Advisory` with per-device `AdvisoryDisposition`, `KnownDefect` | FR-4.3 advisory trigger | **carry** |
| `scheme` | 12 | 192 | `Scheme` with role-bearing `SchemeMember` and `SchemeProtects`, `CommissionedFunction`, `ProtectionCondition`, `ProtectionOperation` and its snapshot, `FaultRecord` | FR-4.3, FR-4.4 | **shape** |
| `connection` | 16 | 227 | The IEC 61850 logical layer — `Ied`, `LogicalDevice`, `LogicalNode`, `DataAttribute`, datasets, control blocks — plus `Port`, `ProtocolEndpoint`, `NetworkPort`, `SecurityPerimeter` | CIP applicability | **shape** |
| `network` | 13 | 18 171 | The power-system model: `Case`, `Layer`, line sections and their constants, mutual coupling, source equivalents, `ConstantsRun` | Boundary: model is OURS, ASPEN consumes | **shape** |

### Documents, records and evidence

| Schema | Entities | Rows | Owns | Serves | Verdict |
|---|---:|---:|---|---|---|
| `document` | 13 | 121 873 | One document base: `Document` → `Revision` → `File` / `FileStore`. `ConfigurationFile` is a revision subclass carrying the in-service lifecycle. `Drawing`, `Rationale`, `Study`. **`RevisionLink` with `DrawingKey`** is depiction. `SettingsIssuePackageItem`, `ParsedSetting` | FR-3.3, FR-5.2 | **carry** |
| `record` | 11 | 4 947 | `Record` (the middle of the evidence chain), `Acceptance` (bi-temporal), `TestSheet` / `TestResult` / `TestReading`, `Readback`, `Finding`, `ConsistencyCheck`, `CommissioningPackageItem`, `Instrument` | FR-5.3, FR-4.2 | **carry** |
| `compliance` | 15 | 13 094 | `Standard` / `StandardVersion` / `Requirement`, `ObligationInstance` with `ObligationInstanceFact` (the rule and fact versions that produced it), `RuleEvaluationRun`, `EvidenceLink`, `EvidencePackage`, `Assertion`, `Audit`, `Exception`, `Interpretation` | FR-4.2 | **shape** |
| `event` | 7 | 30 | `Event`, `SerRecord`, `Channel`, `SampleBlock`, `PhasorBlock`, `PmuStream`, `LightningStrike` | FR-4.4 | **shape** |

### Definitions and work — the layer that changes

| Schema | Entities | Rows | Owns | Serves | Verdict |
|---|---:|---:|---|---|---|
| `config` | 11 | 59 600 | The definition engine: `Definition` / `DefinitionVersion` / `DefinitionAppliesTo` (17 kinds, 1 821 definitions). `CharacteristicDefinition` (23 386). `SettingDefinition`, `StandardSettingEntry`, `EnumerationValue`, `TransformMapping`, `ReadLoggedClass` | FR-1.1, FR-1.3 | **carry** — except `TestPlanStep` and `TestPlanReading`, which are **replaced** |
| `work` | 9 | 47 616 | `WorkRequest` (11 879), `WorkRequestCascadeLink`, `CascadeWorkOrder`, `Notification` / `NotificationDelivery`, `Subscription` | FR-5.1 | **carry** — except `WorkflowInstance` and `WorkflowTransition`, which are **replaced** |
| **`process`** | 12 | 0 | **New — designed, not built.** Projections from approval: `ProcedureStep`, `ProcedureStepRole`, `ProcedureFactUse`, `ProcedureCall`. Runtime: `WorkflowInstance`, `WorkflowTransition` (re-homed), `ProcedureInstance`, `InstanceVersionSet`, `BlockInstance`, `StepInstance`, `HoldInstance`, `InstanceMigration` | FR-1.x, FR-2.x | **new** — `docs/design/PROCEDURE-ENGINE.md` §4 |

### The application code — not carried

This map is a map of the **schema**. The owner ruled on 2026-09-11 (decision #64) that the
predecessor's **application is rewritten** on the same stack, against the recommendation to carry
it. Two pieces of code are carried, each with the same deliberate re-justification as a schema
subsystem:

| Carried | Why |
|---|---|
| `src/PnC.Formula` — the grammar-1 library and its 133-case conformance suite | The engine's every condition, validation and cadence runs on it; the design (#43) depends on it unchanged |
| `docs/schema/ddl/` — the SQL project that builds `PnCPlatform.dacpac`, with `Roles.sql` and the publish profile | The schema itself is carried (#21); the project is how it deploys |
| `ddl/tools/deploy.py` — build → publish → generate → build → publish → smoke, `--fresh` | The one command every wave's gate starts with (#76) |
| `ddl/tools/generate.py` · `check_generated.py` — temporal views and base write procedures emitted from the deployed catalogue via the `PnC.TemporalClass` extended property | The `process` schema's twelve tables get their views and procedures without hand-writing; the check keeps generated files honest |
| `ddl/tools/smoke.py` — 252 schema checks, re-runnable on a populated database | The schema gate; the seven replaced tables' checks are removed in W0 and the new total recorded |
| `ddl/tools/record_release.py` · `tools/package_release.py` — the `platform.Release` fact; dacpac + published site + SBOM + `release.json` with SHA-256s | Every deploy to DEV or QA goes through a release package |
| `tools/rehearse_relocation.py` | The QA acceptance run from three vantage points; W8's gate |
| `docs/schema/gate/` — the extensibility-gate toy (decision #77) | Re-run once in W0 to prove the carried schema still has the property |
| `src/PnC.Api.Smoke` | **Rewritten in W1**, not carried: it targets the API surface, which is new. Its role-based check shape is kept |

Not carried: `src/PnC.Api` (the generic dispatcher, forms, definitions editor, expression checker
UI, rule runs, notifications, feed puller, Windows-auth middleware) and `wwwroot/` (the PWA).
Their *designs* remain consultable in the predecessor's `PLATFORM-ARCHITECTURE.md`; their code is
not imported. Estimated cost of the rewrite: 60–100 h (`PHASE-1-ESTIMATE.md` A).

### What is replaced

Seven tables, 124 rows. See `docs/review/SCHEMA-REVIEW.md` §3 for why, and
`docs/design/PROCEDURE-ENGINE.md` for what replaces them.

```
config.TestPlanStep            config.TestPlanStepRegistry     → the procedure document (a step block) + process.ProcedureStep
config.TestPlanReading         config.TestPlanReadingRegistry  → step.capture in the document + record.CharacteristicValue at commit
work.WorkflowInstance          work.WorkflowInstanceRegistry   → process.WorkflowInstance (same shape, re-homed)
work.WorkflowTransition                                        → process.WorkflowTransition (+ FiredByStepInstanceEntityId, GuardEvaluation)
```

Plus the `Program.Workflow` and `Program.TestPlan` definition kinds, whose payloads are the shape
being replaced — by `workflow.schema.json` and `procedure.schema.json` respectively. The
`config.Definition` base they sit in is carried unchanged.

---

## 4. How to read a table you have never seen

1. Strip the four conventions. Ignore `RowSeq`, `RowId`, `EntityId`, `SysStart`, `SysEnd`, the
   `Valid*` triple, the eight audit columns and `MigrationRunId`. What is left is the domain.
2. If it ends in `Registry`, it holds nothing but identity. Look at its twin.
3. If it has `ValidFrom`, it is a fact about the world that was true for a period. If it does not,
   it is a fact about the platform.
4. If a `By` column looks like it should be a user, it is an actor. Follow it to `personnel.Actor`.
5. Its temporal class is an extended property on the table; the current / as-of / history views
   are generated from it and are what the application reads. **The application never reads a base
   table** — `app_execute` holds no rights on them by design.

---

## 5. Not yet mapped

- The 510 stored procedures and 365 views have not been catalogued here. They are generated from
  the tables and conventions above; a per-schema list is a later addition to this document.
- `PnCPlatform_QA` has not been compared with `_DEV`.
