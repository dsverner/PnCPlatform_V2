# PnCPlatform — Schema Design

**Status:** design pass complete, 15 steps (2026-09-03/04) · next: extensibility gate, then DDL · **Started:** 2026-09-03 · **Owner:** Daren Verner, P.Eng.

The design record of the schema pass named in the vision (§10.1) as the first step of the
project. It is written step by step in the order the final readiness review set
(`../vision/reviews/2026-09-03-final-readiness-review.md` §E), each step interviewed with the
owner, compared against the predecessor catalogue, and committed before the next begins.

**Precedence.** The vision document (`../vision/PnCPlatform-Vision.md`) §4 and §10 govern. This
document refines them into tables, columns, keys and procedures. Where it must deviate, the
deviation is logged in Appendix A with a rationale. Decisions here continue the numbering of the
sketch session's log, which ended at 65.

**The predecessor.** `dbPCPlatform_DEV` on VM01 (190 tables, catalogue at
`../reference/dbPCPlatform_DEV-schema.md`) is consulted for comparison of fields only. It does
not meet the vision's requirements and nothing is adopted from it by default; what is lifted is
named, and what is corrected is named.

**Hard rules carried forward** (`CLAUDE.md`): no hard deletes; audit columns on every table;
granular access control; no credentials in source; never fabricate — where a field's meaning is
not known from the vision, the sketches or the owner, it is marked *open*.

---

## 0. Conventions

### 0.1 Database and schemas

**Database name: `PnCPlatform`.** Decided 2026-09-03 (66). Environments are separate installs
(vision §8.5) and carry the same name; where two must share one server, as on VM01 during
development, a suffix distinguishes them — `PnCPlatform_DEV`, `PnCPlatform_QA` — and never in
production. The predecessors keep their names (`dbPCPlatform`, `dbPCPlatform_DEV`,
`dbRelayManagement_legacy`, `dbGridInfo`) so nothing is confused with them.

**Schemas** are the domain set of vision §10.5, as amended by decisions 41, 58 and the `record`
schema:

| Schema | Holds | Step |
|---|---|---|
| `location` | the functional-location tree: point and linear nodes, adjacency, routes, custody locations, Cascade cross-reference, geography | 3 |
| `asset` | assets of the four classes, characteristics, ownership links, classification | 4 |
| `device` | device positions, assignments, lifecycle events, firmware history, advisories, defects | 5 |
| `connection` | the abstract connection, realisations, ports, paths; the network model as cyber-asset inventory | 6 |
| `scheme` | schemes, scheme types, membership, protection conditions, protection operations | 7 |
| `document` | document base, revisions, files, configuration files, drawings, revision links, rationale | 8 |
| `work` | Work Requests, work types, workflow instances, Cascade cross-references | 9 |
| `record` | records of every kind, test plans, sheets, results, readbacks, findings, instruments | 10 |
| `party` | organisations: the utility and its divisions, neighbouring utilities, carriers, manufacturers, contractors, regulators | 4 |
| `personnel` | persons, actors, positions, groups, qualifications, authorisations | 11 |
| `security` | users, roles, grants, delegations, segregation rules | 11 |
| `compliance` | standards, versions, requirements, rules, instances, evidence links, assertions, packages, audits, exceptions | 12 |
| `network` | the electrical network model (vision §4.9) | 13 |
| `event` | event and synchrophasor records, operational tier | 13 |
| `config` | the `definition` base and its versions; system settings | 2 |
| `ref` | reference data: manufacturers, models, firmware versions, device types, standards codes | 4, 5 |
| `audit` | append-only action log | 1 |
| `migration` | provenance and staging | 14 |
| `archive` | the archive tier's structures, if co-located (vision §10.6) | 13 |

### 0.2 Naming

- Tables: singular PascalCase (`asset.Asset`, `scheme.SchemeMember`). Columns: PascalCase.
- The entity identity column is `EntityId`; the row-version column is `RowId`; the hidden
  clustering column is `RowSeq`. Foreign keys to an entity are `<Role>EntityId`; to a specific
  row version, `<Role>RowId`.
- Valid time: `ValidFrom`, `ValidTo`. Transaction time is supplied by system versioning
  (`SysStart`, `SysEnd`, hidden).
- Audit: `CreatedBy`, `CreatedAt`, `ModifiedBy`, `ModifiedAt`, `IsDeleted`, `DeletedBy`,
  `DeletedAt`. (`At` rather than `Date` because the values are instants with offset.)
- Booleans `Is…` / `Has…`; codes `…Code`; free text `Notes`.
- No abbreviations in names except those the domain uses as words: CT, VT, DC, SCD, CID, GOOSE.

### 0.3 The universal base — every record table

Decided 2026-09-03 (67–73), answering the step-1 questions.

| Column | Type | Notes |
|---|---|---|
| `RowSeq` | `BIGINT IDENTITY` | clustered index; never exposed; exists to keep inserts sequential |
| `RowId` | `UNIQUEIDENTIFIER` | **the fact version**; unique; the value an obligation instance, an evidence link or an as-of snapshot cites |
| `EntityId` | `UNIQUEIDENTIFIER` | the stable public identity; the same across every row version of the thing; FK to the schema's `…Registry` table |
| `ValidFrom` / `ValidTo` | `DATETIMEOFFSET(7)` | valid time, on valid-time and bi-temporal classes; `ValidTo` null = open; may be unknown or estimated (flag below) |
| `ValidFromQuality` | `TINYINT` | `0` exact, `1` estimated, `2` unknown-defaulted — needed for as-found readbacks (vision §4.4) and migrated history (§10.3) |
| `SysStart` / `SysEnd` | `DATETIME2(7)` | system-versioning period columns, hidden; SQL Server maintains them |
| `CreatedBy` / `ModifiedBy` | `UNIQUEIDENTIFIER` | FK to `personnel.Actor.ActorId`, never to a user |
| `CreatedAt` / `ModifiedAt` | `DATETIMEOFFSET(7)` | stamped by the procedure |
| `IsDeleted` / `DeletedBy` / `DeletedAt` | `BIT`, FK, `DATETIMEOFFSET(7)` | soft delete only |
| `MigrationRunId` | `UNIQUEIDENTIFIER` | null unless migrated; joins `migration.Run` and `migration.Provenance` |

**Two-level identity (67).** A thing has one `EntityId` for life and one `RowId` per fact row.
The predecessor's registry/record split (`core.AssetRegistry.EntityID` + `core.Asset.RecordID`)
is lifted as the shape; its `ClosedBy` is replaced by `ModifiedBy` on the closing row plus system
versioning. Every schema with entities carries a `<Entity>Registry` table of `EntityId` alone,
which is what foreign keys reference when they mean "the thing" rather than "the fact".

**Clustering (67).** Clustered on `RowSeq`; unique nonclustered on `RowId`; nonclustered on
`(EntityId, ValidFrom)` for as-of lookups. GUIDs are generated by the procedure as sequential
GUIDs (`NEWSEQUENTIALID()`-equivalent from the application) so `RowId` ordering roughly follows
insert order.

**Temporal class as metadata (69).** Every table carries an extended property
`PnC.TemporalClass` with one of:

| Class | Columns present | System-versioned | Examples |
|---|---|---|---|
| `BiTemporal` | valid time + system | yes | configuration files, approvals, obligation instances, scheme membership, classification, protection conditions, grants |
| `ValidTime` | valid time + system | yes | device and asset characteristics, ownership links, test readings, firmware history |
| `Versioned` | version number + effective date + system | yes | definitions and their versions |
| `Reference` | system only | yes | `ref.*` and lookup tables |
| `AppendOnly` | none | **no** | `audit.*`, `event.*` |

**System-versioning scope (70).** Every table is system-versioned except the `AppendOnly` class.
The distinction between "valid-time" and "bi-temporal" is therefore not *whether* transaction
time exists — it always does — but whether the design *reads* it: bi-temporal tables get as-of
views on both clocks; valid-time tables get a current view and a history view, and their system
history is there for corrections and for the fact-version chain of decision 54.

**Soft delete (71).** `IsDeleted = 1` closes belief in the row; it does not touch `ValidTo`. A
real end of validity is a valid-time update that closes `ValidTo` on the current row. Generated
current views exclude deleted rows; as-of views include them when the as-of transaction time
precedes the deletion.

**Actor on audit columns (72).** `CreatedBy` and `ModifiedBy` reference `personnel.Actor`. The
write procedure resolves the actor from the session's authenticated user plus any delegation or
sponsorship in force at that instant, creating an actor row if that combination has not been
seen; actor rows are immutable. Detail in step 11.

**Timestamps (73).** Every instant is `DATETIMEOFFSET(7)`, stored as supplied with its offset.
Record and event rows additionally carry `TimeSourceQuality` (`TINYINT`: GPS-locked, NTP,
relay clock unverified, manual entry, migrated-unknown) — audit columns do not. Units and base
(primary / secondary, per-unit) ride on numeric characteristics (step 2) and are part of the
formula language's contract (vision §7.7).

**Generated views (69).** A generator reads `PnC.TemporalClass` and emits, per table:
`<schema>.v<Table>` (current: latest valid row per entity, not deleted, `SysEnd` = max),
`<schema>.f<Table>AsOf(@validAt, @believedAt)` (bi-temporal only), and `<schema>.v<Table>History`.
The application and reporting read nothing else (vision §7.5, §10.3). Hand-written views are a
review finding.

### 0.4 Alternate keys — one table per schema (68)

The identities the field and the drawings use — designation, serial number, cable number,
structure number, wire number, Cascade functional location, NERC id — are not columns scattered
across entities. Each schema has one table:

| `<schema>.AlternateKey` | Type | Notes |
|---|---|---|
| base columns | | class `ValidTime` |
| `EntityId` | FK → the schema's registry | the thing the key names |
| `KeyKind` | `NVARCHAR(50)` FK → `ref.AlternateKeyKind` | designation, serial, cable number, structure number, Cascade FLOC, NERC id, wire number (scoped), … |
| `KeyValue` | `NVARCHAR(200)` | as written on the nameplate or drawing |
| `ScopeEntityId` | `UNIQUEIDENTIFIER`, null | for keys unique only within a parent: a wire number within a panel (decision 18), a structure number within a line's numbering |
| `IsPrimaryLabel` | `BIT` | the one shown by default when several exist |

Unique filtered index on `(KeyKind, KeyValue, ScopeEntityId)` where `ValidTo IS NULL AND
IsDeleted = 0`. Search across the platform is a union over the per-schema tables through one
generated view `core.vAlternateKey`. A renumbering closes one row and opens another, so history
is kept and old drawings still resolve.

`ref.AlternateKeyKind` says, per kind, which schema and entity type may carry it and whether a
scope is required. The predecessor scattered these (`core.Asset.AssetTag`, `Alias`,
`AliasObserved`, `core.Location.Code`, `NERC_ID`, `core.AssetConnection.CableID`, `WireID`);
all of those become rows here.

### 0.5 Write path

All writes go through stored procedures in the owning schema (vision §7.5): the procedure
resolves the actor, stamps audit columns, generates GUIDs, closes the prior valid-time row when a
new fact replaces it, and refuses physical deletes. The application login has `EXECUTE` on
procedures and `SELECT` on generated views only.

---

## 1. Universal base and temporal machinery

The base is §0.3–§0.5 above. This step adds the three tables that exist independently of any
domain.

### 1.1 `audit.ActionLog` — class `AppendOnly`

| Column | Type | Notes |
|---|---|---|
| `ActionLogId` | `BIGINT IDENTITY` | PK, clustered |
| `OccurredAt` | `DATETIMEOFFSET(7)` | |
| `ActorId` | FK → `personnel.Actor` | who, under what authority (the actor row carries the delegation) |
| `ActionKind` | `NVARCHAR(50)` FK → `ref.ActionKind` | transition, approval, override, grant, revocation, administrative, read (for logged object classes), release |
| `SubjectSchema`, `SubjectTable`, `SubjectEntityId`, `SubjectRowId` | | polymorphic subject; `RowId` when the act was against a specific fact version |
| `DefinitionVersionId` | FK → `config.DefinitionVersion`, null | the workflow, rule or gate under which the act was taken |
| `Detail` | `NVARCHAR(MAX)` | structured (JSON) detail: from-state, to-state, override reason |

No update or delete procedure exists for this table; the application login has `INSERT` through
one procedure and `SELECT` through one view. Read logging (decision 65) writes here with
`ActionKind = 'Read'` for the object classes flagged in `config.ReadLoggedClass`.

### 1.2 `migration.Run` and `migration.Provenance`

Lifted from the predecessor's `core.MigrationProvenance`, which already matches vision §10.7,
with two corrections: provenance references the target `RowId` as well as the `EntityId` (so a
migrated *fact version* is traceable, not only the thing), and the run carries the source
capture date and the cleansing-rule set version applied.

| `migration.Run` | Type | Notes |
|---|---|---|
| `RunId` | PK | |
| `SourceSystem` | `NVARCHAR(50)` | legacy settings database, Doble RTS, Cascade export, Relaying Field Notes, TLM |
| `SourceCaptureAt` | `DATETIMEOFFSET(7)` | when the source snapshot was taken |
| `CleansingRuleVersionId` | FK → `config.DefinitionVersion` | the agreed rules (vision §10.7) are a definition |
| `StartedAt`, `CompletedAt`, `RunBy` | | |

| `migration.Provenance` | Type | Notes |
|---|---|---|
| `ProvenanceId` | PK | |
| `RunId` | FK → `migration.Run` | |
| `TargetSchema`, `TargetTable`, `TargetEntityId`, `TargetRowId` | | |
| `SourceKey` | `NVARCHAR(400)` | the source system's key |
| `SourceRowHash` | `BINARY(32)` | for re-run idempotence |
| `Notes` | | mapping decisions taken for this row |

### 1.3 `config.ReadLoggedClass`

The per-object-class switch of vision §9.6: `(SchemaName, TableName, IsLogged, ChangedBy,
ChangedAt)`. Seeded with configuration files and evidence packages on (decision 65).

### 1.4 Comparison with the predecessor

| Predecessor | Verdict |
|---|---|
| Registry + versioned-record split on 44 tables (`EntityID`, `RecordID`, `ValidFrom`, `ValidTo`, `CreatedBy`, `ClosedBy`) | **Lifted** as the two-level identity; `ClosedBy` dropped in favour of `ModifiedBy` on the closing row plus system versioning, which supplies the transaction time the predecessor lacked |
| Audit columns present on some tables (`CreatedBy` 97, `CreatedDate` 56, `ModifiedBy` 28, `IsDeleted` 14 of 190) | **Corrected**: universal base on every table, enforced by the generator |
| `CreatedBy` → `core.PersonRegistry` | **Corrected**: → `personnel.Actor` (decision 44) |
| `datetime2` everywhere, no offset, no source quality | **Corrected** (decision 63) |
| `core.MigrationProvenance` | **Lifted**, with `TargetRowId` and a `Run` table added |
| `core.LoginSession` (614 rows) | Not a schema concern; sessions belong to the application tier (vision §7.5) |
| `hierarchyid` PKs on three tables | Not adopted; the tree of step 3 uses explicit parent references plus a materialised path column, which the adjacency of linear nodes needs anyway |

### 1.5 Decisions taken this step

66 database name · 67 two-level identity and clustering · 68 alternate-key table per schema ·
69 temporal class as metadata with generated views · 70 system-version everything but
append-only · 71 soft delete closes belief only · 72 actor on audit columns · 73
`DATETIMEOFFSET(7)` and `TimeSourceQuality` on record and event rows. All 2026-09-03.

### 1.6 Open

- The exact sequential-GUID strategy (application-generated vs `NEWSEQUENTIALID()` default) is
  an implementation choice for the database project, not a design question.
- Retention of system-version history for high-churn valid-time tables (characteristic values)
  — revisit at step 4 with a volume estimate.

---

## 2. The definition base and the extensibility gate

Vision §4.12 ("nothing above is code"), decisions 45, 46, 51, 58. Answers to step-2 questions
8–12 are decisions 74–78.

### 2.1 `config.Definition` — class `Versioned` (74)

| Column | Type | Notes |
|---|---|---|
| base columns | | `EntityId` is the definition's identity |
| `DefinitionKind` | `NVARCHAR(40)` FK → `ref.DefinitionKind` | one of the three meta-kinds and its sub-kind: `CharacteristicSchema.AssetTemplate`, `CharacteristicSchema.CableType`, `CharacteristicSchema.StructureType`, `CharacteristicSchema.RationaleSchemeType`, `CharacteristicSchema.RationaleDevice`, `CharacteristicSchema.DocumentClass`, `CharacteristicSchema.TestPlanReadings`, `Transform.SettingsParse`, `Transform.SettingsGenerate`, `Transform.SclParse`, `Transform.WordOutput`, `Transform.Import`, `Program.Workflow`, `Program.Formula`, `Program.ObligationRule`, `Program.EvidenceDefinition`, `Program.ClassificationDerivation`, `Program.QualificationRequirement`, `Program.SegregationRule`, `Program.ReportDefinition`, `Program.WorkType`, `Program.SchemeType`, `Program.MaintenanceActivityType`, `Program.CleansingRules` |
| `DefinitionKey` | `NVARCHAR(100)` | alternate key, unique within kind |
| `Name`, `Description` | | |
| `OwningRole` | FK → `security.Role` | who may author (Administrator by default; Compliance Officer for rules — vision §3.2) |

### 2.2 `config.DefinitionVersion` — class `Versioned` (74)

| Column | Type | Notes |
|---|---|---|
| base columns | | |
| `DefinitionEntityId` | FK → `config.DefinitionRegistry` | |
| `VersionNumber` | `INT` | unique per definition |
| `Status` | `NVARCHAR(20)` | `Draft`, `Approved`, `Effective`, `Retired` |
| `EffectiveFrom`, `EffectiveTo` | `DATETIMEOFFSET(7)` | the period this version governs new instances |
| `ApprovedBy` | FK → `personnel.Actor`, null | segregation from `CreatedBy` enforced by `Program.SegregationRule` |
| `ApprovedAt` | | |
| `ChangeNote` | `NVARCHAR(MAX)` | |
| `TestEvidenceRecordId` | FK → `record.RecordRegistry`, null | for programs: the record of the dry run or parity test that approved it |
| `PayloadText` | `NVARCHAR(MAX)` | **programs only** (78): the declarative text the interpreter runs — workflow, formula, rule, report. Characteristic schemas and transforms have no payload here; their content is the structured tables below |
| `PayloadHash` | `BINARY(32)` | for diffing and for evidence packages, which freeze the versions they were produced under |

**Rule enforced by procedure:** exactly one version of a definition may be `Effective` at an
instant for a given applies-to match; a new version's `EffectiveFrom` closes the prior version's
`EffectiveTo`. Every instance, output or result stores the `DefinitionVersion.RowId` it was made
under (decision 51); that column is named `<Role>DefinitionVersionRowId` wherever it appears.

### 2.3 `config.DefinitionAppliesTo` — class `ValidTime` (75)

Typed selector rows, one per dimension, composable; a definition version matches a subject when
every row it carries matches.

| Column | Type | Notes |
|---|---|---|
| base columns | | |
| `DefinitionVersionRowId` | FK → `config.DefinitionVersion.RowId` | |
| `Dimension` | `NVARCHAR(40)` FK → `ref.AppliesToDimension` | `Manufacturer`, `Model`, `FirmwareVersion`, `AssetClass`, `AssetType`, `SchemeType`, `ProtectionApplication`, `DocumentClass`, `SubjectKind`, `StationType`, `VoltageClass`, `WorkType` |
| `ValueEntityId` / `ValueCode` | one of | reference to the dimension's entity or a code |
| `IsOverlay` | `BIT` | an overlay row *adds to* a base match rather than restricting it (the rationale's device template over its scheme-type template, decision 61) |

**Resolver** (a procedure, `config.ResolveDefinition(@kind, @subjectEntityId, @at)`): collect
effective versions of the kind whose non-overlay rows all match the subject's facts; pick the one
with the most dimensions matched; then apply, in order, every effective overlay version whose rows
match. Ties are a configuration error surfaced to the Administrator, not silently resolved.

### 2.4 Characteristic schemas and values (76)

| `config.CharacteristicDefinition` — class `Versioned` | Type | Notes |
|---|---|---|
| base columns | | |
| `DefinitionVersionRowId` | FK | the characteristic-schema version this belongs to |
| `CharacteristicKey` | `NVARCHAR(100)` | unique within the version |
| `Name`, `Description` | | |
| `DataType` | `NVARCHAR(20)` | `Text`, `Integer`, `Decimal`, `Boolean`, `DateTime`, `Reference`, `Enumeration` |
| `Unit` | FK → `ref.Unit`, null | |
| `Base` | `NVARCHAR(20)`, null | `Primary`, `Secondary`, `PerUnit` — numeric only |
| `IsRequired` | `BIT` | |
| `AllowedValuesDefinitionRowId` | FK, null | for enumerations: an enumeration definition |
| `ReferenceTargetKind` | `NVARCHAR(60)`, null | for `Reference`: which registry the value points at |
| `ValidationExpression` | `NVARCHAR(MAX)`, null | in the formula language, evaluated on write |
| `DisplayOrder`, `DisplayGroup` | | |
| `IsCatalogueFact` | `BIT` | **publishes the characteristic to the fact catalogue** (step 12) as `<hostkind>.template.<key>` — this bit is what makes the gate (§2.6) pass |

| `<host>.CharacteristicValue` — class `ValidTime`, one per host kind (`asset`, `record`, `document` for rationale) | Type | Notes |
|---|---|---|
| base columns | | `EntityId` here is the value's own identity; the host is `HostEntityId` |
| `HostEntityId` | FK → the host registry | |
| `CharacteristicDefinitionRowId` | FK | governs type, unit, base, validation |
| `TextValue` `NVARCHAR(400)` · `IntegerValue` `BIGINT` · `DecimalValue` `DECIMAL(28,10)` · `BooleanValue` `BIT` · `DateTimeValue` `DATETIMEOFFSET(7)` · `ReferenceEntityId` `UNIQUEIDENTIFIER` | exactly one non-null, checked against `DataType` by the procedure | |
| `UnitOverride` | FK → `ref.Unit`, null | the unit the value was entered in, if it differs from the definition's; the procedure converts and keeps both |
| `SourceRecordRowId` | FK → `record`, null | where the value came from (a test sheet, a readback, a migration) |

The predecessor's `core.Asset.Attributes` (unbounded JSON text) plus `config.AttributeKey`
(39 typed keys, units, no validation, no version) is the halfway form of this. The JSON is
**corrected** into typed columns; `AttributeKey` is **lifted** in spirit as
`CharacteristicDefinition`, with version, base, validation and the catalogue bit added.

### 2.5 Transforms

A transform version has no `PayloadText`; its content is structured:

| `config.TransformMapping` — class `Versioned` | Notes |
|---|---|
| `DefinitionVersionRowId` | the transform version |
| `Direction` | `Parse` or `Generate` |
| `SourcePath` | the location in the native file: a settings-file token, an SCL XPath, a Word field, a Doble column |
| `TargetKind`, `TargetKey` | a `SettingDefinition` (step 8), a characteristic key, a document field |
| `ConversionExpression` | formula-language expression over `$` (the source token), null if identity — `docs/schema/FORMULA-GRAMMAR.md` §7 |
| `IsRequired`, `DefaultValue` | |

The one parser (vision §7.7) interprets these rows; a new relay firmware is a new transform
version with its own rows, never a code change. Parity tests (vision §7.6) are records cited by
`TestEvidenceRecordId`.

### 2.6 The extensibility gate (77)

Before any table in steps 3–14 is created in the database project, a **toy** proves the
defining property (vision §2.3, §4.12; scenario 5, gaps G17 and G18):

1. Create `config.*` as above plus a minimal `asset.AssetRegistry`, `asset.Asset`,
   `asset.CharacteristicValue`, and the `compliance.FactCatalogue` view generator of step 12.
2. Author an asset template with one characteristic flagged `IsCatalogueFact`. Author a formula
   that derives a second fact from it. Author an obligation rule whose predicate references both.
3. Run the rule in preview: it scopes the expected subjects.
4. **Add a new characteristic** to a new template version, flag it, enter values, and author a
   second rule referencing it.
5. Run in preview again. The new rule must scope correctly **with no change to any table,
   procedure, view or code** outside the rows entered in step 4.

If step 5 needs anything but data, the meta-model is wrong and the design stops here. The gate's
DDL and script live at `docs/schema/gate/`; its result is the first record
in `record.*` of kind `ParityTest`, cited by the approval of every program definition that follows.

**Passed 2026-09-04** on VM01 (`PnCPlatform_DEV`, SQL Server 2022): nine checks, including a
byte-identical object snapshot (98 objects) before step 4 and after step 5. See
`docs/schema/gate/RESULT.md` and `README.md` (deviations and one finding: whether a template
revision carries characteristic values forward — added to §2.10).

### 2.7 Programs are interpreted (78)

Workflow, formula, obligation rule, evidence definition, classification derivation,
qualification requirement, segregation rule, report definition, work type, scheme type and
cleansing-rule payloads are declarative text in `PayloadText`, interpreted at runtime by the
engine of vision §7.7. The grammar is **`docs/schema/FORMULA-GRAMMAR.md`** (grammar 1, 2026-09-05;
decisions 191–196): a text form people author, a canonical JSON AST that `PayloadText` stores and
`PayloadHash` hashes, interpreted by `compliance.fEvalNode` on the database and by the reference
implementation in `docs/schema/grammar/`. It meets the three constraints the schema set: it may
reference only catalogued facts (step 12), it carries units and base on every numeric term (§0.3),
and it is deterministic and side-effect free so that a stored `PayloadHash` reproduces a result —
and adds a fourth: a run never throws on data; a missing value is `Unknown`, propagated and recorded.

### 2.8 Comparison with the predecessor

| Predecessor | Verdict |
|---|---|
| `config.AttributeKey` (39 rows: key, data type, units) | **Lifted** as `CharacteristicDefinition`, with version, base, validation, allowed values, catalogue flag |
| `core.Asset.Attributes` `NVARCHAR(MAX)` JSON | **Corrected** to typed `CharacteristicValue` rows |
| `core.AssetTypeTemplate` (27 rows) | **Lifted** as the `CharacteristicSchema.AssetTemplate` definition kind; its rows migrate as one definition version each (step 14) |
| `protection.SettingTemplate` / `SettingTemplateEntry` / `SettingDefinition` (996 rows) | The settings parse/generate transform of §2.5 and the `SettingDefinition` of step 8; the 996 definitions are a migration seed |
| `workflow.WorkflowTemplate` / `WorkflowStage` / `WorkflowTransition` / `…Registry` | **Corrected**: the predecessor stored workflow structure as rows; here a workflow is a `Program.Workflow` definition with text payload (78); the runtime instance tables are in step 9 |
| `iec61850.SCLTemplate` | the `Transform.SclParse` definition kind |
| No definition versioning, no approval, no applies-to selector, no catalogue | **Added** — this is the meta-model the predecessor lacked (vision §4.12 concern C) |

### 2.9 Decisions taken this step

74 `Definition` / `DefinitionVersion` with payload tables in domain schemas · 75 typed
`DefinitionAppliesTo` rows with most-specific resolver and overlays · 76 typed
`CharacteristicValue` per host kind under a versioned `CharacteristicDefinition` with a catalogue
flag · 77 the extensibility gate runs before any domain DDL · 78 programs are declarative text
interpreted at runtime; schemas and transforms are structured rows. All 2026-09-03.

### 2.10 Open

- ~~The formula-language grammar (vision §13.3)~~ — closed 2026-09-05: `FORMULA-GRAMMAR.md`
  (decisions 191–196). What it leaves open: regular expressions (`matches`, `decode`) have no
  T-SQL implementation on SQL Server 2022 and evaluate to Unknown on the database interpreter;
  the application evaluator carries them.
- Whether `ref.Unit` is seeded from an external unit registry or hand-authored — step 4.
- Whether a new template version carries forward characteristic values entered under the prior
  version, re-validates them, or requires re-entry. The gate toy resolves by (template entity,
  key) across versions; §2.4 does not decide this. Raised by the gate, 2026-09-04.

---

## 3. Location tree

Vision §4.2 governs: the tree, the ground-versus-route test, point and linear nodes with
adjacency, routes, the custody location, the panel as a position, and the Cascade seam
(decisions 7, 8, 13, 17, 20, 23–25, 29–32, 34–35). Decisions here: 79–87.

### 3.1 `ref.LocationNodeType` and `ref.LocationNodeTypeParent` — class `Reference` (80)

Node types are data, seeded from the vision tree, extensible by the Administrator within the
rule that a node type is either a point or a line.

| `ref.LocationNodeType` | Notes |
|---|---|
| `NodeTypeCode` PK | `Region`, `Station`, `Building`, `Room`, `Panel`, `DevicePosition`, `ProtectionFunction`, `TerminalBlock`, `Stud`, `Yard`, `Bay`, `EquipmentPosition`, `JunctionBox`, `Raceway`, `Segment`, `RightOfWay`, `Structure`, `AttachmentPoint`; plus the predecessor's `MeteringPosition` and `NetworkSwitchPosition` as device-position subtypes |
| `Name`, `Description` | |
| `Geometry` | `Point` or `Linear` — only `Raceway` and `RightOfWay` are `Linear` (decision 30) |
| `IsCascadeSupplied` | `Region`, `Station`, `Building`, `Room`, `Panel` true; everything else platform-authored (decision 24) |
| `SubtypeListDefinitionRowId` | FK → an enumeration definition, null: station kind (terminal, substation, generating station, repeater site, switching station, control centre, field site — decisions 13, 86), raceway kind (trench, duct, tray — decision 25) |
| `IsActive` | |

| `ref.LocationNodeTypeParent` | Notes |
|---|---|
| `ChildNodeTypeCode`, `ParentNodeTypeCode` PK | allowed pairs; seeded: Station→Region; RightOfWay→Region; Building, Yard, Raceway→Station; Room→Building; Panel→Building **or** Room (Room optional, 87); DevicePosition, TerminalBlock→Panel; ProtectionFunction, TerminalBlock→DevicePosition; Stud→TerminalBlock; Bay→Yard; EquipmentPosition, JunctionBox→Bay; TerminalBlock→JunctionBox; Segment→Raceway; Structure→RightOfWay; AttachmentPoint→Structure |
| `IsRequired` | whether a child of this type must exist under the parent (none seeded) |

The procedure refuses a node whose type is not allowed under its parent's type.

### 3.2 `location.NodeRegistry` and `location.Node` — class `ValidTime` (81)

| `location.Node` | Type | Notes |
|---|---|---|
| base columns | | `EntityId` → `location.NodeRegistry` |
| `NodeTypeCode` | FK → `ref.LocationNodeType` | |
| `ParentEntityId` | FK → `location.NodeRegistry`, null only for `Region` | one parent, always |
| `Path` | `NVARCHAR(900)` | materialised path of ancestor `EntityId`s, maintained by the procedure; indexed; a subtree query is a prefix match |
| `Depth` | `TINYINT` | |
| `SiblingOrder` | `INT` | display order among siblings; the structure sequence on a right of way uses the route, not this |
| `Name` | `NVARCHAR(200)` | the platform's name for the node; the Cascade name is a `NodeFunction` row (§3.6), not this column |
| `SubtypeCode` | `NVARCHAR(40)`, null | from the type's subtype list: station kind, raceway kind |
| `Location` | `geography`, null | point nodes (83) |
| `Extent` | `geography`, null | linear nodes: a linestring (83) |
| `RegionSplitOfEntityId` | FK, null | a right of way that continues in another region points at its counterpart (decision 23) |
| `Notes` | | |

**Identity and search.** Everything the field calls a node by is an alternate key (§0.4) of kind:
`StationNumber` (the predecessor's four-digit station code, e.g. 4134), `CascadeFloc` (the Cascade
functional-location id, on Cascade-supplied nodes), `SiteAlias` (the two-character alias the
predecessor generated and verified per station), `PanelSlot` (12A, scoped to the building or
room), `StructureNumber` (scoped to the line whose numbering it carries, decision 29). Wire
numbers are on connections, not nodes. *Open (§3.9): which of `StationNumber` and `CascadeFloc`
is the same value, and what the four-digit device-position code in the predecessor denotes.*

**Predecessor mapping.** `core.Location` rows migrate to `location.Node` with type mapped:
`DIVISION` → an `Entity` in the ownership relation, not a node (79); `SUBSTATION`,
`GENERATING_STATION`, `SWITCHING_STATION`, `CONTROL_CENTRE`, `FIELD_SITE` → `Station` with
subtype; `LINE`, `POLE_LINE` → **not nodes**: a line is an asset with a route (decision 29), so
these five rows become `asset.Asset` rows of class Primary with an empty route to be filled from
TLM; `BUILDING`, `YARD`, `BAY`, `PANEL`, `TERMINAL_BLOCK`, `TERMINAL_STUD` → same-named types;
`STRUCTURE` → `Structure` under a `RightOfWay` created per line corridor; `PRIMARY_ELEMENT` →
`EquipmentPosition` under a `Bay` (created if absent) with the primary asset attached;
`RELAY_POSITION` (394 rows, mostly direct under the station) → `Panel` + `DevicePosition`, with
the Cascade name kept as `NodeFunction` and the panel slot left *open* for the owner to supply;
`METERING_POSITION` → `DevicePosition` with device class meter; `NETWORK_SWITCH`,
`SUBSTATION_PC`, `TERMINAL_SERVER` → `DevicePosition` with the matching device class.

### 3.3 Linear nodes — `location.Adjacency` and `location.Segment` (81)

| `location.Adjacency` — class `ValidTime` | Notes |
|---|---|
| `LinearNodeEntityId` | FK → a node whose type is `Linear` |
| `TouchedNodeEntityId` | FK → any node: a room, a bay, a junction box, a station (for a right of way) |
| `Sequence` | `INT` — order along the linear node |
| `Chainage` | `DECIMAL(12,3)`, null — distance from the linear node's start, metres, when known |

| `location.Segment` — a node of type `Segment` whose parent is the linear node | Notes |
|---|---|
| `FromAdjacencyRowId`, `ToAdjacencyRowId` | the two consecutive touch points it lies between; maintained by the procedure when adjacency changes |
| `Length` | `DECIMAL(12,3)`, null |

A raceway's segments are what a cable's route cites; a right of way's structures are what a
line's route cites (structures are point nodes under the right of way, ordered by the route, not
by adjacency — the right of way's adjacency lists the stations it touches).

### 3.4 Routes — `location.Route` and `location.RouteStep` (82)

| `location.Route` — class `ValidTime` | Notes |
|---|---|
| base columns | |
| `OwnerAssetEntityId` | FK → `asset.AssetRegistry` — the cable, line, channel or panel wire whose location this is (decisions 8, 29) |
| `RouteKind` | `Cable`, `Line`, `Channel`, `PanelWire` |
| `FromNodeEntityId`, `ToNodeEntityId` | the end nodes: studs for a cable or panel wire; stations or equipment positions for a line; device positions for a channel |

| `location.RouteStep` — class `ValidTime` | Notes |
|---|---|
| `RouteEntityId` | FK |
| `Sequence` | `INT` |
| `NodeEntityId` | FK → the node passed: a segment, a structure, a station |
| `OccupiedNodeEntityId` | FK, null → what is occupied there: an attachment point on the structure, a stud at the end |
| `OccupiedAssetEntityId` | FK, null → for a channel: the medium asset at this step (fiber pair, multiplexer, radio) |

"What runs through this node" is `RouteStep` filtered by node. A structure that carries several
circuits appears in several lines' routes (decision 29).

### 3.5 `location.CustodyLocation` — class `ValidTime` (84)

Deliberately **not** a node. `(EntityId, Name, CustodyKind [Store, Vendor, ForensicHold,
Calibration], OwnerEntityId → asset.EntityRegistry, Address, Notes)`. A device assignment (step
5) points at either a `DevicePosition` node or a custody location, never both; the check
constraint enforces exactly one.

### 3.6 `location.NodeFunction` — class `ValidTime` (85)

The function a position carries, over time, separate from the position's identity (vision §4.2
"a panel is a position, not a function"; decision 15).

| Column | Notes |
|---|---|
| `NodeEntityId` | FK — any node, in practice `Panel`, `DevicePosition`, `EquipmentPosition` |
| `FunctionLabel` | `NVARCHAR(200)` — the platform's label, e.g. "Line 3001 A protection" |
| `CascadeName` | `NVARCHAR(200)`, null — the Cascade function-based name in force, kept as cross-reference |
| `SchemeEntityId` | FK → `scheme.SchemeRegistry`, null — the scheme this position serves (step 7) |

### 3.7 Cascade seam

The Cascade import (vision §11.2) lands in `migration.*` staging, creates or matches nodes of
Cascade-supplied types by their `CascadeFloc` alternate key, writes the Cascade name into
`NodeFunction.CascadeName`, and never touches platform-authored types. A later re-import updates
names and flags nodes Cascade no longer lists; it does not delete.

### 3.8 Comparison with the predecessor

| Predecessor | Verdict |
|---|---|
| `core.Location` single-parent tree with `LocationTypeID`, `ParentEntityID`, `HierarchyLevel` on the type | **Lifted** in shape; level replaced by allowed-parent pairs and a materialised path; linear nodes and adjacency **added** |
| 21 location types incl. `LINE`, `PRIMARY_ELEMENT`, `DIVISION` as nodes | **Corrected** per the ground-vs-route test: line → asset with route; primary element → equipment position with the asset attached; division → entity |
| `RELAY_POSITION` direct under `SUBSTATION`, named the Cascade way | **Corrected**: panel + device position, Cascade name as `NodeFunction`; slot identity open |
| `Code`, `NERC_ID`, `Abbreviation`, `SiteAliasSeed.AliasFinal` | **Lifted** as alternate-key kinds |
| `Latitude`, `Longitude`, `Address` (unpopulated) | **Lifted** as `geography`; populated from TLM and GIS |
| `IsBES`, `IsNPCC_BPS` bits on Location | **Corrected**: classification is a bi-temporal entity (step 4, decision 39) |
| `VoltageKV` on Location | Moves to the asset (bus, line) or to a node characteristic where it is a property of the place (yard voltage) — step 4 |
| `hierarchyid` (3 tables elsewhere) | Not adopted |

### 3.9 Decisions and open items

**Decided 2026-09-03:** 79 Region is the root; the predecessor's Division is an entity · 80
node types and allowed parents are reference data with a point/linear flag · 81 parent +
materialised path + depth; adjacency and segments for linear nodes · 82 `Route` / `RouteStep`
in the location schema, owned by the asset · 83 `geography` on point and linear nodes · 84
custody location is its own table, never a node · 85 `NodeFunction` valid-time on any node
holds the Cascade name and the platform label · 86 station subtypes seeded: terminal,
substation, generating station, repeater site, switching station, control centre, field site ·
87 Room is optional.

**Answered by the owner 2026-09-05** (recorded verbatim in MIGRATION-PLAN §10):
- The four-digit station code (4134) is what NB Power calls the **asset number**; `StationNumber`
  carries it. Its first digit typically says the station kind: 4 → terminal (transmission-owned,
  69/138/230/345 kV), 5 or 6 → distribution substation (13.8 kV, one site at 25 kV) — owner
  2026-09-05; the loader sets `StationKind` from it and flags the inference. A Cascade FLOC is `<division>-<asset number>[-<sub-location segments>]`
  (`TN-4134-BDG1`): its second segment *is* the asset number, so the two keys agree by
  construction; `CascadeFloc` holds the full string.
- The four-digit device-position code (0125) means nothing the owner knows of — probably added by
  the predecessor's import; **dropped** (kept in Notes) unless a reason to keep it is found.
- The two-character site alias shortens device names on schematic drawings (KE Keswick, MQ
  Mactaquac) and is **unique platform-wide**, as modelled.
- The panel label (34A — the `PNL34A` segment of the FLOC) is the **label drawn on the schematic
  and fixed to the panel at site**; there is no standard nomenclature, and the labels must be
  maintained as they are — `PanelSlot` alternate key on the panel node, scoped to the station.
- Codes such as 97B on a position are **function designations**, not panel labels: device number
  plus protection group. 97 is NB Power's custom device number for the *isolation zone* — the
  device programmed to clear one electrical asset (a GE UR C30 or SEL-2440) — for which no
  standard number exists; so `TN-4134-BDG1-PNL34A-97B` reads transmission-owned, Keswick (asset
  number 4134), building 1, panel 34A, function 97B. `Designation` alternate key (§7.3).

---

## 4. Assets, entities, ownership and classification

Vision §10.1 (four classes, the Hybrid rule), §10.2 (templates describe assets), §4.2
(ownership relation, classification as a bi-temporal entity, attach anywhere), §4.11 (line,
conductor, cable, structure types as templates). Decisions 2–6, 12, 16, 19, 22, 26–28, 39.
Decisions here: 88–97.

### 4.1 `ref.AssetClass` and `ref.AssetType` — class `Reference` (88, 89)

| `ref.AssetClass` | `Primary`, `Secondary`, `Hybrid`, `NonEnergised` with the vision's one-line rule for each; the predecessor's `INTERFACE` maps to `Hybrid` |
|---|---|

| `ref.AssetType` | Notes |
|---|---|
| `AssetTypeCode` PK | seeded from the predecessor's 54 codes plus: `Conductor`, `GroundWire`, `Insulator`, `Tower`, `Pole`, `Cable`, `CableConductor`, `PanelWire`, `JunctionBox`, `MarshallingKiosk`, `MergingUnit`, `NCIT`, `Multiplexer`, `MicrowaveRadio`, `FiberTransceiver`, `CarrierTransmitterReceiver`, `CarrierTuner`, `LineTrap`, `PatchPanel`, `EthernetSwitch`, `OPGW`, `AntennaMount`, `RepeaterSite`, `Building`, `Yard`, `RightOfWay`, `DcSystem`, `Charger`, `TeleprotectionInterface`, `IED` |
| `Name`, `Description` | |
| `AssetClassCode` | FK; fixed per type |
| `IsDevice` | true for types that carry a serial number, firmware and settings: relays, meters, recorders, RTUs, IEDs, switches, clocks, multiplexers, radios, merging units — these get a `device.Device` extension (step 5) |
| `IsRouted` | true for `Cable`, `Line`, `Channel`, `PanelWire`: the asset's location is a `location.Route` |
| `IsAssembly` | true for types that normally have components: `Line`, `DcSystem`, `Transformer`, `Cable`, `Breaker` |
| `DefaultTemplateDefinitionEntityId` | FK → `config.DefinitionRegistry`, the `CharacteristicSchema.AssetTemplate` that applies unless a more specific one matches (§2.3) |
| `IsActive` | |

The Administrator adds an asset type by inserting a row and authoring its template; no release.

### 4.2 `asset.AssetRegistry` and `asset.Asset` — class `ValidTime` (89, 90)

| `asset.Asset` | Type | Notes |
|---|---|---|
| base columns | | |
| `AssetTypeCode` | FK | |
| `Name` | `NVARCHAR(200)` | the platform's display name; designations and numbers are alternate keys |
| `VoltageClassCode` | FK → `ref.VoltageClass`, null | first-class because scoping reads it constantly (97); the catalogue fact `asset.voltage_class` |
| `ManufacturerEntityId` | FK → `party.EntityRegistry`, null | |
| `ModelId` | FK → `ref.Model`, null | for devices and for typed plant (breaker model) |
| `Status` | `NVARCHAR(20)` | `Planned`, `InService`, `OutOfService`, `Retired` — the asset-level state; device lifecycle detail is step 5 |
| `CommissionedAt`, `RetiredAt` | `DATETIMEOFFSET(7)`, null | |
| `Notes` | | |

Everything else about an asset is a `asset.CharacteristicValue` row governed by the resolved
template (§2.4): CT ratio and class, MVA rating, interrupting rating, winding configuration,
battery capacity, and every field the predecessor held in `Attributes` JSON.

**Alternate keys** on assets: `Designation` (87A, scoped to the panel), `SerialNumber` (scoped
to manufacturer), `CableNumber`, `LineNumber`, `WireNumber` (scoped to the panel, decision 18),
`AssetTag` (the predecessor's), `SapEquipmentNumber` when known.

**Device is an asset, extended (90).** Types with `IsDevice = 1` have exactly one `device.Device`
row sharing the `EntityId` (step 5). The predecessor's split into `core.Asset` and
`protection.Device` with separate identities is corrected.

### 4.3 `asset.AssetComponent` — class `ValidTime` (91)

Physical composition, distinct from scheme membership (step 7) and from placement.

| Column | Notes |
|---|---|
| `ParentAssetEntityId`, `ChildAssetEntityId` | FK; a child has at most one parent at a time |
| `ComponentRole` | `NVARCHAR(60)`: phase A conductor, shield wire, bushing H1, tap changer, battery bank, charger, distribution panel, conductor blue, CT core 1 … |
| `Sequence` | `INT`, null |

A line is an assembly of conductors; a DC system of bank, charger and distribution (scenario 2,
gap G8); a cable of its conductors (decision 16); a transformer of bushings and tap changer. The
predecessor's `hardware.DeviceComponent` and `core.Asset.CTBodyEntityID` are both this table.

### 4.4 `asset.Placement` — class `BiTemporal` (92)

The one table that says where an asset is, for every asset, device or not. It is the
device ↔ location assignment of vision §4.10 and decision 32.

| Column | Notes |
|---|---|
| base columns | bi-temporal: "where was it" and "where did we believe it was" both answerable |
| `AssetEntityId` | FK |
| `NodeEntityId` | FK → `location.NodeRegistry`, null |
| `CustodyLocationEntityId` | FK → `location.CustodyLocationRegistry`, null |
| `PlacementKind` | `Attached` (a transformer at its equipment position, a tower at its structure, a building at its station), `Installed` (a device filling a device position), `Stored`, `AtVendor`, `Retained` |
| `InstalledByActorId`, `RemovedByActorId` | |
| `WorkRequestEntityId` | FK, null — the request under which it was placed (step 9) |

Check constraints: exactly one of `NodeEntityId` / `CustodyLocationEntityId`; if the asset
type `IsDevice`, the node must be a `DevicePosition` (or the placement is custody); if
`IsRouted`, the asset has no placement and its location is its `location.Route`. A device
position holds at most one installed device at an instant (unique filtered index).

### 4.5 `party.Entity` — class `ValidTime` (93)

Organisations, distinct from persons: the power company and its divisions, neighbouring
utilities, carriers, manufacturers, contractors, regulators, the standards bodies. A new schema,
`party`, because entities are neither personnel nor assets and both reference them.

| Column | Notes |
|---|---|
| base columns | |
| `Name`, `ShortName` | |
| `EntityKind` | `Utility`, `Division`, `Carrier`, `Manufacturer`, `Contractor`, `Regulator`, `StandardsBody`, `Other` |
| `ParentEntityEntityId` | FK, null — a division of a utility |
| `IsOwnerOrganisation` | true for NB Power and its divisions, the party the platform serves |
| `ExternalIdentifier` | `NVARCHAR(100)`, null — NERC registration, SAP vendor number |

The predecessor's `core.Vendor` (seven rows) and its `DIVISION` location row both migrate here.
`ref.Manufacturer` (§4.7) is a thin reference over entities of kind `Manufacturer`.

### 4.6 `asset.OwnershipLink` — class `ValidTime` (94)

Decisions 1, 26: ownership is a relation, not a level; role and valid time; joint.

| Column | Notes |
|---|---|
| base columns | |
| `SubjectKind` | `Node`, `Asset`, `Scheme`, `RouteStep` (a leased link on a channel) |
| `SubjectEntityId` | FK to the matching registry (polymorphic; enforced by the procedure) |
| `EntityEntityId` | FK → `party.EntityRegistry` |
| `OwnershipRole` | `Owner`, `Operator`, `Maintainer`, `Lessor`, `Lessee` |
| `Share` | `DECIMAL(5,2)`, null — percentage where joint ownership is fractional |
| `IsResponsibleForReporting` | `BIT` — resolves scenario 4's gap G13: which party reports a misoperation on a jointly owned scheme |

Several links may coexist for one subject. The catalogue fact `asset.owner_of_record(role, at)`
reads this table.

### 4.7 `asset.Classification` — class `BiTemporal` (95)

| Column | Notes |
|---|---|
| base columns | |
| `SubjectKind`, `SubjectEntityId` | station node, line asset, scheme, generation resource asset — polymorphic |
| `ClassificationKind` | FK → `ref.ClassificationKind`: `BesStatus`, `CipImpactRating`, `NpccBulkPowerSystem`, `NpccA10`, and any the Administrator adds |
| `ClassificationValue` | `NVARCHAR(60)` from the kind's allowed values |
| `Basis` | `Recorded` (a person entered it, Phase 3) or `Derived` (a classification-derivation definition produced it) |
| `DerivationDefinitionVersionRowId` | FK, null — when derived |
| `DeterminedByActorId`, `DeterminedAt` | |
| `ReferenceDocumentRevisionRowId` | FK → `document`, null — the determination on file |

**Multiple concurrent kinds per subject** are the normal case: one station is BES, has a CIP
impact rating of low, and is on the NPCC A10 list at the same time. Uniqueness is on
`(SubjectKind, SubjectEntityId, ClassificationKind)` over the valid period, so one value per
kind at an instant and any number of kinds. The catalogue facts `station.classification.<kind>`
and `line.classification.<kind>` read this table. Replaces the predecessor's `IsBES`,
`IsNPCC_BPS` bits and `compliance.CIPAssetClassification`.

### 4.8 `ref.Manufacturer`, `ref.Model` — class `Reference` (96)

| `ref.Manufacturer` | `ManufacturerId`, `EntityEntityId` → `party.Entity`, `ShortCode` (SEL, GE, ABB), `IsActive` |
|---|---|

| `ref.Model` | Notes |
|---|---|
| `ModelId` PK | |
| `ManufacturerId` | FK |
| `ModelCode`, `ModelName` | SEL-487E, D60 |
| `AssetTypeCode` | FK — what kind of thing this model is |
| `DeviceCategory` | `NVARCHAR(40)`, null — the predecessor's: protection, metering, SCADA, comms |
| `FirmwareFamily` | `NVARCHAR(60)`, null |
| `MaxSettingGroups` | `TINYINT`, null |
| `VendorSoftware`, `ProjectFileExtension` | the tool and file type the round trip uses (vision §11.6) |
| `Technology` | `Electromechanical`, `Static`, `Microprocessor`, `IEC61850` |
| `VendorLifecycleStatus` | `Active`, `MatureSupport`, `EndOfSale`, `EndOfSupport`, `Obsolete` — with `StatusAsOf` |
| `IsActive` | |

Lifted almost whole from the predecessor's `protection.DeviceType` (51 rows), which was the best
table in it; lifecycle status added (decision 49).

### 4.9 `ref.Unit`, `ref.VoltageClass` — class `Reference` (97)

| `ref.Unit` | `UnitCode` (V, kV, A, kA, MVA, MW, Ah, Ω, %, pu, s, ms, cycles, Hz, m, ft, °C …), `Name`, `Dimension` (voltage, current, power, energy, impedance, time, length, temperature, ratio), `BaseUnitCode`, `ToBaseFactor` `DECIMAL(28,12)` |
|---|---|

| `ref.VoltageClass` | `VoltageClassCode` (`345`, `230`, `138`, `69`, `25`, `12`, `DC125`, `DC48` …), `NominalKv` `DECIMAL(10,3)`, `IsTransmission`, `DisplayOrder` — seeded from NB Power's actual set at migration; the predecessor's `voltage_class:text[kV]` attribute and `VoltageKV` columns collapse into it |
|---|---|

### 4.10 Comparison with the predecessor

| Predecessor | Verdict |
|---|---|
| `core.AssetType` (54) with `DefaultClass` PRIMARY / SECONDARY / INTERFACE, `Module`, `IsContainerOfPrimary` | **Lifted** as `ref.AssetType`; INTERFACE → Hybrid; Non-energised **added**; `Module` dropped (domain schemas replace it); container flag → `IsAssembly` |
| `core.AssetTypeTemplate` (field key, label, type, lookup, required, order) | **Lifted** into `config.CharacteristicDefinition` under a versioned template; migrates as one definition version per asset type |
| `core.Asset.Attributes` JSON + `config.AttributeKey` (39) | **Corrected** to typed `asset.CharacteristicValue`; the 39 keys and the JSON keys observed (rated MVA by cooling stage, winding kV, bushing, tap positions, relay kind) seed the templates |
| `core.Asset` columns `Model`, `FirmwareVersion`, `SerialNumber` as free text | **Corrected**: model is `ref.Model`; firmware and serial move to `device.Device` (step 5); serial is an alternate key |
| `core.Asset.LocationEntityID` (one location, required) | **Corrected** to `asset.Placement`, bi-temporal, node or custody |
| `core.Asset.ProtectedElementEntityID` | Moves to scheme → protects → primary asset (step 7) |
| `core.Asset.IsBES`, `IsNPCC_BPS`, `BES_NPCC_*` and `compliance.CIPAssetClassification` | **Corrected** to `asset.Classification`, bi-temporal, many kinds |
| `core.Asset.WiringReconciliationStatus`, `AliasObserved` | Drawing-reconciliation state belongs on the revision link (step 8), not the asset |
| `core.Vendor` (7), `core.VendorRegistry` | **Lifted** into `party.Entity` kind Manufacturer + `ref.Manufacturer` |
| `protection.DeviceType` (51) | **Lifted** into `ref.Model` |
| `hardware.DeviceComponent`, `core.Asset.CTBodyEntityID` | **Lifted** into `asset.AssetComponent` |
| `core.AssetTag`, `core.Tag` (asset tagging, revocable) | Held over: a general tagging facility is not in the vision; revisit if a use case appears (open) |
| `core.AssetReconciliationEvent`, `DrawingReconciliationFlag` | Step 8 (documents) |

### 4.11 Decisions and open items

**Decided 2026-09-03:** 88 four asset classes as reference data; INTERFACE → Hybrid · 89
`ref.AssetType` as reference rows with class, device, routed and assembly flags and a default
template; seeded from the predecessor plus the sketch additions · 90 one `asset.Asset` table;
devices are an extension sharing the entity id · 91 `asset.AssetComponent` for physical
composition · 92 one bi-temporal `asset.Placement` for every asset, node or custody, which is the
device assignment of decision 32 · 93 organisations are `party.Entity` in a new `party` schema,
distinct from personnel · 94 `asset.OwnershipLink` with role, share and reporting responsibility
· 95 `asset.Classification` bi-temporal, many concurrent kinds per subject, recorded or derived
· 96 `ref.Manufacturer` and `ref.Model` lifted from the predecessor's device type with lifecycle
status · 97 `ref.Unit` with base conversion and `ref.VoltageClass` as a first-class column.

**Open:** whether a general asset tagging facility (the predecessor's `Tag` / `AssetTag`) has a
use in the vision; parked.

---

## 5. Devices — extension, lifecycle, firmware, advisories

Vision §4.12 "Device information" and §4.1 (device history travels with the serial number);
decisions 32, 35, 48–50, 90, 92. Decisions here: 98–106. The device position node and the
placement table are already defined (steps 3, 4); this step is what a physical device carries
that a non-device asset does not.

### 5.1 `device.Device` — class `ValidTime`, extension of `asset.Asset` (98)

One row per asset whose type `IsDevice = 1`, sharing `EntityId`; the procedure creates both.

| Column | Notes |
|---|---|
| base columns | `EntityId` = the asset's; no separate registry |
| `PartNumber` | `NVARCHAR(100)`, null |
| `HardwareRevision` | `NVARCHAR(50)`, null |
| `ManufacturedAt` | `DATE`, null |
| `CurrentFirmwareVersionId` | FK → `ref.FirmwareVersion`, null — **derived** from `FirmwareHistory` by the procedure; kept for query convenience, never edited directly |
| `Notes` | |

Serial number is an alternate key of kind `SerialNumber` scoped to the manufacturer. Network
identity, active settings group and hardware characteristics move out (step 6, step 7,
characteristics §2.4).

### 5.2 `ref.FirmwareVersion` — class `Reference` (100)

| Column | Notes |
|---|---|
| `FirmwareVersionId` PK | |
| `ModelId` | FK → `ref.Model` |
| `VersionString` | as the vendor writes it |
| `VendorReleaseReference`, `ReleasedAt` | |
| `ParseTransformDefinitionEntityId` | FK → `config.DefinitionRegistry` — the `Transform.SettingsParse` that reads this firmware's native file (vision §4.4) |
| `IcdDocumentEntityId` | FK → `document.DocumentRegistry`, null — the ICD that states this firmware's 61850 capability (gap G11) |
| `VendorLifecycleStatus`, `StatusAsOf` | as on `ref.Model` |
| `IsActive` | |

### 5.3 `device.FirmwareHistory` — class `ValidTime` (100)

| Column | Notes |
|---|---|
| base columns | valid period = while this firmware was on the device |
| `DeviceEntityId` | FK |
| `FirmwareVersionId` | FK |
| `AppliedByActorId`, `VerifiedByActorId`, `VerifiedAt` | |
| `WorkRequestEntityId` | FK, null |
| `AdvisoryDispositionEntityId` | FK, null — when the change was a patch (§5.5) |

**Rule:** opening a new row fires the settings re-validation rule for every in-service
configuration file on the device (a `Program.ObligationRule` or workflow, not code), and the
parse transform for the new version must exist or the write is refused with a message naming the
missing definition.

### 5.4 `device.LifecycleEvent` — class `AppendOnly` (99)

| Column | Notes |
|---|---|
| `LifecycleEventId` PK | |
| `DeviceEntityId` | FK |
| `EventKind` | `Received`, `BenchTested`, `Installed`, `Removed`, `SentForRepair`, `Returned`, `Retired`, `Disposed`, `Lost` |
| `OccurredAt` | `DATETIMEOFFSET(7)` + `TimeSourceQuality` |
| `ActorId` | |
| `NodeEntityId` / `CustodyLocationEntityId` | where, exactly one |
| `WorkRequestEntityId`, `RecordEntityId` | null — the request and the record (bench test sheet) that go with it |
| `Notes` | |

Current lifecycle state is `vDeviceState`, derived from the latest event; `Installed` and
`Removed` events are written by the same procedure that writes `asset.Placement`, so the two never
disagree.

### 5.5 `device.Advisory` and `device.AdvisoryDisposition` (102)

| `device.Advisory` — class `ValidTime` | Notes |
|---|---|
| base columns | |
| `IssuerEntityEntityId` | FK → `party.Entity` — the vendor, or a CERT |
| `AdvisoryReference` | `NVARCHAR(100)` — vendor bulletin id, CVE id |
| `AdvisoryKind` | `SecurityVulnerability`, `ProductDefect`, `Patch`, `EndOfLife`, `Recall` |
| `Severity` | `NVARCHAR(20)` |
| `PublishedAt`, `NotifiedAt` | when issued; when NB Power learned of it |
| `DocumentEntityId` | FK → `document` — the bulletin on file |
| `Summary`, `MitigationSummary` | |

| `device.AdvisoryScope` — class `ValidTime` | `AdvisoryEntityId`, `ModelId`, `FirmwareVersionFromId`, `FirmwareVersionToId` (null = all) — which models and firmware ranges it names |
|---|---|

| `device.AdvisoryDisposition` — class `BiTemporal` | Notes |
|---|---|
| base columns | bi-temporal: an assessment is an approval-like act |
| `AdvisoryEntityId`, `DeviceEntityId` | FK |
| `Applicability` | `Applicable`, `NotApplicable`, `Undetermined` |
| `AssessedByActorId`, `AssessedAt` | |
| `Action` | `Patch`, `Mitigate`, `Accept`, `Replace`, `None` |
| `DueAt` | derived from the rule, stored for the record when the assessment is made |
| `CompletedAt` | |
| `DeferralReason`, `RiskAcceptedByActorId`, `DeferralReviewAt` | |
| `WorkRequestEntityId` | FK, null |

The predecessor's `compliance.CIPPatchRecord` and `supplychain.CVERecord` are both this pair:
patch assessment fields (available, assessed, applied, deferral, risk acceptance) are the
disposition; the advisory is the bulletin. Obligation rules of the patch-management family
(verify) scope on `device.advisories[open]` from the catalogue.

### 5.6 `device.KnownDefect` — class `ValidTime` (103)

`(EntityId, ModelId, FirmwareVersionFromId, FirmwareVersionToId, Description, Workaround,
VendorReference, AdvisoryEntityId null, ReportedByActorId, Status)`. A defect found in the field
before the vendor names it; later linked to the advisory when one issues.

### 5.7 Device position kind (101)

`ref.LocationNodeType` row `DevicePosition` gets a subtype list: `Relay`, `Meter`, `Recorder`,
`Rtu`, `EthernetSwitch`, `TimeClock`, `Multiplexer`, `Radio`, `TeleprotectionInterface`,
`MergingUnit`, `SubstationPc`, `TerminalServer`, `Other`. `asset.Placement` refuses a device
whose `ref.Model.DeviceCategory` does not match the position's subtype unless the actor holds an
override grant, in which case it logs.

### 5.8 No stored baseline (104)

The CIP configuration baseline of a device is a **view**, `device.vBaseline(@deviceEntityId,
@validAt, @believedAt)`: the in-service configuration file (step 8), the firmware in force
(§5.3), the ports and services (step 6), open advisory dispositions (§5.5), and the placement.
An evidence package (step 12) freezes the view's output by citing the `RowId`s it read. The
predecessor's `compliance.CIPConfigBaseline` snapshot table is **not** carried: a stored snapshot
drifts from the facts it copied.

### 5.9 `party.EntityAgreement` — class `ValidTime` (105)

Shape only, no Phase 1 build: `(EntityId, EntityEntityId → party.Entity, AgreementKind
[SupportContract, SupplyChainAcknowledgement, Licence], ProductLine, Reference, StartsAt,
EndsAt, EndOfSupportAt, EndOfLifeAt, AcknowledgementDocumentEntityId, ContactPersonEntityId)`.
The supply-chain risk-management family's vendor acknowledgements (verify against current text)
are rows of kind `SupplyChainAcknowledgement`. The predecessor's `supplychain.VendorAgreement`
and `SupplyChainAck` are this table.

### 5.10 Modules inside a device (106)

A card or module with its own serial and firmware is an asset of type `DeviceModule` (a device
type), a component of its host via `asset.AssetComponent` with role = slot designation, and has
its own `device.Device` row, so `FirmwareHistory` and advisories apply to it. The predecessor's
`hardware.DeviceComponent` is this; its `SlotDesignation` becomes the component role.

### 5.11 Comparison with the predecessor

| Predecessor | Verdict |
|---|---|
| `protection.Device` (72 rows): firmware, hardware rev, IP, subnet, gateway, DNP3, 61850 LD, active settings group, part number, serial, hardware characteristics JSON | **Split**: identity → `asset.Asset` + `device.Device`; firmware → `FirmwareHistory`; network → step 6 ports; active group → step 7 condition; JSON → characteristics |
| `hardware.FirmwareRecord` (update type, vendor ref, patch link, work order, applied/verified) | **Lifted** as `device.FirmwareHistory` |
| `hardware.DeviceComponent` | **Lifted** as `DeviceModule` assets + `AssetComponent` |
| `hardware.PortService` | Step 6 |
| `compliance.CIPConfigBaseline` | **Corrected** to a view (104) |
| `compliance.CIPPatchRecord`, `supplychain.CVERecord` | **Lifted** into `Advisory` + `AdvisoryDisposition` |
| `supplychain.VendorAgreement`, `SupplyChainAck` | **Lifted** into `party.EntityAgreement`, shape only |
| `protection.DeviceType.MaxSettingGroups`, `VendorSoftware`, `ProjectFileExt` | Already on `ref.Model` (step 4) |

### 5.12 Decisions

**Decided 2026-09-03:** 98 `device.Device` extension sharing the asset entity id; serial as an
alternate key; network, active group and characteristics move out · 99 lifecycle as an
append-only event log; current state derived · 100 `ref.FirmwareVersion` per model linked to
its parse transform and ICD; `device.FirmwareHistory` valid-time; a change fires re-validation
· 101 device position kind as a subtype; placement checks device category · 102 `Advisory`,
`AdvisoryScope`, `AdvisoryDisposition` (bi-temporal) replace CVE and patch records · 103
`KnownDefect` per model and firmware range · 104 the CIP baseline is a view over held facts,
never a stored snapshot · 105 `party.EntityAgreement` as a shape for support and supply-chain
acknowledgements · 106 modules are `DeviceModule` assets with their own device row.

---

## 6. Connections, ports, channels and the network

Vision §4.11 (copper, telecom channels, IEC 61850, the connection abstraction, the network as
the cyber-asset inventory), §4.12, §9.2; decisions 9–11, 14, 15, 18, 47, 57. Decisions here:
107–115.

### 6.1 `connection.Port` — class `ValidTime` (107)

The electrical or communications ports an asset presents. Studs are location nodes (step 3); a
port *terminates at* a stud, which says what function that stud serves.

| Column | Notes |
|---|---|
| base columns | |
| `AssetEntityId` | FK |
| `PortDesignator` | `NVARCHAR(50)` — IA, IB, IN, OUT101, IN201, ETH1, SER2, as the vendor labels it |
| `PortKind` | FK → `ref.PortKind`: `CurrentInput`, `VoltageInput`, `ContactOutput`, `ContactInput`, `TripCoil`, `AuxiliaryContact`, `CtSecondaryCore`, `TerminalCommon`, `Ethernet`, `Serial`, `Fiber`, `Antenna`, `DcSupply` |
| `Direction` | `In`, `Out`, `Bidirectional` |
| `Phase` | `A`, `B`, `C`, `N`, `Ground`, null |
| `ElectricalGroupCode` | `NVARCHAR(40)`, null — paralleled inputs share a group (the predecessor's `AssetPortGroup`) |
| `TerminatesAtStudEntityId` | FK → `location.NodeRegistry` (type `Stud`), null |
| `Notes` | |

### 6.2 `connection.Connection` — class `BiTemporal` (108, 109)

One record for every joining of two things, whatever carries it (vision §4.11 "one model, two
realisations"; decision 57 adds serial and routable).

| Column | Notes |
|---|---|
| base columns | bi-temporal: "what was wired" and "what did the drawings say was wired" both answerable |
| `FromKind`, `FromEntityId` | endpoint: `Stud`, `Port`, `ProtectionFunction` (node), `Dataset` (§6.4), `NetworkPort` |
| `ToKind`, `ToEntityId` | endpoint |
| `Realisation` | FK → `ref.ConnectionRealisation`: `PanelWire`, `CableConductor`, `Goose`, `SampledValues`, `Mms`, `Serial`, `Routable`, `EthernetLink`, `FiberLink`, `SerialLink`, `OverChannel` |
| `CarrierAssetEntityId` | FK → `asset.AssetRegistry`, null — the panel-wire asset, the cable-conductor asset, or the channel asset that carries it (109); its `location.Route` is the connection's path |
| `DesignStatus` | `Designed`, `Installed`, `Verified` |
| `VerifiedByRecordEntityId` | FK → `record`, null — the test sheet or commissioning record that verified it |
| `WorkRequestEntityId` | FK, null |
| `DrawingKey` | `NVARCHAR(100)`, null — the label the drawing uses for this connection when it is neither a wire nor a cable number |
| `Notes` | |

Rules in the procedure: `PanelWire` and `CableConductor` require stud endpoints and a carrier
whose type matches; `Goose` / `SampledValues` require a `Dataset` from-endpoint and a `Port` or
`ProtectionFunction` to-endpoint (§6.4); `EthernetLink` / `FiberLink` / `SerialLink` require
`NetworkPort` endpoints and no carrier; `OverChannel` requires a channel-asset carrier. The trip
circuit of vision §4.12 is a chain of these rows; walking it is a recursive query over shared
endpoints.

The predecessor's `core.AssetConnection` (ports, chain order, cable and wire ids as text,
`PROPOSED` / `COMMITTED`, workflow instance) is **lifted** in intent: chain order becomes the
chain of rows; cable and wire ids become carrier assets; status becomes `DesignStatus`; the
workflow link becomes the work request.

### 6.3 Panel wires and cable conductors as carriers (109)

- A **panel wire** is an asset of type `PanelWire` with alternate key `WireNumber` scoped to the
  panel (decision 18), a `location.Route` of kind `PanelWire` whose only steps are its two studs,
  and characteristics (colour, gauge, ferrule labels) from its template.
- A **cable conductor** is an asset of type `CableConductor`, a component of its cable
  (`asset.AssetComponent`, role = colour or number), with `InUse` / `Spare` / `Shield` as a
  characteristic; the cable's `location.Route` through raceway segments is the conductor's path.

### 6.4 IEC 61850 content — parsed, then promoted (110)

The SCD and CID are configuration-file revisions (step 8). Their content is parsed by the
`Transform.SclParse` definition into these tables, keyed to the **revision** that produced them,
exactly as parsed settings are keyed to their settings-file revision:

| Table — class `ValidTime`, `ConfigurationFileRevisionRowId` on each | Columns |
|---|---|
| `connection.Ied` | `DeviceEntityId` (matched by IED name → alternate key `IedName`), `IedName`, `ConfigVersion`, `Manufacturer`, `IedType` |
| `connection.LogicalDevice` | `IedEntityId`, `Inst`, `LdName` |
| `connection.LogicalNode` | `LogicalDeviceEntityId`, `LnClass`, `LnInst`, `Prefix`, `LnType`; `ProtectionFunctionNodeEntityId` FK → `location.Node` (type `ProtectionFunction`), null — the mapping that gives commissioned function its 61850 vocabulary (vision §4.12) |
| `connection.Dataset` | `LogicalDeviceEntityId`, `DatasetName` |
| `connection.DatasetMember` | `DatasetEntityId`, `LdInst`, `LnClass`, `LnInst`, `DoName`, `DaName`, `Fc` |
| `connection.ControlBlock` | `LogicalDeviceEntityId`, `Kind` (`Goose`, `SampledValues`, `Report`), `CbName`, `AppId`, `ConfRev`, `DatasetEntityId`, `MulticastMac`, `VlanId`, `VlanPriority` |
| `connection.ExtRef` | `IedEntityId` (subscriber), `IntAddr`, `LdInst`, `LnClass`, `LnInst`, `DoName`, `DaName`, publisher `IedName`, `CbName`, `DatasetRef`; `ConnectionEntityId` FK — the promoted row |
| `connection.DataAttribute` | the flat attribute map (the predecessor's 277,743 rows): `LogicalNodeEntityId`, `DoName`, `DaName`, `Fc`, `DataSource` — parsed content only, never referenced by rules |

**Promotion:** on parse, each `ExtRef` row that resolves to a publisher control block becomes
one `connection.Connection` of realisation `Goose` or `SampledValues`, from the publisher's
`Dataset` to the subscriber's `Port` (the ExtRef's internal address) or `ProtectionFunction`. A
re-parse of a new revision closes connections no longer present and opens new ones; it never
deletes. `ControlBlock` rows are the publisher endpoints. Nothing else in the parsed set is a
connection.

The predecessor's `iec61850.*` (fifteen tables, the best-populated part of it) is **lifted**
almost table for table, with the revision key added and the promotion rule made explicit. Its
`GEPublishSourceMap` (relay operand → data object) is a `Transform` definition per model, not a
table (114).

### 6.5 Network — ports, links, services, perimeters (111)

| `connection.NetworkPort` — class `ValidTime`, extension of `Port` for kinds `Ethernet`, `Serial`, `Fiber` | `PortEntityId`, `MacAddress`, `IpAddress`, `SubnetMask`, `Gateway`, `VlanId`, `Speed`, `IsEnabled` |
|---|---|

Physical links are `Connection` rows of realisation `EthernetLink`, `FiberLink` or `SerialLink`
between two `NetworkPort` endpoints. **Routable paths are derived**, not stored: a recursive
walk over links and switch ports yields what can reach what, and the catalogue fact
`device.connections[realisation]` (vision §4.12) reports `Routable` for any device with a path
to a routable network — the fact the CIP applicability derivation needs (vision §4.8).

| `connection.PortService` — class `ValidTime` | `NetworkPortEntityId`, `Protocol`, `LogicalPort` `INT`, `ServiceName`, `Direction`, `BusinessJustification`, `IsInsideSecurityPerimeter` — lifted from the predecessor's `hardware.PortService` |
|---|---|

| `connection.SecurityPerimeter` — class `ValidTime` | `Name`, `Description`, `AccessPointDescription`, `LastReviewedAt`, `NextReviewAt`, `ReviewedByActorId`, `ClassificationDocumentEntityId` — the electronic security perimeter (verify against the current CIP text for its definition); lifted from `comms.ESP` |
|---|---|
| `connection.SecurityPerimeterMember` — class `ValidTime` | `PerimeterEntityId`, `DeviceEntityId`, `Role` (`Inside`, `AccessPoint`) — lifted from `comms.ESPDevice` |

`ref.Vlan` and `ref.MulticastAddress` are reference lists the Administrator maintains.

### 6.6 Channels (112)

A **channel** is an asset of type `Channel` with a `location.Route` of kind `Channel` whose
steps cite the medium assets (fiber pair, multiplexer, radio, repeater, carrier set, line trap)
and the stations passed. A teleprotection connection is a `Connection` of realisation
`OverChannel` with the channel as carrier. Channel **performance** — delay, availability — is
recorded as `record` rows of kind `ChannelMeasurement` (step 10); channel **alarms** are
`event` rows (step 13). The channel asset carries no measurement columns.

### 6.7 Protocol endpoints and point maps (113)

Shape now, built in the SCADA phase:

| `connection.ProtocolEndpoint` — class `ValidTime` | `NetworkPortEntityId`, `Protocol` (`Dnp3`, `Modbus`, `Iec104`, `Iec61850Mms`), `Role` (`Master`, `Outstation`, `Server`, `Client`), `Address` (`NVARCHAR(50)`), `RemoteEndpointEntityId` null, `ConfigDetail` |
|---|---|
| `connection.PointMap` — class `ValidTime` | `ProtocolEndpointEntityId`, `ObjectGroup`, `Variation`, `PointIndex`, `PointName`, `Description`, `AssetEntityId` null, `UnitCode`, `ScaleFactor`, `Offset` |

Lifted from `comms.ProtocolConfig` and `comms.DNP3PointList`.

### 6.8 The cyber-asset inventory (115)

`connection.vCyberAsset` is a generated view: every device with at least one `NetworkPort`,
its firmware in force (step 5), its ports and services, its perimeter membership, its placement
and its classification. Vision §9.2 says this *is* the inventory; no second table exists.
`device.vBaseline` (step 5) is this view narrowed to one device.

### 6.9 Comparison with the predecessor

| Predecessor | Verdict |
|---|---|
| `core.AssetPort` (79; kinds CT_INPUT, CT_SECONDARY_CORE, TRIP_OUTPUT, AUX_CONTACT, TB_STUD …), `AssetPortGroup` (PARALLEL_INPUT) | **Lifted** as `connection.Port` + electrical group; `TB_STUD` is a stud node, not a port |
| `core.AssetConnection` (36; CT_TO_RELAY_PORT, TRIP_RELAY_TO_LOCKOUT; PROPOSED/COMMITTED; chain order; cable/wire text ids) | **Lifted** in intent as `connection.Connection`; carriers replace text ids; chain order replaced by the chain of rows |
| `iec61850.*` fifteen tables | **Lifted** table for table under the configuration-file revision; ExtRef → Connection promotion added |
| `iec61850.SCLFiles` (FILESTREAM), `SCLFileMapping` | Step 8: configuration files are document revisions |
| `iec61850.ConsistencyCheck` | A `record` kind (step 10): the SCD-versus-registry check is a record with findings |
| `iec61850.GEPublishSourceMap` | A `Transform` definition per model |
| `hardware.PortService`, `comms.ESP`, `comms.ESPDevice` | **Lifted** |
| `comms.ProtocolConfig`, `comms.DNP3PointList` | **Lifted** as `ProtocolEndpoint`, `PointMap` |
| `protection.Device.IPAddress`, `SubnetMask`, `Gateway`, `DNP3_Address` | Move to `NetworkPort` and `ProtocolEndpoint` |
| `comms.IEC61850Reference` (installed-on-device flag, consistency verified) | The in-service state of the CID revision (step 8) plus the consistency record |

### 6.10 Decisions

**Decided 2026-09-03:** 107 `connection.Port` on assets, terminating at studs, with electrical
groups · 108 `connection.Connection` bi-temporal with polymorphic endpoints, realisation, design
status and verifying record · 109 one `CarrierAssetEntityId` for panel wire, cable conductor or
channel; the carrier's route is the path · 110 61850 content is parsed per configuration-file
revision; control blocks and ExtRefs are promoted to connections; logical nodes map to
protection-function nodes · 111 `NetworkPort`, links as connections, routable paths derived,
`PortService`, `SecurityPerimeter` and membership · 112 channel is a routed asset; performance
as records, alarms as events · 113 `ProtocolEndpoint` and `PointMap` as shapes · 114 vendor
operand maps are transform definitions · 115 the cyber-asset inventory is a generated view.

---

## 7. Schemes, functions, conditions and operations

Vision §4.12 "The scheme is the anchor", "Operational state", "Protection operation"; §4.3
(designation, capability, commissioned function); §5.3; decisions 33, 34, 47, 49, 52, 55.
Decisions here: 116–123.

### 7.1 `scheme.Scheme` — class `ValidTime` (116)

| Column | Notes |
|---|---|
| base columns | |
| `SchemeTypeDefinitionVersionRowId` | FK → `config.DefinitionVersion` of kind `Program.SchemeType`: line differential, line distance with POTT, bus differential, transformer differential, breaker failure, transfer trip, RAS / SPS, generator, feeder, reclosing … Each names the required member roles, the test-plan items and the rationale scheme-type template (decision 61) |
| `Name` | |
| `SystemDesignation` | `NVARCHAR(10)`: A, B, C, or null |
| `Status` | `Designed`, `Commissioned`, `InService`, `Retired` |
| `Notes` | |

Alternate key `SchemeNumber`. Stations spanned are derived from members' locations, not stored.

| `scheme.SchemeProtects` — class `ValidTime` | `SchemeEntityId`, `PrimaryAssetEntityId` → `asset.AssetRegistry` (a line by route, a transformer, a bus, a generator), `ZoneRole` (`Primary`, `Backup`, `BreakerFailure` — the owner, 2026-09-16: the design's `Overlap` is breaker failure in the group's words) |
|---|---|

### 7.2 `scheme.SchemeMember` — class `BiTemporal` (116)

| Column | Notes |
|---|---|
| base columns | bi-temporal: "what protected the line at 03:47" and "what did we believe protected it" |
| `SchemeEntityId` | FK |
| `MemberKind` | `ProtectionFunction` (a location node), `Asset` (CT, VT, DC system, trip coil, breaker), `Connection`, `Channel` (an asset) |
| `MemberEntityId` | polymorphic; enforced by the procedure |
| `MemberRole` | FK → `ref.SchemeMemberRole`: `EndA`, `EndB`, `InitiatingDevice`, `TrippedBreaker`, `CtSource`, `VtSource`, `DcSource`, `Channel`, `BlockingInput`, `IntertripReceive`, `IntertripSend`, `TripCircuit`, `LockoutRelay`, `AuxiliaryTrip` … extensible |
| `IsInService` | `BIT` — a member temporarily out of service is a protection condition (§7.5); this flag is the designed state |
| `Notes` | |

Members are functions and connections, not devices, so a relay swap leaves the scheme intact
(vision §4.12). The predecessor's `protection.ProtectionSystem` columns — device, DC source,
CT core port, trip coil port, communications path — are each a member row here. The
"protection system" of vision §5.3 is `scheme.vSchemeExpanded`: the scheme with every member
resolved to its current asset, device and connection chain.

### 7.3 Functions — capability and commissioned function (117)

| `ref.AnsiFunction` — class `Reference` | `AnsiCode` PK (21, 21N, 27, 50, 51N, 67, 87, 87L, 87T …), `Name`, `Description`, `Category`, `DefaultLnClass` (the 61850 logical-node class this function normally maps to: PDIS, PTOC, PDIF …), `IsActive` — lifted from the predecessor's 62-row `AnsiCodeRegistry`; its 16-row `FunctionType` is redundant and dropped |
|---|---|

| `scheme.FunctionCapability` — class `ValidTime` | `ModelId` → `ref.Model`, `FirmwareVersionId` null, `AnsiCode`, `Source` (`Template`, `Icd`, `Manual`) — what a relay *can* do (vision §4.3 capability); seeded from the ICD parse or the model template |
|---|---|

| `scheme.CommissionedFunction` — class `ValidTime` | Notes |
|---|---|
| base columns | |
| `ProtectionFunctionNodeEntityId` | FK → `location.Node` (type `ProtectionFunction`) — the position |
| `AnsiCode` | FK → `ref.AnsiFunction` — one row per enabled function at this position; a position may carry several (an SEL-487 is 87L and 50, 51, 51N …) |
| `IsPrincipal` | `BIT` — the one the designation names (vision §4.3) |
| `LogicalNodeEntityId` | FK → `connection.LogicalNode`, null — the 61850 mapping (step 6) |
| `EnabledFromConfigurationFileRevisionRowId` | FK, null — the settings revision that enabled it |

The **designation** (87A) is an alternate key of kind `Designation` on the protection-function
node, scoped to the panel. Three tables for the three things vision §4.3 says must be separate.

### 7.4 Remedial action schemes (119)

A RAS or SPS is a `Scheme` whose scheme type's template carries arm conditions, initiation logic,
the reliability coordinator's scheme id and the reporting cadence as characteristics. Its
ordered actions are:

| `scheme.SchemeAction` — class `ValidTime` | `SchemeEntityId`, `Sequence`, `ActionKind` (`TripBreaker`, `ShedLoad`, `RejectGeneration`, `SwitchReactor`, `Alarm`, `Transfer`), `TargetAssetEntityId` null, `TargetNodeEntityId` null, `LoadMw`, `GenerationMw`, `Mvar`, `MaxExecutionMs`, `Description` |
|---|---|

Armed and disarmed are protection conditions (§7.5); an operation is a protection operation
(§7.6) with the RAS-specific characteristics (load shed, generation rejected, execution time)
from the scheme type's operation template; a submission to the reliability coordinator is a
compliance attestation (step 12); a periodic review is a record (step 10). The predecessor's
seven `protection.RAS*` tables collapse into these.

### 7.5 `scheme.ProtectionCondition` — class `BiTemporal` (120)

Vision §4.12 "Operational state"; the in-service invariant reads "one in-service file plus the
conditions in force".

| Column | Notes |
|---|---|
| base columns | |
| `SubjectKind`, `SubjectEntityId` | `ProtectionFunction` (node), `Scheme`, `Connection`, `Device` |
| `ConditionKind` | FK → `ref.ConditionKind`: `ActiveSettingsGroup`, `TemporarySetting`, `FunctionBlocked`, `TestSwitchOpen`, `OutOfService`, `ConstructionCutover`, `Armed`, `Disarmed`, `AbnormalCondition`, `AlarmInhibit` — extensible |
| `ConditionValue` | `NVARCHAR(200)`, null — the group number, the blocked element, the temporary value |
| `Reason` | |
| `OpenedByActorId`, `ClosedByActorId` | |
| `AuthorisedByActorId` | null — where the condition needs authority (out of service) |
| `RevertObligationInstanceEntityId` | FK → `compliance.ObligationInstance`, null — the obligation to restore, with its derived due |
| `NotificationRecordEntityId` | FK → `record`, null — the operations acknowledgement |
| `WorkRequestEntityId` | FK, null |

The active settings group is a condition of kind `ActiveSettingsGroup` on the device, not a
column anywhere (121); the groups themselves live in the settings-file revision (step 8). The
predecessor's `protection.Device.ActiveSettingGroup`, `RASArmedState`, and the absence of
anything for blocked functions or open test switches are all **corrected** here.

### 7.6 `scheme.ProtectionOperation` — class `BiTemporal` (122)

| Column | Notes |
|---|---|
| base columns | |
| `OccurredAt` | `DATETIMEOFFSET(7)` + `TimeSourceQuality` |
| `PrimaryAssetEntityId` | FK — the faulted or protected asset; the operation is *its* history (vision §4.1) |
| `Outcome` | `Correct`, `Incorrect`, `Unnecessary`, `FailureToOperate`, `SlowClear`, `Undetermined` — decision 52; a correct operation is a fact rules may consume |
| `ElementsOperated` | `NVARCHAR(400)` — as reported |
| `ClearingTimeMs` | `INT`, null |
| `RecloseAttempts`, `RecloseSuccessful` | |
| `DataSource` | `Scada`, `Dfr`, `RelayEventReport`, `Ser`, `FieldReport`, `Manual` |
| `IsConfirmed` | `BIT` |
| `ReviewRecordEntityId` | FK → `record` (kind `OperationReview`), null |
| `ExceptionEntityId` | FK → `compliance.Exception`, null — when the outcome is incorrect and the misoperation family applies (step 12) |
| `Notes` | |

| `scheme.ProtectionOperationScheme` | `OperationEntityId`, `SchemeEntityId`, `Role` (`Operated`, `ShouldHaveOperated`, `Blocked`), `SchemeMemberRowId` null — which member acted |
|---|---|
| `scheme.ProtectionOperationSnapshot` — class `AppendOnly` | `OperationEntityId`, `SubjectKind`, `SubjectRowId` — the **row versions** of every in-service configuration file, condition and scheme membership as-of the event, captured when the operation is raised, so a later correction never changes what was recorded (vision §4.10, scenario 4) |
|---|---|
| `scheme.FaultRecord` — class `ValidTime` | `OperationEntityId`, `FaultType`, `PhasesInvolved`, `FaultedAssetEntityId`, `LocationMethod`, `DistanceKm`, `DistancePercent`, `CurrentKaA/B/C/N`, `ResistanceOhm`, `ReactanceOhm`, `IsFieldConfirmed`, `FieldConfirmedAt`, `PatrolRecordEntityId`, `OscillographyDocumentEntityId`, `ComputedByActorId` — lifted from the predecessor |
|---|---|

Misoperation handling (identification, investigation, corrective action plan, reporting — the
family verified against current text) is: outcome `Incorrect` → `compliance.Exception` with the
derived clock → investigation Work Request → `record` findings → child Work Requests → evidence
links (step 12). The predecessor's `events.Misoperation` and `EventReview` columns map onto
those, not onto a table here.

### 7.7 Comparison with the predecessor

| Predecessor | Verdict |
|---|---|
| `core.ProtectionScheme` (code, name, kind), `ProtectionSchemeMember` (asset, role) | **Lifted** as `Scheme`; members **corrected** to functions and connections |
| `protection.ProtectionSystem` (function, device, DC source, CT core, trip coil, comms path as columns) | **Corrected** into `SchemeMember` rows; `vSchemeExpanded` is what the row tried to be |
| `protection.ProtectionFunction` (type, primary asset, location, voltage, "PRC-005 required" bit) | Function node (step 3) + `CommissionedFunction` + `SchemeProtects`; the required bit is an obligation instance, derived (vision §4.8) |
| `protection.AnsiCodeRegistry` (62), `FunctionType` (16) | **Lifted** as `ref.AnsiFunction`; `FunctionType` dropped |
| `protection.IndependenceRecord` | A `record` kind `IndependenceVerification` (step 10) with two scheme subjects (118) |
| `protection.RAS`, `RASDevice`, `RASArmedState`, `RASAction`, `RASEvent`, `RASCompliance`, `RASReview` | **Collapsed** into scheme type template, `SchemeMember`, condition, `SchemeAction`, operation, attestation, record (119) |
| `protection.SettingGroup` (40) | Groups live in the settings-file revision (step 8); active group is a condition (121) |
| `protection.Device.ActiveSettingGroup` | **Corrected** to a condition |
| `events.ProtectionEvent`, `FaultRecord` | **Lifted** as `ProtectionOperation`, `FaultRecord`; snapshot **added** |
| `events.EventReview`, `Misoperation` | Review → record kind; misoperation → exception + findings + work requests (step 12) |
| `events.SERRecord`, `EventSERRecord` | Event tier (step 13) |

### 7.8 Decisions

**Decided 2026-09-03:** 116 `Scheme` with a scheme-type definition, system designation and
`SchemeProtects`; bi-temporal polymorphic `SchemeMember` with role · 117 `ref.AnsiFunction`,
`FunctionCapability` per model, `CommissionedFunction` per position with principal flag and
logical-node mapping; designation as an alternate key on the node · 118 independence
verification is a record kind between two schemes · 119 RAS / SPS is a scheme type with
`SchemeAction`; armed state, operations, submissions and reviews reuse conditions, operations,
attestations and records · 120 `ProtectionCondition` bi-temporal, polymorphic, with revert
obligation and notification record · 121 no settings-group table; groups are in the settings
revision and the active one is a condition · 122 `ProtectionOperation` bi-temporal with outcome,
scheme roles, an append-only row-version snapshot, and a lifted `FaultRecord` · 123
sequence-of-events records go to the event tier.

---

## 8. Documents, configuration files, rationale, drawings

Vision §4.4 (the round trip, the in-service invariant, approved ≠ in service, the package),
§4.5 (as-designed, as-left, as-found), §4.6 (rationale from two templates), §4.12 "Documents and
drawings"; decisions 43, 53, 55, 60, 61, 110. Decisions here: 124–133.

### 8.1 The document base (124)

| `document.DocumentClass` | a definition of kind `CharacteristicSchema.DocumentClass` (§2.1): the metadata a class carries, its numbering rule, its retention, whether reads are logged (decision 65) |
|---|---|

| `document.Document` — class `ValidTime` | `EntityId`, `DocumentClassDefinitionEntityId`, `Title`, `Description`, `OwnerEntityEntityId` → `party.Entity`, `ClassificationMarking` (`Public`, `Internal`, `BcsiRestricted` …), `Notes`. Alternate keys: `DocumentNumber`, `LegacyReference` |
|---|---|

| `document.Revision` — class `BiTemporal` | Notes |
|---|---|
| base columns | bi-temporal: a revision's status changes are approvals (vision §4.10) |
| `DocumentEntityId` | FK |
| `RevisionLabel` | `NVARCHAR(20)` — A, B, 0, 1, as the class's rule dictates |
| `Status` | `Draft`, `Checked`, `Approved`, `Issued`, `Superseded`, `Withdrawn` |
| `PreparedByActorId`, `PreparedAt` | |
| `CheckedByActorId`, `CheckedAt` | |
| `ApprovedByActorId`, `ApprovedAt` | segregation from `PreparedBy` enforced by rule |
| `IssuedAt`, `EffectiveFrom`, `EffectiveTo` | |
| `ChangeNote` | |
| `SupersedesRevisionRowId` | FK, null |

| `document.File` — class `ValidTime` | Notes |
|---|---|
| base columns | |
| `RevisionRowId` | FK — a revision may have several files (the Word source and its PDF, vision §7.8) |
| `FileName`, `MimeType`, `SizeBytes` | |
| `Sha256` | `BINARY(32)` — integrity; evidence packages cite it |
| `FileStreamId` | `UNIQUEIDENTIFIER` → the FILESTREAM file table `document.FileStore` (125) |
| `FileRole` | `Source`, `Rendered`, `Native`, `Attachment` |
| `RedactionStatus` | `None`, `Redacted`, `RedactionPending` |
| `IsCapturedFromDevice` | `BIT` — readbacks (decision 55) |

**Storage (125).** `document.FileStore` is a FILESTREAM file table, as the predecessor used;
the hash is the integrity check, and `File.Sha256` is compared on every read. Large operational
files — COMTRADE, oscillography, synchrophasor archives — live in the archive tier's store
(step 13), referenced by the same `File` row with a different `FileStreamId` target.

### 8.2 `document.RevisionLink` — class `ValidTime` (126)

One polymorphic, kind-labelled join from a revision to anything.

| Column | Notes |
|---|---|
| `RevisionRowId` | FK |
| `LinkKind` | `About` (the subject the document describes), `Depicts` (a drawing shows it), `PerformedTo` (work done per this procedure), `ValidAgainst` (settings valid against this study), `Cites` (rationale cites this), `EvidenceFor` (an obligation instance) |
| `SubjectKind`, `SubjectEntityId` | node, asset, scheme, connection, record, obligation instance, another revision |
| `DrawingKey` | `NVARCHAR(100)`, null — for `Depicts`: the label on the sheet (slot, designation, cable number, panel + wire number — decision 53) |

### 8.3 `document.ConfigurationFile` — revision subclass (127)

One row per revision of a document whose class is a configuration file; shares `RevisionRowId`.

| Column | Notes |
|---|---|
| `RevisionRowId` | PK, FK |
| `DeviceEntityId` | FK — null only for an SCD, which is about a station (`RevisionLink` `About` → station node) |
| `FileKind` | `NativeSettings`, `Cid`, `Scd`, `Icd`, `Iid`, `Ssd`, `DfrConfig`, `PmuConfig`, `VendorProject` |
| `ModelId`, `FirmwareVersionId` | FK — what the file is for; the parse transform is resolved from these (§2.3) |
| `CaptureKind` | `Designed` (authored in the platform), `Generated` (emitted by the transform), `AsLeftReadback` (read from the relay after application), `AsFound` (read from the relay at a visit) — vision §4.5 |
| `InServiceFrom`, `InServiceTo` | `DATETIMEOFFSET(7)` — **the fact**, from readback; distinct from the revision's `Status = Approved` (decision 55); `InServiceFromQuality` as §0.3 |
| `IsInServiceUnapproved` | computed: in service while the revision is not approved — the transient discrepancy state, which raises a finding |
| `DifferentialRecordEntityId` | FK → `record`, null — the as-left-versus-as-designed differential (vision §4.5) |
| `ParseStatus`, `ParseError` | |
| `SettingsGroupCount` | `TINYINT`, null |

**The in-service invariant** (vision §4.4) is a filtered unique index: one `NativeSettings` row
per `DeviceEntityId` with `InServiceTo IS NULL`. Opening a new in-service period closes the
prior one in the same procedure. The active settings group is a condition (decision 121), not a
column here.

### 8.4 `document.SettingsIssuePackage` — revision subclass (128)

A revision whose class is *settings issue package*, grouping configuration-file revisions:

| `document.SettingsIssuePackageItem` | `PackageRevisionRowId`, `ConfigurationFileRevisionRowId`, `Sequence` |
|---|---|

Approval of the package revision cascades: the procedure that approves the package approves
each item's revision in the same transaction, recording the package as the authority
(decision 60). An item may not be approved separately while it belongs to an open package.

### 8.5 Setting definitions and parsed settings (129)

| `config.SettingDefinition` — class `Versioned` | Notes |
|---|---|
| `DefinitionVersionRowId` | FK — the `Transform.SettingsParse` version for a model × firmware |
| `SettingCode` | as the vendor names it (`Z0RTANG`, `50P1P`) — unique within the version |
| `Name`, `Category`, `Description` | |
| `DataType` | as §2.4 |
| `UnitCode`, `Base` | |
| `MinValue`, `MaxValue`, `DefaultValue` | `DECIMAL(28,10)` / text |
| `EnumerationDefinitionRowId` | null |
| `IsGroupSpecific` | `BIT` — per settings group or global |
| `AnsiCode` | FK → `ref.AnsiFunction`, null — which function the setting belongs to |
| `IsCatalogueFact` | `BIT` — publishes `device.settings.<code>` to the fact catalogue |

The predecessor's 996 `SettingDefinition` rows (per device type and firmware, auto-created from
parsed files) seed this, one transform version per model × firmware.

| `document.ParsedSetting` — class `ValidTime` | `ConfigurationFileRevisionRowId`, `SettingDefinitionRowId`, `GroupNumber` (null for global), typed value columns as §2.4, `RangeCheck` (`Ok`, `OutOfRange`, `NotChecked`), `RangeCheckNote` |
|---|---|

Parsed settings are the working representation (vision §4.4); the file is the record. A
differential is a `record` computed over two revisions' parsed settings.

### 8.6 Standard settings and philosophy (130)

A definition kind `CharacteristicSchema.StandardSettings`, applied to a protection application
× model: rows of `(SettingCode, ExpectedValue, Tolerance, Basis)`. Comparing a parsed revision
against the resolved standard produces a `record` of kind `SettingsVerification` with per-setting
deviations. The predecessor's `SettingTemplate` / `SettingTemplateEntry` (36 templates, 6
entries) is this, versioned and approved.

### 8.7 `document.Study` — revision subclass (131)

Lifted from the predecessor's `protection.SettingBasis`, which was a study record under another
name; closes scenario 1's gap G1.

| Column | Notes |
|---|---|
| `RevisionRowId` | PK, FK |
| `StudyKind` | `Coordination`, `FaultLevel`, `Stability`, `ArcFlash`, `LineConstants`, `LoadFlow`, `Other` |
| `Software`, `SoftwareVersion` | ASPEN OneLiner, the platform's own module (vision §11.5) |
| `SystemModelAt` | `DATETIMEOFFSET(7)` — the network-model date the study used |
| `NetworkModelCaseEntityId` | FK → `network` (step 13), null |
| `FaultLevelAssumptions`, `TopologyReference` | |
| `StandardVersionRowIds` | via `RevisionLink` `Cites` |
| `PerformedByActorId`, `ApprovedByActorId` | on the revision |
| `ValidWhile` | `NVARCHAR(400)` — the stated conditions under which its results hold |
| `IsStale` | computed by rule: a network-model change after `SystemModelAt` on any asset in scope |

Settings revisions link `ValidAgainst` a study; rationale `Cites` it. A stale study is the
catalogue fact `study.is_stale` that a settings-review obligation scopes on.

### 8.8 `document.Rationale` — revision subclass (132)

Vision §4.6, decision 61. A rationale revision's content is `document.CharacteristicValue` rows
governed by the two composed templates: the `CharacteristicSchema.RationaleSchemeType` resolved
from the scheme's type, and the `CharacteristicSchema.RationaleDevice` overlay resolved from the
device's model (§2.3 overlays). It links `About` the configuration-file revision it justifies
and `Cites` the study, the philosophy definition version and the standard version. Word export
is a `Transform.WordOutput` per class. The 171 legacy `.doc` rationale files migrate as
`Document` + `Revision` + `File` attached `About` the relay's device position, unparsed, until
templates exist (vision §10.7).

### 8.9 `document.Drawing` — revision subclass (133)

| Column | Notes |
|---|---|
| `RevisionRowId` | PK, FK |
| `SheetNumber`, `SheetCount` | |
| `TitleLine1`, `TitleLine2`, `AssetTitle` | lifted title-block fields |
| `JobNumber`, `WbsNumber` | |
| `DrawnByActorId`, `CheckedByActorId`, `DesignedByActorId` | |
| `DrawingStatus` | FK → `ref.DrawingStatus` — the predecessor's six states, lifted |
| `Orientation`, `PaperSize`, `Scale` | |
| `DrawingKind` | `Schematic`, `Wiring`, `Logic`, `SingleLine`, `Layout`, `Cable`, `Other` |

Alternate key `DrawingNumber` on the document; the revision label is the drawing revision.
What a sheet depicts is `RevisionLink` rows of kind `Depicts` with `DrawingKey` (§8.2).
**Drawing reconciliation** — as-drawn versus corrected, disposition, work request — is a
`record` of kind `Finding` against the sheet (step 10), not a table; the predecessor's
`core.DrawingReconciliationFlag` fields become that finding's characteristics. The logic-diagram
editor's working model (the predecessor's `LogicDraft`, `LogicLink`, `NodeLayout`, shapes,
waypoints) is stored as the editor's serialised file on the drawing revision, not as relational
tables.

### 8.10 Legacy change requests

The predecessor's 61 `protection.ChangeRequest` rows (number, title, calculated, installed and
effective dates, legacy ids) migrate as Work Requests of type *settings change* (step 9), each
with its configuration-file revisions linked and the legacy number as an alternate key.

### 8.11 Comparison with the predecessor

| Predecessor | Verdict |
|---|---|
| `protection.Configuration` (per device: status, active group, vendor file ref/hash, sheet ref) | **Corrected** into `ConfigurationFile` revisions; status becomes revision status + in-service fact; active group → condition |
| `protection.ConfigurationFile`, `VendorProjectFiles`, `SettingsFileMapping`, `iec61850.SCLFiles` (FILESTREAM) | **Lifted** as `document.File` + `FileStore` |
| `protection.ParsedSettings`, `ParsedSettingsFileHistory` | **Corrected**: history is the revision chain; parsed values are `ParsedSetting` per revision |
| `protection.SettingDefinition` (996) | **Lifted** into `config.SettingDefinition` under the transform version |
| `protection.SettingValue` (0) | `document.ParsedSetting` |
| `protection.SettingTemplate` / `Entry` | **Lifted** as the `StandardSettings` definition kind |
| `protection.SettingBasis` | **Lifted** as `document.Study` |
| `protection.Attachment` (171 rationale .doc), `AttachmentFiles`, `AttachmentHistory` | **Lifted** as documents `About` the device position; content migrates unparsed |
| `protection.ChangeRequest` (61) | Work Requests (step 9) |
| `protection.LogicPage` title block, `LogicPageRevision`, `DrawingStatus` | **Lifted** as `Drawing` + `Revision` + `ref.DrawingStatus` |
| `protection.LogicDraft*`, `LogicLink`, `NodeLayout`, `LogicPageShape`, `LogicEdgeWaypoint`, `OperandLabelOverride`, `UserDrawingDefaults` | Editor state → a serialised file on the revision; user defaults → application settings |
| `core.DrawingReconciliationFlag` | A `Finding` record against the sheet |
| `core.AssetReconciliationEvent` | An `audit.ActionLog` kind (merge / split of assets) |

### 8.12 Decisions

**Decided 2026-09-03:** 124 document base: class as definition, document, bi-temporal revision
with four dated actors, file with hash and marking · 125 FILESTREAM file table for held files;
archive tier for operational bulk · 126 one polymorphic `RevisionLink` with six kinds and a
drawing key · 127 `ConfigurationFile` revision subclass with capture kind and an in-service fact
distinct from approval; the invariant is a filtered unique index · 128 settings-issue package
with cascading approval · 129 `config.SettingDefinition` under the transform version;
`ParsedSetting` per revision · 130 standard settings as a definition kind; comparison yields a
record · 131 `document.Study` lifted from the predecessor's setting basis · 132 `Rationale`
from two composed templates; legacy Word files migrate unparsed · 133 `Drawing` with lifted
title block; reconciliation as a finding; editor state as a file.

---

## 9. Work Requests, workflow, Cascade, notifications

Vision §4.7 (Work Requests, one hierarchy), §4.12 "nothing above is code", §5.7 (the platform
drives, Cascade executes), §11.2; decisions 36, 45, 78. Decisions here: 134–142.

**Verified with the owner 2026-09-03.** Every kind of work — set a relay, test a relay, install a
relay, commission a terminal, investigate a misoperation — is a *work type* the Administrator
defines, and every work type names its own *workflow definition*: the states, the transitions,
who may advance each, what must exist before a transition is allowed, and what notifications
fire. Both are versioned, approved definitions (§2). A request records the versions it runs
under, so in-flight work finishes on the workflow it started with. Adding a state, a signature or
a step is a new definition version with an effective date, never a release. What is fixed in code
is the interpreter and the definition grammar (vision §7.7).

### 9.1 `work.WorkRequest` — class `ValidTime` (134)

| Column | Notes |
|---|---|
| base columns | |
| `ParentWorkRequestEntityId` | FK, null — nesting (vision §4.7) |
| `WorkTypeDefinitionVersionRowId` | FK → `config.DefinitionVersion` of kind `Program.WorkType` (135) |
| `Title`, `Description`, `SpecialInstructions` | |
| `Priority` | FK → `ref.Priority` |
| `ScopeKind`, `ScopeEntityId` | polymorphic: node, asset, scheme, connection, channel asset, obligation instance, protection operation |
| `PlannedStartAt`, `PlannedEndAt`, `ActualStartAt`, `ActualEndAt` | |
| `EstimatedHours` | `DECIMAL(8,2)`, null |
| `OutageRequired` | `BIT`; `OutageWindowStartAt`, `OutageWindowEndAt`, `OutageApprovalReference` — columns now, an outage entity later if coordination becomes a feature (139) |
| `RaisedByObligationInstanceEntityId` | FK, null — when derivation raised it (vision §4.12) |
| `RaisedByRecordEntityId` | FK, null — when a finding raised it |
| `Notes` | |

Alternate keys: `WorkRequestNumber` (platform-assigned), `LegacyChangeRequestNumber` (the
predecessor's 61 change requests, step 8). **Not stored:** status (it is the workflow instance's
state), assignee (a grant, step 11), due (derived from the obligation). The predecessor's
`ComplianceDeadline` and `PRC005DrivenBy` columns are the stale-register pattern the vision
removes (§5.2).

### 9.2 Work type — a definition (135)

`Program.WorkType` payload names: the `Program.Workflow` definition to run; the record kinds a
request of this type must produce before it may close; the default test plan; the qualification
requirement for assignment; the Cascade work-order type to raise, if any; whether an outage is
normally required. Seeded from the vision's scenarios: `SettingsChange`, `RelayTest`,
`RelayInstall`, `RelayRemove`, `Commissioning`, `MaintenanceVerification`,
`MisoperationInvestigation`, `CorrectiveAction`, `DrawingReconciliation`, `LegacyImport`.

### 9.3 Workflow runtime (136)

The definition is text (decision 78); the runtime is two tables.

| `work.WorkflowInstance` — class `ValidTime` | Notes |
|---|---|
| base columns | |
| `WorkflowDefinitionVersionRowId` | FK — the version this instance runs under, for its whole life |
| `SubjectKind`, `SubjectEntityId` | `WorkRequest`, `ConfigurationFileRevision`, `DocumentRevision`, `ObligationInstance`, `ProtectionCondition`, `DefinitionVersion` (approval of a definition is itself a workflow) |
| `CurrentState` | `NVARCHAR(60)` — a state name from the definition |
| `StartedAt`, `StartedByActorId`, `CompletedAt` | |
| `IsCancelled` | |

| `work.WorkflowTransition` — class `AppendOnly` | `TransitionId`, `WorkflowInstanceEntityId`, `OccurredAt`, `FromState`, `ToState`, `TransitionName`, `ActorId`, `Reason`, `Detail` (JSON: the guard results, the records cited), `ActionLogId` → `audit.ActionLog` |
|---|---|

The interpreter evaluates a transition's guards against the fact catalogue and the subject's
records, refuses with a named reason, and on success writes the transition and the action log in
one transaction. The predecessor's `WorkflowInstance` and `WorkflowTransitionLog` (202 and 227
rows) are **lifted**; its `WorkflowTemplate`, `WorkflowStage`, `WorkflowStageRole`,
`WorkflowTransition` structure tables are **replaced** by the definition text, and their six
templates (`SETTINGS_APPROVAL`, `CHANGE_REQUEST`, `IEC61850_CONFIG`, `WIRING_RECON`,
`WORK_ORDER_FLOW`, `LEGACY_IMPORT`) become the first six workflow definitions, migrated stage
for stage.

### 9.4 `work.CascadeWorkOrder` — class `ValidTime` (137)

| Column | Notes |
|---|---|
| base columns | |
| `CascadeNumber` | alternate key |
| `CascadeStatus` | as last synchronised |
| `MappedNodeEntityId` | FK → `location.Node` — the nearest Cascade-known ancestor of the request's scope (decision 36) |
| `CascadeWorkOrderType` | |
| `LastSyncedAt`, `SyncDirection` | `ToCascade`, `FromCascade`, `Manual` — completion direction is the open change-order question (vision §11.2) |
| `Notes` | |

| `work.WorkRequestCascadeLink` | `WorkRequestEntityId`, `CascadeWorkOrderEntityId`, `LinkKind` (`RaisedFor`, `ExecutedUnder`) — a link table because the cardinality is not yet decided; either direction of many is representable |
|---|---|

### 9.5 Tasks are records (138)

The predecessor's `WorkOrderTask` (sequence, device, category, expected result, measured value,
completed by) is the shape of a test-plan step and its test-sheet result; both are in step 10.
The work schema has no task table.

### 9.6 Notifications (140)

| `Program.NotificationType` definition | trigger (time-based, assignment, state change), completion mode (auto-resolve, manual sign-off), mandatory flag, priority, message templates, escalation chain (steps, delays, escalate-to role) — the predecessor's `NotificationType`, `TriggerDefinition`, `EscalationChain`, `EscalationStep` collapsed into one definition |
|---|---|

| `work.Notification` — class `ValidTime` | `NotificationTypeDefinitionVersionRowId`, `RecipientActorId` null, `RecipientRoleId` null, `SubjectKind`, `SubjectEntityId`, `Status` (`Open`, `Acknowledged`, `Resolved`, `Escalated`, `Expired`), `CurrentEscalationStep`, `Summary`, `Detail`, `ResolvedAt`, `ResolvedByActorId`, `ResolutionRecordEntityId` (the acknowledgement record, where one is required — step 10) |
|---|---|
| `work.Subscription` — class `ValidTime` | `PersonEntityId`, `NotificationTypeDefinitionEntityId`, `ScopeFilter` (a catalogue predicate: station, device class, scheme type) |
|---|---|
| `work.NotificationDelivery` — class `AppendOnly` | `NotificationEntityId`, `Channel` (`InApp`, `Email`), `SentAt`, `DeliveryStatus` — the predecessor's `DeliveryLog` |
|---|---|

The predecessor's `notify.*` (26 tables, half of them `…Registry`) collapses to these four plus
the definition. Its `Dashboard*` and `DataSource*` tables are reporting configuration
(vision §2.3 report definitions), not notifications.

### 9.7 Assignment (141)

Assigning a person to a request is a grant of an assignment role against the request
(vision §3.2), in `security.Grant` with `ScopeKind = WorkRequest` (step 11), gated by the work
type's qualification requirement. No assignee column on the request.

### 9.8 Maintenance policies become rules (142)

The predecessor's `workplan.MaintenancePolicy` (13 rows: category, BES or not, fixed interval in
days, standard family and category) is the maintained register vision §5.2 replaces. Each row
becomes a `Program.ObligationRule` definition (step 12) whose scoping predicate reads
`asset.class`, `station.classification`, `device.technology` and whose cadence is the interval;
"due" is then derived. Its `MaintenanceEvidence` / `PRC005Evidence` become records with
evidence links.

### 9.9 Comparison with the predecessor

| Predecessor | Verdict |
|---|---|
| `workplan.WorkOrder` (outage fields, priority, compliance deadline, assigned-to) | **Lifted** as `WorkRequest`; deadline and assignee **removed** (derived; a grant) |
| `workplan.WorkOrderTask` | Test plan step + test sheet result (step 10) |
| `workplan.WorkOrderDevice` | The request's scope, or child requests |
| `workplan.WorkOrderApproval` | `WorkflowTransition` |
| `workplan.MaintenancePolicy`, `PRC005Category` | Obligation rules (step 12) |
| `workplan.MaintenanceEvidence`, `PRC005Evidence` | Records + evidence links (steps 10, 12) |
| `workflow.WorkflowTemplate` / `Stage` / `StageRole` / `Transition` (+ registries) | **Replaced** by `Program.Workflow` definitions; six templates migrated as the first definitions |
| `workflow.WorkflowInstance`, `WorkflowTransitionLog` | **Lifted** |
| `workflow.WorkflowNotificationRule` | Part of the workflow definition |
| `notify.NotificationType`, `TriggerDefinition`, `EscalationChain`, `EscalationStep` | **Collapsed** into the `Program.NotificationType` definition |
| `notify.Notification`, `Subscription`, `DeliveryLog`, `ResponsibilityAssignment` | **Lifted** as `Notification`, `Subscription`, `NotificationDelivery`; responsibility is a positional-role grant (step 11) |
| `notify.Dashboard*`, `DataSource*`, `TriggerState`, `EngineConfig` | Report definitions and application configuration, not schema entities |
| `protection.ChangeRequest` (61) | `WorkRequest` of type `SettingsChange` with the legacy number as alternate key |

### 9.10 Decisions

**Decided 2026-09-03:** 134 `WorkRequest` valid-time with nesting, work-type version,
polymorphic scope, outage columns; status, assignee and due are not stored · 135 work type is
a definition naming workflow, required records, test plan, qualification and Cascade type · 136
workflow runtime is `WorkflowInstance` + append-only `WorkflowTransition`; structure lives in the
definition text; the predecessor's six templates migrate as definitions · 137
`CascadeWorkOrder` with a link table, cardinality open · 138 tasks are test-plan steps and
results · 139 outage as columns for now · 140 notification type as a definition;
`Notification`, `Subscription`, `NotificationDelivery` · 141 assignment is a grant · 142
maintenance policies become obligation rules.

---

## 10. Records, test plans, sheets, results, instruments

Vision §4.12 "The evidence chain" and "Records, plans and instruments"; §5.6; decisions 36, 37,
42, 47, 55, 62. Decisions here: 143–151. The record is the middle of the evidence chain:
produced by work, cited by evidence links, never a bare file.

### 10.1 `record.Record` — class `ValidTime` (143)

| Column | Notes |
|---|---|
| base columns | |
| `RecordKind` | FK → `ref.RecordKind`: `TestSheet`, `Readback`, `CommissioningPackage`, `Finding`, `Attestation`, `NotificationAcknowledgement`, `SettingsVerification`, `IndependenceVerification`, `OperationReview`, `ChannelMeasurement`, `Calibration`, `ParityTest`, `ConsistencyCheck`, `OnTheJobTraining`, `ConditionObservation` — extensible; each kind may name a characteristic template |
| `SubjectKind`, `SubjectEntityId` | polymorphic: node, asset, device, scheme, connection, channel, configuration-file revision, drawing revision, instrument, person, another record |
| `SecondSubjectKind`, `SecondSubjectEntityId` | null — for kinds relating two things (independence verification between two schemes) |
| `WorkRequestEntityId` | FK, null — the producing work |
| `OccurredAt` | `DATETIMEOFFSET(7)` + `TimeSourceQuality` |
| `PerformedByActorId`, `WitnessedByActorId` | |
| `OverallResult` | `Pass`, `Fail`, `Conditional`, `Informational`, null |
| `Summary` | `NVARCHAR(1000)` |
| `TemplateDefinitionVersionRowId` | FK, null — the characteristic schema governing this record's `record.CharacteristicValue` rows (§2.4) |

| `record.Acceptance` — class `BiTemporal` (decision 42) | `RecordEntityId`, `AcceptedByActorId`, `AcceptedAt`, `AcceptanceStatus` (`Accepted`, `Rejected`, `Withdrawn`), `Reason`, `SupersededByRecordEntityId` null — acceptance is an approval and is bi-temporal; the readings on the record stay valid-time |
|---|---|

Files attached to a record (a scanned sheet, a photograph, an oscillograph) are documents
linked `About` the record (step 8). Evidence links (step 12) cite `Record.RowId`.

### 10.2 Test plans — a definition with steps (144)

`Program.TestPlan` definitions are the procedures; the Relaying Field Notes migrate first as
documents and are re-authored as these (decision 40).

| `config.TestPlanStep` — class `Versioned` | Notes |
|---|---|
| `DefinitionVersionRowId` | FK — the plan version |
| `Sequence` | |
| `Description`, `Instruction` | |
| `SubjectKind` | `Function`, `Component`, `Connection`, `Device`, `Scheme` — what the step is performed on |
| `SubjectSelector` | `NVARCHAR(200)` — how the step's subject is found within the plan's subject: "CT source member", "ANSI 21 element", "trip circuit connection chain" |
| `ExpectedResult` | text, or a limit expression in the formula language |
| `IsRequired` | |
| `ServesObligationRuleDefinitionEntityId` | FK, null — which rule's evidence definition this step satisfies |

| `config.TestPlanReading` — class `Versioned` | `TestPlanStepRowId`, `ReadingKey`, `Name`, `DataType`, `UnitCode`, `Base`, `LowerLimit`, `UpperLimit`, `LimitExpression` (formula), `IsRequired` |
|---|---|

### 10.3 `record.TestSheet` and `record.TestResult` (145)

| `record.TestSheet` — record subclass, shares `RecordEntityId` | `TestPlanDefinitionVersionRowId`, `InstrumentRowId` → `record.Instrument.RowId` (the instrument *as it was*, so its calibration state is fixed), `AmbientConditions` null, `IsPartial` computed |
|---|---|

| `record.TestResult` — class `ValidTime` | Notes |
|---|---|
| base columns | |
| `TestSheetEntityId` | FK |
| `TestPlanStepRowId` | FK |
| `StepSubjectKind`, `StepSubjectEntityId` | the resolved subject: this CT, this ANSI-21 commissioned function, this connection chain |
| `Status` | `Performed`, `NotPerformed`, `NotApplicable` — with `NotPerformedReason` (gap G7) |
| `Outcome` | `Pass`, `Fail`, `Marginal`, null |
| `Notes` | |

| `record.TestReading` — class `ValidTime` | `TestResultEntityId`, `TestPlanReadingRowId`, `Phase` (`AsFound`, `AsLeft`, `Single`), typed value columns as §2.4, `UnitOverride`, `IsWithinLimits` |
|---|---|

The predecessor's `WorkOrderTask` (expected result, measured value, unit, result, failure notes)
is exactly one `TestResult` with one `TestReading`; its `MaintenanceEvidence` /
`PRC005Evidence` (overall result, condition notes, follow-up, next due) is a `TestSheet` record
whose "next due" is derived, not stored.

### 10.4 Doble RTS import (146)

Each RTS test becomes a `TestSheet` whose plan is a migration-generated `Program.TestPlan`
definition per RTS test template (one per relay type and test routine encountered), results
mapped step by step by a `Transform.Import` definition, every row carrying `MigrationRunId` and
`migration.Provenance`. Instruments named in RTS records become `record.Instrument` rows. The
history from approximately 2001 (decision 62) is therefore queryable as records, and the
generated plans are the seed the group refines into its own definitions.

### 10.5 `record.Instrument` — asset extension (147)

Test sets and reference meters are assets of a device type `TestInstrument` with a
`record.Instrument` extension sharing the entity id: `InstrumentKind`, `Range`, `Accuracy`,
`CalibrationIntervalDays` (a characteristic, so it is data). They live at a custody location of
kind `Calibration` or `Store`. A **calibration** is a `Record` of kind `Calibration` against the
instrument, with certificate document, calibrated-by (a `party.Entity`), and next-due derived
by rule. A test sheet cites the instrument's `RowId`, so the calibration state at the time of
the test is what the sheet saw.

### 10.6 `record.Finding` — record subclass (148)

| Column | Notes |
|---|---|
| `RecordEntityId` | PK, FK |
| `FindingCategory` | FK → `ref.FindingCategory`: `AsFoundDrift`, `OutOfTolerance`, `DrawingDiscrepancy`, `WiringDiscrepancy`, `SettingsDiscrepancy`, `ConsistencyMismatch`, `AuditFinding`, `Observation` … |
| `Severity` | `Critical`, `Major`, `Minor`, `Observation` |
| `Description` | |
| `AsFoundValue`, `ExpectedValue` | `NVARCHAR(400)`, null — the predecessor's `AsDrawn` / `Corrected` |
| `Disposition` | `Open`, `CorrectiveActionRaised`, `Accepted`, `Closed`, `Rejected` |
| `CorrectiveWorkRequestEntityId` | FK, null |
| `ClosedByActorId`, `ClosedAt` | |

Drawing reconciliation (step 8), as-found drift (decision 55), a DC cell out of tolerance
(scenario 2), an SCD mismatch (§10.9) and an audit finding (step 12) are all rows here.

### 10.7 `record.CommissioningPackage` — record subclass (149)

A record of kind `CommissioningPackage` whose subject is a scheme, a terminal or a device
position, grouping its members: `record.CommissioningPackageItem` (`PackageEntityId`,
`MemberRecordEntityId`, `Sequence`, `IsRequired`). Acceptance of the package is the
commissioning sign-off, and cascades acceptance to members not already accepted. The scheme
type's definition names the record kinds a package of that type must contain.

### 10.8 `record.Readback` — record subclass (150)

`RecordEntityId`, `ProducedConfigurationFileRevisionRowId` (the as-found file, step 8),
`ComparedToConfigurationFileRevisionRowId` (the in-service file), `ComparisonResult`
(`Identical`, `Differs`, `NotComparable`), `DifferenceCount`, `DifferenceDetailRecordEntityId`
(a settings-verification record listing the differing settings). A `Differs` result raises a
`Finding` of category `AsFoundDrift` in the same procedure (decision 55).

### 10.9 `record.ConsistencyCheck` — record subclass (151)

The SCD-versus-registry check the predecessor ran: `ScdConfigurationFileRevisionRowId`,
`IedsInScl`, `IedsInRegistry`, `Matched`, `UnmatchedScl`, `UnmatchedRegistry`, with one
`Finding` of category `ConsistencyMismatch` per unmatched IED.

### 10.10 Comparison with the predecessor

| Predecessor | Verdict |
|---|---|
| `workplan.WorkOrderTask` | One `TestResult` + `TestReading` |
| `workplan.MaintenanceEvidence`, `PRC005Evidence` | `TestSheet` record; next-due derived |
| `training.OJTRecord` | Record kind `OnTheJobTraining` (step 11 references it) |
| `iec61850.ConsistencyCheck` | `record.ConsistencyCheck` + findings |
| `core.DrawingReconciliationFlag` | `record.Finding` category `DrawingDiscrepancy` |
| `compliance.CIPVulnAssessment` | A record kind (`VulnerabilityAssessment`) with findings — added to `ref.RecordKind` at step 12 |
| No test plan, sheet, instrument, calibration or readback tables | **Added** |

### 10.11 Decisions

**Decided 2026-09-03:** 143 `record.Record` valid-time with kind, polymorphic subject,
producing request, actors and result; `Acceptance` bi-temporal and separate · 144 test plan as a
definition with versioned steps and readings · 145 `TestSheet` citing plan version and
instrument row; `TestResult` with performed / not performed / not applicable; `TestReading`
with as-found and as-left · 146 Doble RTS history imported as test sheets under generated plans
with provenance · 147 instruments as assets with an extension; calibration as a record; sheets
cite the instrument row version · 148 `Finding` subclass with category, severity, disposition
and corrective request · 149 commissioning package as a grouping record whose acceptance
cascades · 150 readback as a record citing produced and compared revisions, raising a finding on
difference · 151 consistency check as a record with findings.

---

## 11. Personnel, actors, security, qualifications, authorisations

Vision §3.2–§3.6, §4.12 "People", §9.3–§9.5; decisions 37–41, 44, 56, 59, 65, 72. Decisions
here: 152–160.

### 11.1 Person, user, actor (152)

| `personnel.Person` — class `ValidTime` | `EntityId`, `FirstName`, `LastName`, `DisplayName`, `EmployeeNumber` (alternate key), `BadgeNumber` (alternate key), `EmployerEntityEntityId` → `party.Entity` (NB Power, a contractor), `Email`, `Phone`, `IsSystemAccount`, `Notes` |
|---|---|

| `security.User` — class `ValidTime` | `EntityId`, `PersonEntityId` FK, `ActiveDirectorySid` (alternate key), `UserPrincipalName`, `IsEnabled`, `DisabledAt`, `DisabledReason`. Nothing else: AD asserts identity and nothing more (vision §3.6, §9.3). No password, no session — the predecessor's `core.PersonCredential` and `LoginSession` are **dropped** (160) |
|---|---|

| `personnel.Actor` — **immutable**, class `AppendOnly` | Notes |
|---|---|
| `ActorId` PK | the value every `CreatedBy` / `ModifiedBy` holds (§0.3) |
| `PersonEntityId` | FK — who the act is attributed to |
| `ActingUserEntityId` | FK → `security.User`, null — the authenticated identity that performed it (null for `System`) |
| `ActorKind` | `Self` (person = user's person), `Delegated` (acting under a delegation), `Sponsored` (a non-user person, entered by the acting user), `System` (a scheduled process, a migration run) |
| `DelegationEntityId` | FK → `security.Delegation`, null |
| `CreatedAt` | |

The write procedure resolves the actor for the session from the user, any delegation in force,
and any sponsorship declared for the call, and reuses the existing row for that combination.
Held-versus-exercised (vision §3.5) is therefore on every table without a second column.

### 11.2 Position and group (153)

| `personnel.Position` — class `ValidTime` | `EntityId`, `EntityEntityId` → `party.Entity` (the division), `Title`, `ReportsToPositionEntityId` null, `IsActive` |
|---|---|
| `personnel.PositionHolder` — class `ValidTime` | `PositionEntityId`, `PersonEntityId`, `IsActing` |
| `security.Group` — class `ValidTime` | `EntityId`, `Name`, `Description` — defined in the platform, not in AD (vision §3.6) |
| `security.GroupMember` — class `ValidTime` | `GroupEntityId`, `UserEntityId` |

### 11.3 Roles and permissions (154)

| `security.Role` — class `Reference` | `RoleCode` PK, `Name`, `RoleKind` (`Positional`, `Assignment`), `Description`, `IsActive`. Seeded from vision §3.2 — Administrator, Manager / P&C Supervisor, Read-only, Compliance Officer, Transmission P&C Engineer, Distribution P&C Engineer, Hydro Generation Engineer, Belledune Generation Engineer, Coleson Generation Engineer, P&C Technician, Approver — plus the predecessor's System Operator, Telecom Engineer, Telecom Technician, Asset Health, Management Viewer, Reviewer |
|---|---|
| `security.Permission` — class `Reference` | `PermissionCode` PK in the form `<SubjectClass>.<Verb>` with the vision's verbs (§3.4) — `Read`, `Modify`, `Approve`, `Archive`, `Report`, `Administer` — over subject classes (node, asset, device, scheme, connection, configuration file, document, work request, record, obligation, definition, grant …). Lifted from the predecessor's 42 `Module.Entity.Verb` codes, restated |
| `security.RolePermission` — class `Reference` | `RoleCode`, `PermissionCode` |

### 11.4 `security.Grant` — class `BiTemporal` (155)

| Column | Notes |
|---|---|
| base columns | bi-temporal: who held what, when, and when we believed it (vision §9.4) |
| `GranteeKind`, `GranteeEntityId` | `User` or `Group` |
| `RoleCode` | FK |
| `ScopeKind` | `NodeSubtree` (with `AssetClassCode` / `DeviceCategory` filter), `WorkRequest`, `OwnershipRelation` (entity × ownership role — decision 38), `Global` (positional roles such as Administrator) |
| `ScopeNodeEntityId`, `ScopeAssetClassCode`, `ScopeDeviceCategory`, `ScopeWorkRequestEntityId`, `ScopeEntityEntityId`, `ScopeOwnershipRole` | one set populated per `ScopeKind`; check constraint |
| `GrantedByActorId`, `RevokedByActorId`, `RevocationReason` | |

The access decision is role × functional location × device type (vision §3.3), evaluated
**strictly for reads as for writes** (decision 59), in the server, deny by default. A grant of an
assignment role with `ScopeKind = WorkRequest` is what "assign" means (decision 141), and the
procedure that writes it evaluates the work type's qualification requirement (§11.6).

### 11.5 `security.Delegation` — class `BiTemporal` (156)

`(EntityId, FromPersonEntityId, ToPersonEntityId, RoleCode [positional only], StartsAt, EndsAt,
Reason, GrantedByActorId, RevokedByActorId)`. The authority passes and returns; it is never
reassigned (vision §3.5). Every act taken under it has an actor row with `ActorKind =
Delegated` pointing here.

### 11.6 Qualification and training (157)

| `personnel.QualificationType` — class `Reference` | `QualificationTypeCode` PK, `Name`, `WorkCategory`, `ApplicableAssetTypeCode` null, `RequiredOjtHours`, `RequiredExperienceYears`, `RecertificationDays`, `RequiresSupervisorSignOff` — lifted from the predecessor's `QualificationPath` |
|---|---|
| `personnel.QualificationTypeModule` — class `Reference` | `QualificationTypeCode`, `TrainingModuleCode`, `IsPrerequisite`, `MinimumPassScore` |
| `personnel.TrainingModule` — class `Reference` | `TrainingModuleCode` PK, `Name`, `Category`, `DeliveryMethod`, `RequiredFrequencyDays`, `DurationHours`, `CipModuleCode` (the cyber-security training family's module identity — verify), `ProviderEntityEntityId` null |

| `personnel.PersonQualification` — class `ValidTime` | Notes |
|---|---|
| base columns | valid period = while it is held |
| `PersonEntityId`, `QualificationTypeCode` | |
| `GrantedAt`, `GrantedByActorId`, `ExpiresAt` | |
| `AssessmentRecordEntityId` | FK → `record`, null — the assessment that granted it |
| `OjtHoursCompleted` | derived from on-the-job training records |
| `RevokedAt`, `RevocationReason` | |

Training events and attendance are `record.Record` rows of kind `TrainingAttendance` (subject:
the person; second subject: the module — `personnel.TrainingModule.EntityId`, added 2026-09-06 because a
code-keyed reference row had no identity a record could cite; characteristics: score, passed, certificate document);
on-the-job training is the record kind `OnTheJobTraining` (step 10). A succession gap is a report
over qualifications, not a table.

**Gating** is the definition `Program.QualificationRequirement`: work type × device class →
qualification type, mode `Block` or `Warn`; evaluated when an assignment grant is written; a
`Warn` proceeds and logs, a `Block` refuses unless an override (§11.7) is recorded. Optional and
disableable by the Administrator (vision §3.5).

### 11.7 Segregation of duties (158)

`Program.SegregationRule` definition rows: `(ActionA, ActionB, SubjectKind, Mode [Block, WarnAndLog])`
— author ≠ approver of a settings revision, author ≠ approver of a rule definition, tester ≠
acceptor of a test sheet, and any the Administrator adds.

| `security.SegregationOverride` — class `AppendOnly` | `OverrideId`, `RuleDefinitionVersionRowId`, `SubjectKind`, `SubjectEntityId`, `ActionTaken`, `ActorId`, `Reason`, `ApprovedByActorId` null, `OccurredAt`, `ActionLogId` |
|---|---|

Warn-and-log is the default (vision §9.5); every override is an action-log entry with authority.

### 11.8 `personnel.Authorisation` — class `BiTemporal` (159)

Decision 56's entity; a compliance subject in its own right (step 12).

| Column | Notes |
|---|---|
| base columns | |
| `PersonEntityId` | FK |
| `RightKind` | FK → `ref.AuthorisationRightKind`: `PhysicalAccess`, `ElectronicAccess`, `RemoteAccess`, `InformationAccess` (BES cyber system information), `EscortedAccess` |
| `ScopeKind`, `ScopeEntityId` | station node subtree, device category, security perimeter, document class |
| `AuthorisationBasis` | `NVARCHAR(200)` — the role or need |
| `RiskAssessmentAt` | `DATETIMEOFFSET(7)`, null — personnel risk assessment date |
| `TrainingCurrentAsOf` | derived from training records; stored as-of the grant for the evidence |
| `GrantedByActorId`, `RevokedByActorId`, `RevokedAt`, `RevocationReason` | |

Lifted from the predecessor's `compliance.CIPPersonnelAccess`; its `CIPPersonnelTraining` is
the training record kind above. Obligation rules of the personnel and training family (verify)
scope on `person.authorisations[kind]`, `person.training[module].current` from the catalogue.

### 11.9 Comparison with the predecessor

| Predecessor | Verdict |
|---|---|
| `core.Person`, `PersonRegistry` | **Lifted** as `personnel.Person` |
| `core.PersonCredential`, `LoginSession` | **Dropped**: AD authenticates; sessions are application state |
| `core.Role` (14), `Permission` (42), `RolePermission` | **Lifted**, restated in the vision's verbs and role kinds |
| `core.PersonRole` (valid-time) | `security.Grant` with `ScopeKind = Global` |
| `core.PersonDivisionGrant` | `security.Grant` with `ScopeKind = NodeSubtree` or `OwnershipRelation` |
| `training.QualificationPath`, `QualificationPathModule`, `TrainingModule` | **Lifted** as reference tables |
| `training.PersonQualification` | **Lifted** |
| `training.TrainingEvent`, `TrainingAttendance`, `OJTRecord` | Record kinds |
| `training.SuccessionGap` | A report |
| `compliance.CIPPersonnelAccess` | **Lifted** as `personnel.Authorisation` |
| `compliance.CIPPersonnelTraining` | Training record kind |
| No actor, delegation, segregation override, group | **Added** |

### 11.10 Decisions

**Decided 2026-09-03:** 152 `Person`, `User` (AD identity only) and immutable `Actor` with kind
and delegation · 153 `Position`, `PositionHolder`, `Group`, `GroupMember` · 154 `Role` with kind,
`Permission` in subject-class × verb form, `RolePermission` · 155 bi-temporal `Grant` with scope
kinds node subtree, work request, ownership relation, global; strict for reads · 156
bi-temporal `Delegation` referenced by actors · 157 qualification type and training module as
reference; person qualification valid-time; training and OJT as records; gating as a definition
· 158 segregation rules as a definition with an append-only override log · 159 bi-temporal
`Authorisation` lifted from CIP personnel access · 160 no local credentials or sessions in the
schema.

---

## 12. Compliance objects and the fact catalogue

Vision §4.8, §4.12 "Compliance objects", "A revised or new standard is data", §5.1–§5.11,
§9.2; decisions 37, 39, 46, 48, 52, 54, 56, 64, 65. Decisions here: 161–170. No requirement
numbers, intervals or standard text appear here; every standard reference must be verified
against the current text before a rule is authored.

### 12.1 Standards, versions, requirements (161)

| `compliance.Standard` — class `Reference` | `StandardCode` PK (family identifier as the body publishes it), `IssuingEntityEntityId` → `party.Entity` (NERC, NPCC, CSA, IEEE, IEC …), `Family`, `Subject`, `IsActive` |
|---|---|

| `compliance.StandardVersion` — class `BiTemporal` | Notes |
|---|---|
| base columns | bi-temporal: when a version came into force and when we learned it |
| `StandardCode` | FK |
| `VersionLabel` | as published |
| `EffectiveFrom`, `EffectiveTo` | the enforcement period |
| `OverlapUntil` | `DATETIMEOFFSET(7)`, null — a transition window during which this and the prior version may both be followed (decision 64) |
| `TextDocumentEntityId` | FK → `document`, null — the text if licensed to hold; otherwise `TextReference` |
| `TextReference` | `NVARCHAR(400)` |
| `SupersedesVersionRowId` | FK, null |

| `compliance.Requirement` — class `ValidTime` | `EntityId`, `StandardVersionRowId`, `RequirementNumber`, `SubRequirement`, `Title`, `Summary` (NB Power's paraphrase, not the text), `EvidenceGuidance`, `SubjectKinds` (the kinds this requirement addresses: station, scheme, device, person, entity, document, platform) |
|---|---|

The predecessor's `RegulatoryRequirement` (19 rows, keyed by body, standard, version, number)
seeds this; its `CIPRequirement` duplicate is dropped.

### 12.2 Obligation rules — definitions (162)

`Program.ObligationRule` definition payload, one per requirement it implements:

- `RequirementEntityId` — which requirement;
- **scoping predicate** — an expression over catalogue facts (§12.3) yielding the subjects the
  requirement applies to, e.g. schemes whose station or line carries a BES classification and
  whose members include a relay of technology microprocessor;
- **subject kinds admitted** — physical (station, scheme, device, asset, connection) or
  non-physical (person, entity, document, definition, platform) — decision 56;
- **cadence** — the cadence sub-language of FORMULA-GRAMMAR.md §6: `every 6 y from <anchor>`,
  `every calendar_year`, `within 30 d of event`, `once`; an unknown anchor falls back to the rule's
  effective date and is flagged (decision 195);
- **work type** to raise when unsatisfied and the lead time to raise it;
- **evidence definition** — the record kinds, with minimum acceptance, that satisfy an instance;
  a correct protection operation may be admitted where the standard allows (decision 52, verify);
- **responsible role** for the assertion.

Rules are authored by the Compliance Officer (vision §3.2) and approved by another actor under
the segregation rule; a rule is `Effective` from its standard version's effective date. The
predecessor's `workplan.MaintenancePolicy` (13 fixed-interval rows) and
`core.AssetComplianceObligation` (the hand-maintained register) are what these replace.

### 12.3 The fact catalogue (163)

`compliance.vFactCatalogue` is a **generated view**, not a table, listing every fact a rule may
reference:

| Column | Notes |
|---|---|
| `FactName` | `station.type`, `station.classification.<kind>`, `line.classification.<kind>`, `line.voltage_class`, `scheme.type`, `scheme.members[role]`, `function.commissioned`, `function.logical_node`, `device.model`, `device.technology`, `device.firmware`, `device.template.<key>` (every `CharacteristicDefinition` with `IsCatalogueFact`), `device.settings.<code>` (every `SettingDefinition` with `IsCatalogueFact`), `device.connections[realisation]`, `device.advisories[open]`, `network.port`, `network.vlan`, `network.routable`, `channel.route`, `channel.links[owner]`, `asset.owner_of_record(role, at)`, `record.last(kind, subject)`, `study.is_stale`, `person.qualifications[type]`, `person.authorisations[kind]`, `person.training[module].current`, `entity.agreements[kind]`, `document.revision.current(class)`, `platform.release`, `platform.baseline` … |
| `SourceSchema`, `SourceObject`, `SourceColumn` | where the interpreter reads it |
| `SubjectKind` | what it is a fact about |
| `TemporalClass` | so the interpreter knows whether an as-of read is possible |
| `PublishedByDefinitionVersionRowId` | null for fixed facts; the template or transform version for published characteristics and settings |

Facts take **named parameters** (`scheme.members[role='Relay']`, `record.last[kind='Maintenance',
accepted=true]`; column `Parameters`, a JSON list of names). Built 2026-09-06 (PROCEDURES #35) with these
spellings where the list above differs: `document.revision_current` + `document.class` for
`document.revision.current(class)`; `person.training_current[module]` for `person.training[module].current`;
`network.services[protocol]` added; `platform.release` / `platform.baseline` not built (no table holds the
platform's own baseline yet); `network.routable` and the `Routable` value of `device.connections` wait on
the path walk (#11) and **path steps** through Reference and
Set values (`…record.last[…].record.occurred_at`); the view also carries `Base` and `ReferenceKind` so the
interpreter types what it reads (decision 194). The interpreter refuses a rule that names a fact absent from the view. Adding a characteristic
with `IsCatalogueFact = 1` to a template version, or a formula definition that publishes a
derived fact, makes it appear in the view with no other change — the property the
extensibility gate (§2.6) proves before any of this is built. The trigger of vision §5.4 ("on any
change") is a subscription on the source objects the view names.

### 12.4 `compliance.RuleEvaluationRun` — class `AppendOnly` (164)

| Column | Notes |
|---|---|
| `RunId` PK | |
| `RuleDefinitionVersionRowId` | FK — or null for a full-catalogue run |
| `Mode` | `Preview`, `Effective` |
| `Trigger` | `Scheduled`, `FactChanged`, `RuleApproved`, `Manual` |
| `StartedAt`, `CompletedAt`, `ActorId` | |
| `SubjectsScoped`, `InstancesOpened`, `InstancesClosed`, `InstancesUnchanged` | counts |
| `ResultDocumentEntityId` | FK → `document`, null — the preview's impact assessment, kept (scenario 5) |

A `Preview` run writes nothing but this row and its document; an `Effective` run writes
instances (`compliance.RunRuleEffective`, built 2026-09-05: both modes scope through `fRuleSubjects`;
the rule payload names its `requirement`, `cadence` and `evidence` — FORMULA-GRAMMAR.md §7).

### 12.5 `compliance.ObligationInstance` — class `BiTemporal` (165)

| Column | Notes |
|---|---|
| base columns | |
| `SubjectKind`, `SubjectEntityId` | polymorphic, any kind the rule admits |
| `RuleDefinitionVersionRowId` | FK — the rule version that derived it |
| `RequirementEntityId` | FK — denormalised for reporting |
| `ElectedStandardVersionRowId` | FK — during an overlap window, which version the entity elected (decision 64) |
| `PeriodStartAt`, `PeriodEndAt` | the compliance period this instance covers |
| `Status` | `Open`, `Satisfied`, `Exception`, `NotApplicable`, `Superseded` |
| `RaisedWorkRequestEntityId` | FK, null |
| `EvaluationRunId` | FK → the effective run that opened it |

| `compliance.ObligationInstanceFact` — class `AppendOnly` | `ObligationInstanceRowId`, `FactName`, `SourceRowId`, `ValueAsRead` — the **fact versions** the derivation read (decision 54); the reverse walk an auditor makes |
|---|---|

**Due** is `compliance.vObligationDue`: for each open instance, the last satisfying record's
instant plus the rule's cadence, or the period end, whichever the rule says. Never a column.
Built 2026-09-05 over `fObligationDue` (the cadence node evaluated as of now; `PeriodEndAt` when
Unknown; `DueBasis`, `IsOverdue`, `DaysToDue`). `ObligationInstanceFact.SourceRowId` is null for now:
the interpreter reads values, not row ids — a follow-on when `fFactRead` surfaces them.

### 12.6 `compliance.EvidenceLink` and `compliance.Assertion` — class `BiTemporal` (166)

| `compliance.EvidenceLink` | `ObligationInstanceRowId`, `RecordRowId` (a record's fact version, never a file — decision 47), `JudgedByActorId`, `JudgedAt`, `Sufficiency` (`Sufficient`, `Partial`, `Insufficient`), `EvidenceDefinitionVersionRowId` (the definition it was judged against), `Notes`. Many-to-many: one record may evidence several instances (vision §5.6) |
|---|---|
| `compliance.Assertion` | `SubjectKind`, `SubjectEntityId`, `StandardVersionRowId`, `RequirementEntityId` null (whole standard or one requirement), `PeriodStartAt`, `PeriodEndAt`, `AssertedByActorId`, `AssertedAt`, `Statement` (`Compliant`, `NonCompliant`, `NotApplicable`), `Basis` (`NVARCHAR(1000)`), `SupportingInstanceRowIds` via a child table |
|---|---|

The platform assembles; a person asserts (vision §5.9).

### 12.7 `compliance.EvidencePackage` — immutable (167)

| Column | Notes |
|---|---|
| `PackageId` PK | |
| `AuditRequestEntityId` | FK, null — what it answers |
| `SubjectKind`, `SubjectEntityId`, `StandardVersionRowId`, `PeriodStartAt`, `PeriodEndAt` | what it covers |
| `ValidAsOf`, `BelievedAsOf` | the two clocks the package was assembled at |
| `PreparedByActorId`, `PreparedAt`, `ReviewedByActorId`, `ReviewedAt`, `ApprovedByActorId`, `ApprovedAt` | |
| `SubmittedAt`, `SubmittedToEntityEntityId` | |
| `PackageDocumentEntityId` | FK → `document` — the rendered package (report definition output) |
| `PackageHash` | `BINARY(32)` — over the manifest |

| `compliance.EvidencePackageManifest` — class `AppendOnly` | `PackageId`, `ItemKind` (`ObligationInstance`, `Record`, `EvidenceLink`, `Assertion`, `ConfigurationFileRevision`, `File`, `DefinitionVersion`), `ItemRowId`, `FileSha256` null — every row version and file the package contains, including the rule, evidence and report definition versions in force, so the package reproduces |
|---|---|

Once `ApprovedAt` is set the package and its manifest are read-only; a correction is a new
package citing the old. Lifted from the predecessor's `CIPEvidencePackage` with the manifest and
the two clocks added; its `AuditorFindings` column becomes findings (§12.8).

### 12.8 Audit, request, finding, exception (168)

| `compliance.Audit` — class `ValidTime` | `EntityId`, `AuditingEntityEntityId` → `party.Entity`, `AuditKind` (`Regulatory`, `Internal`, `SpotCheck`, `SelfCertification`), `ScopeDescription`, `PeriodStartAt`, `PeriodEndAt`, `NoticeReceivedAt`, `FieldworkStartAt`, `ClosedAt`, `LeadActorId` |
|---|---|
| `compliance.AuditRequest` — class `ValidTime` | `AuditEntityId`, `RequestReference`, `RequirementEntityId` null, `SubjectKind`, `SubjectEntityId` null, `RequestedAt`, `DueAt`, `Description`, `AnsweredByPackageId` null |
| audit findings | `record.Finding` rows of category `AuditFinding` with the audit as subject and a corrective work request |

| `compliance.Exception` — class `BiTemporal` | Notes |
|---|---|
| base columns | |
| `SubjectKind`, `SubjectEntityId` | |
| `RuleDefinitionVersionRowId`, `ObligationInstanceRowId` null | |
| `ExceptionKind` | `SelfReport`, `Misoperation`, `MissedCadence`, `TechnicalFeasibility`, `AuditFinding` |
| `OpenedAt`, `OpenedByActorId` | |
| `ClockDueAt` | `DATETIMEOFFSET(7)` — **derived at opening** from the event instant and the rule version, stored so the record shows what the clock was when opened; re-derived and re-stored if the rule version changes (scenario 5) |
| `MitigationPlanDocumentEntityId` | FK, null |
| `ReportedAt`, `ReportedToEntityEntityId`, `ReportReference` | |
| `ClosedAt`, `ClosedByActorId`, `ClosureBasis` | |

A protection operation with outcome `Incorrect` (step 7) opens an `Exception` of kind
`Misoperation` in the same procedure.

### 12.9 `compliance.Interpretation` — class `ValidTime` (169)

`(EntityId, StandardVersionRowId, RequirementEntityId null, Title, InterpretationText,
ApprovedByActorId, ApprovedAt, SupersedesEntityId null, RationaleDocumentEntityId null)` — NB
Power's documented reading of a requirement, cited by rules and packages. The final review
named this as something that would otherwise stay in a spreadsheet.

### 12.10 Vulnerability assessment (170)

A `record.Record` of kind `VulnerabilityAssessment` against a device, scheme or perimeter, with
findings (category `AuditFinding` or `Observation`), the assessment document, lead assessor and
remediation work request. The predecessor's `CIPVulnAssessment` is this; `ref.RecordKind` gains
the kind.

### 12.11 Comparison with the predecessor

| Predecessor | Verdict |
|---|---|
| `compliance.RegulatoryRequirement` (19), `CIPRequirement` (19, duplicate) | **Lifted** into `Standard` / `StandardVersion` / `Requirement`; duplicate dropped |
| `core.AssetComplianceObligation` (hand-maintained subject × requirement with dates) | **Replaced** by rules + derived instances (vision §5.2) |
| `workplan.MaintenancePolicy`, `PRC005Category` | Obligation rule definitions |
| `compliance.CIPEvidencePackage` | **Lifted** with manifest and two clocks |
| `compliance.CIPVulnAssessment` | Record kind |
| `compliance.CIPClassificationRegistry`, `CIPAssetClassification` | `asset.Classification` (step 4) |
| No rule, run, instance, fact, link, assertion, audit, exception or interpretation tables | **Added** — the object model of vision §5 |

### 12.12 Decisions

**Decided 2026-09-03:** 161 `Standard`, bi-temporal `StandardVersion` with overlap window and
text reference, `Requirement` with admitted subject kinds · 162 obligation rules as definitions
with predicate, subject kinds, cadence, work type and evidence definition · 163 the fact
catalogue is a generated view; rules may name only what it lists · 164 `RuleEvaluationRun`
append-only with preview and effective modes and a kept result document · 165 bi-temporal
`ObligationInstance` with elected version and an append-only fact-version child; due is a view ·
166 bi-temporal `EvidenceLink` citing record row versions and `Assertion` by a person · 167
immutable `EvidencePackage` with manifest of row versions, file hashes and definition versions,
and both clocks · 168 `Audit`, `AuditRequest`, findings as records, bi-temporal `Exception` with
a stored derived clock · 169 `Interpretation` · 170 vulnerability assessment as a record kind.

---

## 13. Network model skeleton, event tier, archive seam

Vision §4.9 (deep, unexercised), §2.5 (nothing is ever lost), §10.6 (archive tier), §11.4
(ASPEN), §11.5 (line constants from TLM), §4.11 (line sections). Decisions here: 171–177 and 186–190 (overlay layers, 2026-09-05).

### 13.1 Overlay layers — external models on the physical truth (171, 186–190)

The owner's statement of 2026-09-05 (MIGRATION-PLAN Q23, Q27): the platform will house a complete
model of the electrical system — the transmission network first, so that other applications are
served early; transformers, breakers, disconnects, generating units and the rest connected into it
in later stages. The TLM section is where the real world (GPS structures, spans, lines) is mapped
onto the applications that consume this one source of truth. ASPEN OneLiner is the first such
application; any number of others may follow, each a **layer** a user creates, with its own export
template — and **no custom programming for any particular layer**. Everything a layer needs that is
particular to its system is the layer's content: two definitions, mapping rows, records.

The shape below is what the TLM predecessor learned (its `aspen-bus-overlay-framework-clean`
branch; tombstones Phase33/38/57/58, read both as template and as warning): an external bus is an
electrical identity, not a place; it needs zero-to-many physical endpoints, each scoped to one line
on a shared tower; a branch is the walk between two endpoints, derived and never cached; an anchor
that cannot be verified is left unresolved, never guessed from the nearest structure; tools stage
matches and humans apply them.

| `network.Layer` — class `ValidTime` (186, 190) | `EntityId`, `Name` (unique while live), `Description`, `ExportTransformDefinitionEntityId` → a `Transform.Export` definition (the export template), `ImportTransformDefinitionEntityId` → a `Transform.Import` definition (parse and reconciliation rules), `OwnerEntityEntityId` null, `Notes`. No column names a system. |
|---|---|
| `network.Case` — class `ValidTime` (186) | a **snapshot** of a layer: `LayerEntityId`, `Name`, `SystemModelAt`, `Origin` (`Imported`, `Platform`), `SourceFileDocumentEntityId` null, `StudyRevisionRowId` null → `document.Study`. `document.Study.NetworkModelCaseEntityId` cites it (§8.7). |
| `network.LayerNode` — class `ValidTime` (187) | `EntityId`, `LayerEntityId`, `ExternalNumber` (unique within the layer; also the `LayerNodeNumber` alternate key scoped to the layer), `Name`, `VoltageClassCode` null, `FirstCaseEntityId` null. **Nothing physical.** |
| `network.LayerNodeEndpoint` — class `ValidTime` (187) | `LayerNodeEntityId`, `AnchorKind` (`Structure`, `RouteStep`, `Node`) + `AnchorEntityId`, `LineAssetEntityId` null (the scope on a shared tower), `IsPrimary` (one per node and line), `SnapMethod` (`Manual`, `Reconciled`, `Imported`), `Location` geography null, `Notes`. Written only by `network.AddLayerNodeEndpoint`: a Structure or RouteStep anchor with a line scope must lie on that line's route, else refused. |
| `network.LayerBranch` — class `ValidTime` (188) | `LayerEntityId`, `BranchKind` (`LineSection`, `TransformerWinding`, `SeriesElement`, `Switch`), `FromNodeEntityId`, `ToNodeEntityId`, `CircuitId`, `LineAssetEntityId` null, the external system's `R1 X1 B1 R0 X0 B0` (per unit on its base), `LengthKm`; not self. Its path is **`network.vLayerBranchPath`**: the route steps of the line between the two nodes' primary endpoints on that line — no rows while either end is unresolved. |
| `network.LayerBranchConstants` — class `AppendOnly` (188) | `RunId` → `ConstantsRun`, `LayerBranchEntityId`, `LengthKm`, `Z1R Z1X Z0R Z0X` totals, `InputHash`, `Status`, `FailureReason` — the engine's roll-up of `LineSectionConstants` along the derived path (PROCEDURES.md #41). Branch mutuals derive from `LineSectionMutualConstants` along two paths (Q25); no table. |
| `network.SourceEquivalent` — class `ValidTime` | `CaseEntityId`, `LayerNodeEntityId`, `Z1`, `Z0` as R/X pairs |
| `network.MutualCoupling` — class `ValidTime` | `CaseEntityId`, `BranchAEntityId`, `BranchBEntityId` (layer branches), `R0m`, `X0m` — values the external system holds |

**Reconciliation (189)** is records, not tables of its own: a `LayerReconciliation` record (subject
the layer, second subject the import document) groups `LayerMatchCandidate` records (subject the
layer node, second subject the reconciliation record) whose proposal — `anchor_kind`,
`anchor_entity_id`, `line_asset_entity_id`, `is_primary`, `confidence`, `method`, `reason` — is
characteristics under a `CharacteristicSchema.RecordTemplate`. A person accepts a candidate
(`record.AcceptRecord`, decision 42); `network.ApplyReconciliation` then writes an endpoint
(`SnapMethod = Reconciled`) for each accepted, unapplied candidate and marks it `applied_endpoint`.
Candidate generation is a generic engine over the layer's import mapping rows (PROCEDURES.md #40);
a re-import stages again and closes what is gone — it never deletes (§3.7, §6.4).

**Transforms (190).** `config.TransformMapping.TargetKind` gains `LayerField`; `TargetKey` names
`node.number`, `node.name`, `node.kv`, `endpoint.*`, `branch.from`, `branch.to`, `branch.circuit`,
…. The export template is a `Transform.Export` version's `Generate` rows (ASPEN's DXT tokens are
rows); the parse and matching rules are a `Transform.Import` version's `Parse` rows with
`ConversionExpression`s — for ASPEN: NB buses start with 17; the line-number prefix gives the
voltage (0 = 69, 1 = 138, 2 = 230, 3 = 345 kV); 69 kV taps `TxxxLyyy`, 138 kV taps `xxxxyy`; a
named station bus is a station anchor, never one line (TLM `ASPEN_RECONCILIATION_RULES.md`). None
of it is code.

**Migration.** TLM's `ASPEN_Buses`, `ASPEN_BusMapBindings`, `ASPEN_LineBranches`,
`ASPEN_BranchCalculationResults`, `ASPEN_ReconciliationSessions` and `ASPEN_BusEndpointCandidates`
are lifted as the first layer (MIGRATION-PLAN §5.5); `ASPEN.ReferenceConstants` / `ReferenceMutuals`
are ASPEN's own answers kept by TLM as benchmarks and become parity records later, not model data.

### 13.2 Line sections and constants — from TLM (172)

| `network.LineSection` — class `ValidTime` | `EntityId`, `LineAssetEntityId` → the line, `FromRouteStepRowId`, `ToRouteStepRowId` (a run of consecutive spans on the line's `location.Route`), `StructureTypeDefinitionVersionRowId` (the construction in force), `ConductorAssetTypeCode` / `ConductorTemplate`, `GroundWireCount`, `LengthKm` — a grouping over route steps, not a location node (decision 21) |
|---|---|
| `network.ConstantsRun` — class `AppendOnly` | `RunId`, `StartedAt`, `ActorId`, `EngineDefinitionVersionRowId` (the line-constants module's version — a `Program.Formula` family), `Method` (`CarsonSimplified`, `DeriSemlyen`), `EarthResistivityOhmM`, `FrequencyHz`, `SectionsCalculated`, `Status` |
| `network.LineSectionConstants` — class `AppendOnly` | `RunId`, `LineSectionEntityId`, `Z1R`, `Z1X`, `Z0R`, `Z0X`, `B1`, `B0` per unit length and total, `MutualsToSectionEntityId` + `Z0mR`, `Z0mX` rows in a child, `InputHash` — the calculation is reproducible from the run and the hash |

The structure-type template (attachment points, circuit slots — decision 22) and the conductor
library (a `ref.ConductorType` reference table: name, GMR, resistance, diameter, ampacity) are
the geometry and material inputs. TLM's `LineSections`, `LineSectionSegments`,
`LineSectionCircuits`, `BatchCalculationRuns`, `LineSectionCalculations` are **lifted** in
shape; the results are held against the line asset and versioned (vision §11.5).

### 13.3 Event tier — separable from the first table (173)

All `event.*` tables are class `AppendOnly` and live on the `EventData` filegroup (§13.6).

| `event.Event` | `EventId`, `OccurredAt` + `TimeSourceQuality`, `SourceDeviceEntityId`, `SourceKind` (`Dfr`, `RelayEventReport`, `Pmu`, `Ser`), `Format` (`Comtrade`, vendor formats), `SampleRateHz`, `DurationMs`, `NominalFrequencyHz`, `TriggerDescription`, `ProtectionOperationEntityId` null, `RawFileEntityId` → `document.File` in the archive store, `IngestedAt`, `IngestRunId` |
|---|---|
| `event.Channel` | `ChannelId`, `EventId`, `ChannelKind` (`Analog`, `Digital`), `Name`, `UnitCode`, `Phase`, `CtRatio`, `PtRatio`, `PrimaryOrSecondary`, `SortOrder`, `SourcePortEntityId` null → `connection.Port` |
| `event.SampleBlock` | `ChannelId`, `BlockSequence`, `SampleCount`, `Encoding`, `Samples` `VARBINARY(MAX)` compressed |
| `event.SerRecord` | `SerRecordId`, `SourceDeviceEntityId`, `OccurredAt` + `TimeSourceQuality`, `PointName`, `PointDescription`, `PreviousState`, `NewState`, `SourceFormat`, `SourceFileEntityId` null — lifted from the predecessor (174); correlation to an operation is through `scheme.ProtectionOperationSnapshot`, not a join table |
| `event.PmuStream` | `StreamId`, `PmuDeviceEntityId`, `ConfigurationFileRevisionRowId`, `ReportingRateHz`, `StartedAt`, `EndedAt` — shape only (175) |
| `event.PhasorBlock` | `StreamId`, `BlockStartAt`, `BlockEndAt`, `Encoding`, `Data` `VARBINARY(MAX)` — shape only (175) |

The predecessor's `dbo.TEV.*` (event, channels, samples, raw files) is **lifted**; its
`RelayProfiles` (characteristic type, default impedance parameters per model) and
`EventSettings` (the CT / PT ratios and reach settings an analysis used) become a
`CharacteristicSchema` template per model and a record of kind `OperationReview` citing the
configuration-file revision as-of, respectively (176). Analysis engines (DFT, phasors, fault
location — vision §7.6) read these tables and write records; they do not write here.

### 13.4 Archive seam (177)

The vision leaves the archive tier's form open (§10.6, §13.3). The schema fixes the seam so the
choice is deferred without rework:

- `event.*`, `document.FileStore` for operational bulk, and `event`-class indexes are on
  dedicated filegroups (`EventData`, `EventIndex`, `BulkFiles`) from the first deployment.
- `archive.Manifest` — class `AppendOnly`: `ManifestId`, `SourceSchema`, `SourceTable`,
  `KeyRangeFrom`, `KeyRangeTo`, `RowCount`, `MovedAt`, `Destination` (`SameDatabaseFilegroup`,
  `ArchiveDatabase`, `CompanionStore`), `DestinationReference`, `Sha256`, `MovedByActorId` —
  what has been moved out, where, and how to verify it.
- `archive.Retention` — class `Reference`: per record kind and event kind, the retention rule
  (which is a definition the Administrator sets, never a purge — vision §10.6).
- The generated views (§0.3) read across the seam by `UNION ALL` over the live table and, when
  the archive is a separate database, a synonym; the application never knows which side a row
  is on.

### 13.5 Comparison with the predecessor

| Predecessor | Verdict |
|---|---|
| No network model tables | **Added** as a skeleton |
| TLM (`dbGridInfo`, read 2026-09-05) | Line sections, runs and constants **lifted** in shape; structures and templates already in steps 3–4; normalised structure templates → `StructureType` definitions, transitional bracketed ones **not carried** (TLM's own normalisation plan) |
| TLM `ASPEN_*` (the ASPEN bus overlay, branch `aspen-bus-overlay-framework-clean`) | **Lifted** as the first overlay layer (§13.1): buses → layer nodes, bindings → endpoints, branches, calculation results, reconciliation sessions and candidates as records; `ASPEN.ReferenceConstants/Mutuals` **not carried** (benchmarks → parity records later). Its dropped `BranchTerminals` and bus snap columns are the warning: no second source of truth for an anchor |
| `dbo.TEV.Events`, `Channels`, `Samples`, `RawFiles` | **Lifted** as the event tier |
| `dbo.TEV.RelayProfiles`, `EventSettings` | Template per model; review record citing the as-of revision |
| `events.SERRecord`, `EventSERRecord` | **Lifted** as `event.SerRecord`; correlation via the operation snapshot |
| No archive structures | **Added**: filegroups, manifest, retention |

### 13.6 Decisions

**Added 2026-09-06 (236):** `event.LightningStrike` — class `AppendOnly` on `EventData`: `StrikeId`, `SourceSystem`, `SourceStrikeId` (unique per source: an idempotent landing), `OccurredAt` + `TimeSourceQuality`, `Location` GEOGRAPHY (spatial index), `AmplitudeKa`, `StationCount`, `FeedRunId` → `migration.Run` (a feed run reuses the migration run and provenance shape, PLATFORM-ARCHITECTURE §5.1), `SourceHash`. Facts `operation.lightning_nearby[km, minutes]` (set of strikes within the distance of any located place of the operation's primary asset — placement node or route step nodes — and within the window) and `operation.lightning_count[km, minutes]`; a set-based spatial query by design, C++ only if a QA measurement earns it (vision §7.3).

**Decided 2026-09-03:** 171 network skeleton: case, bus, branch with sequence parameters and a
link to the physical asset, source equivalent, mutual coupling · 172 line sections as groupings
over route steps; constants runs and results append-only and reproducible; conductor library as
reference · 173 event tier append-only on its own filegroup: event, channel, sample block, raw
file in the archive store · 174 sequence-of-events lifted, correlated through the operation
snapshot · 175 synchrophasor stream and phasor block as shapes · 176 relay profiles are
templates; analysis settings are review records · 177 archive seam: dedicated filegroups,
`archive.Manifest`, `archive.Retention`, views that span the seam.

---

## 14. Mapping from `dbPCPlatform_DEV`, and where data comes from

Vision §10.1 (the schema pass judges the predecessor, not the reverse), §10.7 (owner-led
migration, provenance, fresh capture), §11.2. Decisions here: 178–181.

### 14.1 What the predecessor is for (178)

Three uses, decided with the owner 2026-09-03:

1. **Schema comparison** — done, step by step, in every "Comparison with the predecessor"
   table above; consolidated in Appendix B.
2. **Development and training data.** The predecessor's data — real NB Power station names,
   377 relays, a full 61850 parse of 115 IEDs, 996 setting definitions, 171 rationale documents,
   61 legacy change requests — populates `PnCPlatform_DEV` for development and test, and a
   dedicated **`PnCPlatform_TRAIN`** database for user training, through the same
   `migration.Run` / `Provenance` machinery as production, so the migration transforms are
   exercised long before they run for real. The training database is refreshed from the
   predecessor on demand and never receives production data.
3. **Never a production source.** Production is loaded only from the client's live systems
   (§14.3).

### 14.2 Seed and reference rows (179)

Hand-curated lists in the predecessor are loaded into every environment, production included,
as seed data with provenance, and are then the Administrator's to edit:

| Predecessor | Target | Rows |
|---|---|---|
| `core.AssetType` | `ref.AssetType` (+ sketch additions) | 54 |
| `core.LocationType` | `ref.LocationNodeType` (re-mapped per step 3) | 21 |
| `protection.AnsiCodeRegistry` | `ref.AnsiFunction` | 62 |
| `protection.DeviceType` | `ref.Model` | 51 |
| `core.Vendor` | `party.Entity` + `ref.Manufacturer` | 7 |
| `core.Role`, `Permission`, `RolePermission` | `security.Role`, `Permission`, `RolePermission` (restated) | 14 / 42 / 169 |
| `training.TrainingModule`, `QualificationPath` | `personnel.TrainingModule`, `QualificationType` | 20 / 1 |
| `compliance.RegulatoryRequirement` | `compliance.Standard` / `StandardVersion` / `Requirement` | 19 |
| `config.AttributeKey`, `core.AssetTypeTemplate` | `config.CharacteristicDefinition` under asset-template definitions | 39 / 27 |
| `protection.SettingDefinition` | `config.SettingDefinition` under parse-transform definitions | 996 |
| `protection.SettingTemplate` / `Entry` | `StandardSettings` definitions | 36 / 6 |
| `workflow.WorkflowTemplate` + stages + transitions | six `Program.Workflow` definitions | 8 / 44 / 52 |
| `workplan.MaintenancePolicy`, `PRC005Category` | thirteen `Program.ObligationRule` definitions, marked *unverified against current standard text* | 13 / 6 |
| `notify.NotificationType` | six `Program.NotificationType` definitions | 6 |
| `protection.DrawingStatus`, `core.LookupCategory` / `LookupValue` | `ref.DrawingStatus`, enumeration definitions | 6 / 49 |

### 14.3 Production sources — a separate plan (180, 181)

The production migration is **its own document**, `docs/schema/MIGRATION-PLAN.md`, written
after the DDL exists and the transforms can be rehearsed against `PnCPlatform_DEV`. The owner's
direction 2026-09-03:

- **The one live database imported is `dbRelayManagement_Legacy`** — the 1990s settings
  database behind the C++Builder application (vision §10.7), captured fresh at migration time.
  It is the source of relays, settings history, change requests and rationale references.
- **Other sources are simpler feeds**, not databases to reconcile: the Cascade functional-location
  export (region → panel, step 3), the Doble RTS test history from approximately 2001
  (decision 62), the Relaying Field Notes as documents (decision 40), TLM's structures, sections
  and constants (step 13), SCL files from the stations, and the rationale Word documents.
- Every migrated row carries `MigrationRunId` and a `migration.Provenance` row; every run carries
  its source capture date and the cleansing-rule definition version applied (§1.2).
- The plan's open items are access to `dbRelayManagement_Legacy` for cataloguing (the dev login
  cannot read it today) and the form of the Cascade export (vision §11.2).

### 14.4 Decisions

**Decided 2026-09-03:** 178 the predecessor populates `PnCPlatform_DEV` and a dedicated
`PnCPlatform_TRAIN` through the migration machinery; never production · 179 the predecessor's
curated reference lists are seed data in every environment, with provenance, then
Administrator-owned · 180 production migration is a separate plan written after DDL, rehearsed
on DEV · 181 the only live database imported is `dbRelayManagement_Legacy`; Cascade, RTS, Field
Notes, TLM, SCL and rationale documents are feeds.

---

## 15. Operations — backup, restore and integrity

Vision §12.2 (backup is the platform's responsibility, Administrator-configurable), §7.5 (the
privilege boundary), §9.2 (the platform collects evidence about itself), §13.3 (RPO / RTO open).
Decisions here: 182–185, taken 2026-09-04.

### 15.1 `config.BackupPolicy` — a definition (182)

A `Program.BackupPolicy` definition, versioned and approved like every other definition, whose
payload the Administrator edits in the application:

| Field | Notes |
|---|---|
| full backup schedule, differential schedule, log backup interval | cron-style expressions |
| destination | path or URL; credentials are **not** here (vision §9.8) but in the server's credential store, referenced by name |
| retention | per backup kind, in days; never a purge of records — this is backup media only |
| encryption | on / off, certificate name |
| archive filegroups | whether `EventData`, `BulkFiles` back up on the same schedule or their own |
| verification | checksum on write; `RESTORE VERIFYONLY` after each full |
| restore rehearsal cadence | how often a restore test must run |
| `TargetRpoMinutes`, `TargetRtoMinutes` | declared targets, **open** until NB Power sets them (§13.3); runs are judged against them once set |

### 15.2 `audit.BackupRun` and `audit.RestoreTest` — class `AppendOnly` (183)

| `audit.BackupRun` | `BackupRunId`, `PolicyDefinitionVersionRowId`, `BackupKind` (`Full`, `Differential`, `Log`, `FilegroupFull`), `DatabaseName`, `StartedAt`, `CompletedAt`, `DestinationReference`, `SizeBytes`, `ChecksumVerified`, `VerifyOnlyPassed`, `Outcome` (`Succeeded`, `Failed`, `Skipped`), `ServerMessage`, `AchievedRpoMinutes` (computed from the last log backup) |
|---|---|
| `audit.RestoreTest` | `RestoreTestId`, `BackupRunId`, `RestoredToServer`, `StartedAt`, `CompletedAt`, `IntegrityCheckPassed` (`DBCC CHECKDB` on the restored copy), `RowCountsMatched`, `AchievedRtoMinutes`, `ActorId`, `Outcome`, `Notes` |

Both are evidence: the recovery-plan family of the CIP standards (verify against current text)
asks for backup and restore testing records, and these rows are what an obligation rule of that
family scopes on through `platform.backup.last(kind)` and `platform.restore_test.last` in the
fact catalogue (§12.3). A backup that has never been restored is an assumption, not a plan.

### 15.3 The privilege boundary (184)

The application login has `EXECUTE` on procedures and `SELECT` on views (vision §7.5) and can
neither run a backup nor read the server's credential store. **SQL Agent jobs, owned by a
dedicated service account**, read the effective `BackupPolicy` version through a view, perform
the backups and restore tests, and write `BackupRun` / `RestoreTest` rows through their own
procedure. The application writes policy and reads runs; it never issues `BACKUP`. A change to
the policy is picked up by the next scheduled job, and the job records which policy version it
ran under.

### 15.4 Recovery objectives (185)

`TargetRpoMinutes` and `TargetRtoMinutes` are declared on the policy so that every run and test
can be compared against them; their values are NB Power's to set (vision §12.2, §13.3) and stay
null until then, which the operations dashboard shows as "targets not set" rather than as
compliance.

### 15.6 The platform's own release and deployment (232–235) — added 2026-09-06

PLATFORM-ARCHITECTURE §8.1: the platform is a CIP subject and its evidence is data here.

| `platform.Release` — class `AppendOnly` | `ReleaseId`, `Version` (unique; the sqlproj `DacVersion`), `ReleasedAt`, `DacpacHash`, `PackageHash` null, `SbomDocumentEntityId` null, `ReleaseDocumentEntityId` null, `RecordedByActorId`, `Notes` — written by `tools/record_release.py` through `Release_Append` at the end of a deployment (232) |
|---|---|
| `platform.Deployment` — class `AppendOnly` | `DeploymentId`, `ReleaseId`, `Environment` (`DEV`, `QA`, `TRAIN`, `PROD`), `DatabaseName`, `DeployedAt`, `DeployedByActorId`, `Outcome` (`Succeeded`, `RolledBack`, `Failed`), `ChecklistRecordEntityId` null → the `PlatformDeployment` record, `SmokeChecks`, `Notes` (233) |
| facts | `platform.release` (the version of the latest succeeded deployment to the current database at `@at`), `platform.baseline` (that release as a reference) — the two facts PROCEDURES #35 could not build (234) |
| `ref.AssetType` `PlatformHost` | the platform's hosts are assets; their ports and services (`connection.Port` / `NetworkPort` / `PortService`) are the boundary-flow register as data (235) |
| `record.Record` subject `Platform` | `SubjectEntityId` null for that kind only (`CK_Record_Subject`); record kind `PlatformDeployment` with a seeded `CharacteristicSchema.RecordTemplate` (environment, release version, checklist step, rule closed, feed pull, inbound refused, notes) |

### 15.5 Decisions

**Decided 2026-09-04:** 182 backup policy is an Administrator-edited, approved definition with
schedules, destination by reference, retention, encryption, filegroup treatment, verification and
rehearsal cadence · 183 `audit.BackupRun` and `audit.RestoreTest` append-only, published to the
fact catalogue as platform facts · 184 SQL Agent jobs under a service account execute the policy;
the application never issues `BACKUP` · 185 RPO and RTO are declared targets on the policy,
null until NB Power sets them.

---

## Status at the end of the pass

Fifteen steps interviewed, designed and committed (steps 0–14 on 2026-09-03, step 15 on
2026-09-04); decisions 66–185 in Appendix A; every predecessor table mapped in Appendix B. The extensibility gate (§2.6) **passed 2026-09-04**
(`docs/schema/gate/RESULT.md`). The **SQL Database Project** (`docs/schema/ddl/`,
Microsoft.Build.Sql) was **built and deployed to `PnCPlatform_DEV` on 2026-09-04** in five waves
covering every step: 288 tables (107 registries) across the schemas of §0.1, with the temporal
class on every table, system versioning per decision 70, and filegroups for the event tier and
files. The current, history and as-of views and the base write procedures are generated from
the deployed catalog by `tools/generate.py` (decision 69, §0.5); the definition procedures, the
actor resolver, the fact catalogue and its interpreter (placeholder JSON grammar until vision
§13.3), and the backup-evidence procedures are hand-written. Seeds cover only lists this
document states. What was defaulted or deviated is in `ddl/STEPS.md`; the domain-rule
procedures the steps describe are listed, unbuilt, in `ddl/PROCEDURES.md` as the follow-on
pass. **Next:** `docs/schema/MIGRATION-PLAN.md`, rehearsed on DEV with predecessor data.

**Migration.** `docs/schema/MIGRATION-PLAN.md` was written 2026-09-04 and rehearsal 1 ran on
`PnCPlatform_DEV` the same day (predecessor seed lists and `dbRelayManagement_Legacy`: 259,406 rows,
every one with provenance; idempotent rerun). Its §9 lists the owner decisions and two schema gaps
(standard-settings entries, §8.6; a FileStore write procedure) that the next passes take up.

---

## Appendix A — Decision log

Moved to [`docs/decisions/DECISION-LOG.md`](../decisions/DECISION-LOG.md) on 2026-09-10.

The log ran across three documents, each continuing the last, and 1–65 lived in a vision-session sketch
none of them named. That scattering is why 57 decision numbers were cited by the code with no row a
reader could find. It is one file now, 258 entries, 1–258, no gaps. The 201 decisions this
document contributed are still there, tagged `SCHEMA-DESIGN` in the Source column.


## Appendix B — Predecessor mapping summary

Every `dbPCPlatform_DEV` table, its verdict and its target. *Lifted* = shape or rows carried;
*Corrected* = replaced by a different shape for a stated reason; *Collapsed* = several tables
become one shape; *Dropped* = no equivalent by design; *Data* = becomes definition or reference
rows, not a table.

| Predecessor | Verdict | Target | Step |
|---|---|---|---|
| `core.*Registry` (Asset, Location, Person, Vendor) | Lifted | `<schema>.<Entity>Registry` — the two-level identity | 0 |
| `core.MigrationProvenance` | Lifted | `migration.Provenance` + `migration.Run` | 1 |
| `core.LoginSession`, `core.PersonCredential` | Dropped | AD authenticates; sessions are application state | 1, 11 |
| `config.AttributeKey`, `core.AssetTypeTemplate` | Lifted | `config.CharacteristicDefinition` under template definitions | 2 |
| `core.Asset.Attributes` (JSON) | Corrected | `asset.CharacteristicValue` typed rows | 2 |
| `protection.SettingTemplate`, `SettingTemplateEntry` | Data | `StandardSettings` definitions | 2, 8 |
| `iec61850.SCLTemplate` | Data | `Transform.SclParse` definitions | 2 |
| `workflow.WorkflowTemplate`, `WorkflowStage`, `WorkflowStageRole`, `WorkflowTransition` (+ registries) | Collapsed | `Program.Workflow` definition text | 2, 9 |
| `core.Location`, `LocationType` | Lifted / Corrected | `location.Node`, `ref.LocationNodeType` + parents; linear nodes added; LINE, PRIMARY_ELEMENT, DIVISION re-homed | 3 |
| `core.SiteAliasSeed`, `SiteAliasOwnerList` | Lifted | `location.AlternateKey` kind `SiteAlias` | 3 |
| `core.AssetType` | Lifted | `ref.AssetType` | 4 |
| `core.Asset` | Corrected | `asset.Asset` + `device.Device` + `Placement` + characteristics | 4, 5 |
| `core.Vendor` | Lifted | `party.Entity` + `ref.Manufacturer` | 4 |
| `core.AssetConnection`, `AssetPort`, `AssetPortGroup` | Lifted | `connection.Connection`, `connection.Port` | 6 |
| `core.ProtectionScheme`, `ProtectionSchemeMember` | Lifted / Corrected | `scheme.Scheme`, `SchemeMember` (members are functions and connections) | 7 |
| `core.Tag`, `AssetTag` | Open | No vision use case; parked | 4 |
| `core.DrawingReconciliationFlag` | Corrected | `record.Finding` category `DrawingDiscrepancy` | 8, 10 |
| `core.AssetReconciliationEvent` | Corrected | `audit.ActionLog` kind | 8 |
| `core.LookupCategory`, `LookupValue` | Data | Enumeration definitions | 14 |
| `core.Person`, `PersonRole`, `PersonDivisionGrant` | Lifted | `personnel.Person`, `security.Grant` | 11 |
| `core.Role`, `Permission`, `RolePermission` | Lifted | `security.Role`, `Permission`, `RolePermission` (restated) | 11 |
| `protection.Device`, `DeviceType` | Lifted / Corrected | `device.Device`, `ref.Model`, `FirmwareHistory`, ports, conditions | 4, 5, 6, 7 |
| `hardware.FirmwareRecord` | Lifted | `device.FirmwareHistory` | 5 |
| `hardware.DeviceComponent` | Lifted | `DeviceModule` assets + `asset.AssetComponent` | 5 |
| `hardware.PortService` | Lifted | `connection.PortService` | 6 |
| `compliance.CIPConfigBaseline` | Corrected | `device.vBaseline` view | 5 |
| `compliance.CIPPatchRecord`, `supplychain.CVERecord` | Collapsed | `device.Advisory`, `AdvisoryScope`, `AdvisoryDisposition` | 5 |
| `supplychain.VendorAgreement`, `SupplyChainAck` | Lifted | `party.EntityAgreement` (shape) | 5 |
| `comms.ProtocolConfig`, `DNP3PointList` | Lifted | `connection.ProtocolEndpoint`, `PointMap` (shape) | 6 |
| `comms.ESP`, `ESPDevice` (+ registry) | Lifted | `connection.SecurityPerimeter`, `Member` | 6 |
| `comms.IEC61850Reference` | Corrected | CID revision in-service state + consistency record | 6, 8 |
| `iec61850.ParsedIED`, `LogicalDevice`, `LogicalNode`, `Dataset`, `DatasetMember`, `GOOSEControlBlock`, `GOOSESubscription`, `DataAttributeMapping` | Lifted | `connection.Ied` … `ExtRef`, `DataAttribute` under the configuration-file revision; ExtRefs promoted to connections | 6 |
| `iec61850.GEPublishSourceMap` | Data | `Transform` definition per model | 6 |
| `iec61850.SCLFiles`, `SCLFileMapping`, `Configuration`, `ConfigurationRegistry` | Corrected | `document.ConfigurationFile` revisions + `File` | 8 |
| `iec61850.ConsistencyCheck` | Lifted | `record.ConsistencyCheck` + findings | 10 |
| `protection.ProtectionSystem`, `ProtectionFunction`, `FunctionType`, `AnsiCodeRegistry` | Corrected / Lifted | `SchemeMember` rows; function node + `CommissionedFunction`; `ref.AnsiFunction` | 7 |
| `protection.IndependenceRecord` | Corrected | Record kind `IndependenceVerification` | 7, 10 |
| `protection.RAS*` (7 tables) | Collapsed | Scheme type + `SchemeAction` + conditions, operations, attestations, records | 7 |
| `protection.SettingGroup` | Corrected | Groups in the settings revision; active group is a condition | 7, 8 |
| `events.ProtectionEvent`, `FaultRecord` | Lifted | `scheme.ProtectionOperation`, `FaultRecord` + snapshot | 7 |
| `events.EventReview`, `Misoperation` | Corrected | Review record; `compliance.Exception` + findings + requests | 7, 12 |
| `events.SERRecord`, `EventSERRecord` | Lifted | `event.SerRecord` | 13 |
| `protection.Configuration`, `ConfigurationFile`, `ConfigurationRegistry`, `ParsedSettings`, `ParsedSettingsFileHistory`, `SettingsFileMapping`, `VendorProjectFiles` | Corrected | `document.ConfigurationFile` revisions, `File`, `ParsedSetting` | 8 |
| `protection.SettingDefinition`, `SettingValue` | Lifted | `config.SettingDefinition`, `document.ParsedSetting` | 8 |
| `protection.SettingBasis` (+ registry) | Lifted | `document.Study` | 8 |
| `protection.Attachment`, `AttachmentFiles`, `AttachmentHistory` | Lifted | `document.Document` / `Revision` / `File` | 8 |
| `protection.ChangeRequest`, `ChangeRequestHistory` | Corrected | `work.WorkRequest` of type settings change | 8, 9 |
| `protection.LogicPage`, `LogicPageRevision`, `DrawingStatus` | Lifted | `document.Drawing`, `Revision`, `ref.DrawingStatus` | 8 |
| `protection.LogicDraft`, `LogicDraftItem`, `LogicLink`, `LogicPageShape`, `LogicEdgeWaypoint`, `NodeLayout`, `OperandLabelOverride`, `UserDrawingDefaults`, `ComponentPageAssignment` | Dropped | Editor state as a file on the drawing revision; user defaults are application settings | 8 |
| `workplan.WorkOrder`, `WorkOrderRegistry`, `WorkOrderApproval`, `WorkOrderDevice` | Lifted / Corrected | `work.WorkRequest`, `WorkflowTransition`, scope | 9 |
| `workplan.WorkOrderTask` | Corrected | `record.TestResult` + `TestReading` | 10 |
| `workplan.MaintenancePolicy`, `PRC005Category` | Data | `Program.ObligationRule` definitions | 9, 12 |
| `workplan.MaintenanceEvidence`, `PRC005Evidence` | Corrected | `record.TestSheet` + `compliance.EvidenceLink` | 10, 12 |
| `workflow.WorkflowInstance`, `WorkflowTransitionLog` (+ registry) | Lifted | `work.WorkflowInstance`, `WorkflowTransition` | 9 |
| `workflow.WorkflowNotificationRule` | Collapsed | Part of the workflow definition | 9 |
| `notify.NotificationType`, `TriggerDefinition`, `TriggerState`, `EscalationChain`, `EscalationStep` (+ registries) | Collapsed | `Program.NotificationType` definition | 9 |
| `notify.Notification`, `Subscription`, `DeliveryLog`, `DeliveryPreference`, `ResponsibilityAssignment` (+ registries) | Lifted / Corrected | `work.Notification`, `Subscription`, `NotificationDelivery`; responsibility is a grant | 9 |
| `notify.Dashboard*`, `DataSource*`, `EngineConfig` | Dropped | Report definitions and application configuration | 9 |
| `training.QualificationPath`, `QualificationPathModule`, `TrainingModule` | Lifted | `personnel.QualificationType`, `QualificationTypeModule`, `TrainingModule` | 11 |
| `training.PersonQualification` | Lifted | `personnel.PersonQualification` | 11 |
| `training.TrainingEvent`, `TrainingAttendance`, `OJTRecord` | Corrected | Record kinds | 10, 11 |
| `training.SuccessionGap` | Dropped | A report | 11 |
| `compliance.CIPPersonnelAccess` | Lifted | `personnel.Authorisation` | 11 |
| `compliance.CIPPersonnelTraining` | Corrected | Training record kind | 11 |
| `compliance.RegulatoryRequirement`, `CIPRequirement` | Lifted (dedup) | `compliance.Standard`, `StandardVersion`, `Requirement` | 12 |
| `core.AssetComplianceObligation` | Corrected | Rules + derived `ObligationInstance` | 12 |
| `compliance.CIPEvidencePackage` | Lifted | `compliance.EvidencePackage` + manifest | 12 |
| `compliance.CIPVulnAssessment` | Corrected | Record kind with findings | 12 |
| `compliance.CIPClassificationRegistry`, `CIPAssetClassification` | Corrected | `asset.Classification` | 4 |
| `dbo.TEV.Events`, `Channels`, `Samples`, `RawFiles` | Lifted | `event.Event`, `Channel`, `SampleBlock`, `File` | 13 |
| `dbo.TEV.RelayProfiles`, `EventSettings` | Data / Corrected | Template per model; review record | 13 |
| `dbo.TEV.Config`, `DisplayConfigs`, `NodeGraphs` | Dropped | Application configuration | 13 |
