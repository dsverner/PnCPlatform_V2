# Design step → project files

The 15-step order of SCHEMA-DESIGN.md, mapped to this project. Per step: the tables, the
hand-written objects, the seeds, and **every column whose type was defaulted** by
CONVENTIONS.md because the design gave none (owner may override at review). Items the design
names that are deliberately not built in this pass point at PROCEDURES.md.

Status legend: ✅ built and deployed · ⏳ pending wave · ⛔ deferred (reason given).

## Step 0–1 — conventions, universal base, temporal machinery ✅ (wave 1)

| Object | File | Notes |
|---|---|---|
| `personnel.Actor` | `personnel/Tables/Actor.sql` | AppendOnly, immutable; FKs to Person/User/Delegation added in step 11. `SystemName` added for `ActorKind = System` (the design says "a scheduled process, a migration run" without naming a column) |
| `audit.ActionLog` | `audit/Tables/ActionLog.sql` | `Detail` checked as JSON |
| `migration.Run`, `migration.Provenance` | `migration/Tables/*` | `Run.CleansingRuleVersionRowId` nullable for DEV/TRAIN loads (§14.1); `RunByActorId` is the design's `RunBy` |
| `config.ReadLoggedClass` | `config/Tables/ReadLoggedClass.sql` | design's `ChangedBy/ChangedAt` are the reference block's `ModifiedBy/ModifiedAt` |
| `ref.ActionKind`, `ref.SubjectKind`, `ref.AlternateKeyKind`, `ref.Unit` | `ref/Tables/*` | `SubjectKind` is a convention table (polymorphic references); `AlternateKeyKind` per §0.4 |
| `personnel.ResolveActor` | `personnel/Procedures/ResolveActor.sql` | SESSION_CONTEXT ActorId → (step 11: UPN → User → Delegation) → System actor per login |
| `audit.LogAction`, `audit.LogRead` | `audit/Procedures/*` | decision 65 read logging |
| `migration.CompleteRun` | `migration/Procedures/CompleteRun.sql` | |
| Generator | `tools/generate.py` | views, base procedures, `meta.fEntityExists`, `core.vAlternateKey` |

Defaulted types: `ActionLog.Detail` MAX · `Run.SourceSystem` NVARCHAR(50) (design gives 50) · `Provenance.Notes` MAX.
Seeds: `ref.ActionKind` (§1.1 list + `AssetMerge`/`AssetSplit` from §8.11), `ref.SubjectKind`, `ref.AlternateKeyKind`, `ref.Unit` (§4.9 codes; SI factors only), System actor.
`ref.AlternateKeyKind` also carries two migration kinds the design does not name (MIGRATION-PLAN.md, decided 2026-09-04): `LegacyRecordNumber` (`asset`, `Asset` — the legacy `OLD_NO`, a record number, not a plant tag; Q15) and `SapWorkOrder` (`work`, `WorkRequest`; Q10).

Flags: `Designation` alternate key seeded for the protection-function node (§7.3); §4.2 also lists it on assets — one kind, one schema; resolve at review.

## Step 2 — definition base ✅ (wave 1)

| Object | File | Notes |
|---|---|---|
| `config.Definition`, `DefinitionVersion` (+ registries) | `config/Tables/*` | `OwningRoleCode` FK → `security.Role` added step 11; `TestEvidenceRecordId` FK added step 10 |
| `config.DefinitionAppliesTo` | | ValidTime with own registry |
| `config.CharacteristicDefinition` | | `AllowedValuesDefinitionRowId` → an `Enumeration` definition version |
| `config.EnumerationValue` | | **implied** by §2.4/§3.1/§14.2; kind `CharacteristicSchema.Enumeration` added to the seed for the same reason |
| `config.TransformMapping` | | `TargetKind` CHECK (SettingDefinition, Characteristic, DocumentField) from §2.5's prose; `Sequence` added for ordered mappings |
| `config.SettingDefinition` (§8.5) | | `AnsiCode` FK → `ref.AnsiFunction` added step 7 |
| `config.TestPlanStep`, `TestPlanReading` (§10.2) | | **removed in V2 W0** — replaced by the procedure document and `process.ProcedureStep` (`docs/review/SCHEMA-REVIEW.md` §3, `docs/design/PROCEDURE-ENGINE.md` §4) |
| `config.AddDefinition`, `AddDefinitionVersion`, `AddCharacteristic`, `ApproveDefinitionVersion` | `config/Procedures/*` | lifted from the gate; fact validation joins in step 12 |
| `config.ResolveDefinition` + type `config.AppliesToFactList` | | §2.3 resolver: most-specific base, overlays after, tie → error 50040 |
| `ref.DefinitionKind`, `ref.AppliesToDimension` | `ref/Tables/*` | seeded from §2.1 and §2.3 |

Defaulted types: `Definition.DefinitionKey` 100 (design: 100) · `DefinitionVersion.ChangeNote` MAX · `TransformMapping.SourcePath` 400, `TargetKey` 100, `DefaultValue` 400 · `SettingDefinition.SettingCode` 100, `Category` 100, `DefaultValue` 400, `AnsiCode` NVARCHAR(10) · `TestPlanStep.Description` 400, `SubjectSelector` 200 (design: 200) · `TestPlanReading.ReadingKey` 100 · `EnumerationValue.ValueCode` 60.

`Program.SegregationRule` evaluation in `ApproveDefinitionVersion` is `security.CheckSegregation` (step 11, built 2026-09-04); `compliance.ValidateProgramFacts` (step 12, built).

## Step 3 — location tree ✅ (wave 2)

| Object | File | Notes |
|---|---|---|
| `ref.LocationNodeType`, `ref.LocationNodeTypeParent` | `ref/Tables/*` | seeded from §3.1; subtype lists attached by `Seed_config_Enumerations.sql` |
| `location.Node` (+ registry) | `location/Tables/Node.sql` | CHECKs: Region has no parent, others must. `Path`/`Depth` computed by `location.AddNode` / `MoveNode` (Path = parent's Path + parent EntityId + '/'; Region '/'); the generated `Node_Add` still accepts caller-supplied values for migration |
| `location.AddNode`, `location.MoveNode`, `location.AddAdjacency` | `location/Procedures/*` | PROCEDURES.md #4. Choice: segments under a linear node pair with consecutive touch points by `SiblingOrder` (the design says only that the procedure maintains from/to) |
| `location.Adjacency`, `location.Segment` | | `Segment` is an **extension** keyed by the node's `EntityId` (a node of type Segment with two extra columns, §3.3) |
| `location.Route`, `location.RouteStep` | | |
| `location.CustodyLocation` | | owner FK → `party.EntityRegistry` (the design writes "asset.EntityRegistry"; organisations are `party.Entity`, §4.5) |
| `location.NodeFunction` | | `SchemeEntityId` FK added step 7 |
| `location.AlternateKey` | | see flag below |
| Enumeration definitions `StationKind` (decision 86), `RacewayKind` (§3.1), `DevicePositionKind` (§5.7) | `PostDeploy/Seed_config_Enumerations.sql` | created through the definition procedures, approved by a second System actor (`…0002`, `Platform.SeedApprover`) |

Defaulted types: `Node.SubtypeCode` 40 · `Node.Notes` MAX · `CustodyLocation.Address` 400, `Notes` MAX · `NodeFunction.CascadeName` 200 (design: 200).

Flags:
- **AlternateKey identity.** §0.4 writes `EntityId` as "the thing the key names". The base rule (one current row per `EntityId`, decision 67 / generated views) would allow only one key per thing, so each key row has its own `EntityId` → `AlternateKeyRegistry` and `SubjectEntityId` names the node/asset. `core.vAlternateKey` exposes `SubjectEntityId`. Owner to confirm.
- `MeteringPosition`, `NetworkSwitchPosition` are in §3.1's code list "as device-position subtypes" and also appear as `DevicePositionKind` values in effect (`Meter`, `EthernetSwitch`); seeded as node-type codes per the list, with no allowed-parent pairs (none stated). Likely redundant with the subtype; owner to decide.
- `Designation` alternate-key kind seeded for the protection-function node (§7.3); §4.2 also lists it on assets.

Not built: Cascade import (PROCEDURES.md #25, MIGRATION-PLAN). #4 built 2026-09-04.

## Step 4 — assets, entities, ownership, classification ✅ (wave 2)

| Object | File | Notes |
|---|---|---|
| `ref.AssetClass` | `ref/Tables/AssetClass.sql` | seeded: Primary, Secondary, Hybrid, NonEnergised; `Rule` text null (vision text not quoted in the design) |
| `ref.AssetType` | | **no rows seeded**: §4.1 names the added types but not their class per type; all rows are migration (§14.2) |
| `ref.ClassificationKind` | | seeded: BesStatus, CipImpactRating, NpccBulkPowerSystem, NpccA10; allowed values not stated → null |
| `ref.Manufacturer`, `ref.Model` | | `ManufacturerId` / `ModelId` are `UNIQUEIDENTIFIER` keys supplied by the caller (design names ids without a type); unique on `ShortCode` and (`ManufacturerId`, `ModelCode`) |
| `ref.VoltageClass` | | no seed (NB Power's set at migration) |
| `asset.Asset` (+ registry) | `asset/Tables/Asset.sql` | |
| `asset.AssetComponent` | | unique filtered index: a child has one parent at a time; CHECK not self |
| `asset.Placement` (BiTemporal) | | CHECK one of node / custody; unique filtered index one `Installed` device per node; device/routed checks are PROCEDURES.md #5 |
| `asset.CharacteristicValue` | | §2.4 host = asset; `SourceRecordRowId` FK step 10 |
| `asset.OwnershipLink` | | `SubjectKind` CHECK (Node, Asset, Scheme, RouteStep); `Share` CHECK 0 < x ≤ 100 |
| `asset.Classification` (BiTemporal) | | `SubjectKind` CHECK (Node, Asset, Scheme); unique per (subject, kind) over the current period; Derived requires a derivation version |
| `asset.AlternateKey` | | as step 3 |
| `party.Entity`, `party.EntityAgreement` | `party/Tables/*` | agreement is shape only (§5.9); document/person FKs in steps 8 and 11 |

Defaulted types: `AssetClass.Rule` 400 · `AssetType.Description` MAX · `Model.DeviceCategory` 40, `FirmwareFamily` 60 (design: 60), `VendorSoftware` 100, `ProjectFileExtension` 20, `StatusAsOf` DATETIMEOFFSET · `Manufacturer.ShortCode` 20 · `Asset.Notes` MAX · `AssetComponent.ComponentRole` 60 (design: 60) · `Entity.ShortName` 40, `ExternalIdentifier` 100 (design: 100) · `EntityAgreement.ProductLine` 200, `Reference` 100.

| `asset.PlaceAsset` | `asset/Procedures/PlaceAsset.sql` | PROCEDURES.md #5, #6. Choices: override role `PlacementOverride` (seeded, `Seed_security_Role.sql`), Global or NodeSubtree grant, `@OverrideReason` required and logged; no category check when the model's `DeviceCategory` or the position's `SubtypeCode` is null; the two are compared ignoring case and underscores as a safety net; the standard vocabulary for `ref.Model.DeviceCategory` is the `DevicePositionKind` list (PascalCase), applied at load (owner decision 2026-09-05, MIGRATION-PLAN Q21); lifecycle `TimeSourceQuality` default 3 (manual) |

#5, #6 built 2026-09-04.

## Step 5 — devices ✅ (wave 2)

| Object | File | Notes |
|---|---|---|
| `device.Device` | `device/Tables/Device.sql` | **extension** of `asset.Asset` sharing `EntityId` (no own registry); `CurrentFirmwareVersionId` derived by PROCEDURES.md #8 |
| `ref.FirmwareVersion` | `ref/Tables/FirmwareVersion.sql` | `ParseTransformDefinitionEntityId` **nullable** (design shows FK without null): a firmware can be registered before its transform is authored; §5.3's rule is enforced at `FirmwareHistory` (PROCEDURES.md #7). `IcdDocumentEntityId` FK step 8 |
| `device.FirmwareHistory` | | `WorkRequestEntityId` FK step 9 |
| `device.LifecycleEvent` (AppendOnly) | | `TimeSourceQuality` CHECK 0–4; one of node / custody; work-request and record FKs steps 9, 10 |
| `device.Advisory`, `device.AdvisoryScope`, `device.AdvisoryDisposition` (BiTemporal) | | `DocumentEntityId` FK step 8; `WorkRequestEntityId` FK step 9 |
| `device.KnownDefect` | | `Status` has no value list in the design → no CHECK |
| Device-position kinds | enumeration `DevicePositionKind` (step 3 seed) | §5.7 list |

Defaulted types: `Device.PartNumber` 100 (design: 100), `HardwareRevision` 50 (design: 50) · `FirmwareVersion.VersionString` 100, `VendorReleaseReference` 100, `ReleasedAt` DATETIMEOFFSET · `Advisory.Severity` 20 (design: 20), `Summary`/`MitigationSummary` MAX · `AdvisoryDisposition.DeferralReason` 400 · `KnownDefect.VendorReference` 100, `Status` 20.

| `device.ApplyFirmware` | `device/Procedures/ApplyFirmware.sql` | PROCEDURES.md #7, #8. Choice: the re-validation is fired as an `audit.ActionLog` row of kind `FirmwareChanged` (seeded, `Seed_ref_ActionKind.sql`) for the obligation rule / workflow to consume; the firmware must belong to the asset's model when the asset names one |

| `device.fBaseline` | `device/Functions/fBaseline.sql` | PROCEDURES.md #29 (built 2026-09-04): the design's `vBaseline(@device, @validAt, @believedAt)` as an inline TVF (a view takes no parameters). Column set = union of §5.8 (in-service file, firmware, ports/services, open advisory dispositions, placement) and §6.8 (adds classification) — the two lists differ |

Not built: `party.EntityAgreement` procedures beyond the generated base. #7, #8, #29 built 2026-09-04.
## Step 6 — connections, ports, channels, network ✅ (wave 3)

| Object | File | Notes |
|---|---|---|
| `ref.PortKind`, `ref.ConnectionRealisation` | `ref/Tables/*` | seeded from §6.1 / §6.2 |
| `ref.Vlan`, `ref.MulticastAddress` | | "reference lists the Administrator maintains" — columns (`VlanId` 1–4094 / `MacAddress` 17, `Name`, `Description`) are this project's; no seed |
| `connection.Port` (+ registry) | `connection/Tables/Port.sql` | unique designator per asset over the current period; `TerminatesAtStudEntityId` → node registry (type Stud enforced by PROCEDURES.md #9) |
| `connection.NetworkPort` | | **extension** of Port sharing `EntityId`; lengths this project's (MAC 17, IP/mask/gateway 45, Speed 40) |
| `connection.Connection` (BiTemporal) | | `From/ToKind` CHECK per §6.2 list; realisation FK; `CK_Connection_NotSelf` added; endpoint/carrier rules per realisation are PROCEDURES.md #9; record/work FKs steps 10, 9 |
| `connection.PortService`, `SecurityPerimeter`, `SecurityPerimeterMember` | | lifted from `hardware.PortService`, `comms.ESP`, `comms.ESPDevice`; `LogicalPort` CHECK 0–65535 |
| `connection.Ied`, `LogicalDevice`, `LogicalNode`, `Dataset`, `DatasetMember`, `ControlBlock`, `ExtRef`, `DataAttribute` | | each ValidTime with `ConfigurationFileRevisionRowId` → `document.ConfigurationFile`; `Ied.DeviceEntityId` **nullable** until matched by IED name (§6.4); `ControlBlock.Kind` named `ControlBlockKind` (a bare `Kind` collides with the generator's polymorphic-pair rule) |
| `connection.ProtocolEndpoint`, `PointMap` | | shapes (§6.7); `ObjectGroup`/`Variation`/`PointIndex` INT; `ScaleFactor`/`Offset` DECIMAL(28,10) |
| `connection.vCyberAsset` | `connection/Views/vCyberAsset.sql` | **hand-written** (the design calls it generated; its shape is domain-specific): device × network port with firmware in force, services, perimeter membership, placement, classifications — current clocks only; the as-of `device.vBaseline` is PROCEDURES.md #29 |
| `connection.AlternateKey` | — | **not created**: no alternate-key kind lands in this schema (IedName is on the device asset) |

Defaulted types: `Port.PortDesignator` 50 (design: 50), `ElectricalGroupCode` 40 (design: 40), `Notes` MAX · `Connection.DrawingKey` 100 (design: 100), `Notes` MAX · `PortService.Protocol` 40, `ServiceName` 100, `Direction` 20, `BusinessJustification` 400 · `SecurityPerimeter.AccessPointDescription` 400 · SCL text columns: names 100, `LnClass`/`LnInst`/`Fc` 10, `Prefix` 40, `IntAddr`/`DatasetRef`/`DataSource` 200, `AppId` 20, `ConfRev` BIGINT, `VlanPriority` TINYINT · `ProtocolEndpoint.Address` 50 (design: 50), `ConfigDetail` MAX · `PointMap.PointName` 100, `Description` MAX.

Generator: new polymorphic-pair rule requires a non-empty prefix before `Kind` (`SubjectKind`/`SubjectEntityId`, never bare `Kind`/`EntityId`).

| `connection.Connect` | `connection/Procedures/Connect.sql` | PROCEDURES.md #9 (built 2026-09-04). **Open:** `Mms`, `Serial`, `Routable` have no endpoint rule in §6.2; no asset-type flag identifies a wire, conductor or channel asset, so the carrier is checked for existence only |

Not built: PROCEDURES.md #10, #11, #29, #30. `fEntityExists` now resolves `Connection`, `Port`, `NetworkPort`, `Dataset`, `SecurityPerimeter`.

## Step 7 — schemes, functions, conditions, operations ✅ (wave 3)

| Object | File | Notes |
|---|---|---|
| `ref.AnsiFunction` | `ref/Tables/AnsiFunction.sql` | predecessor-derived (62 rows) → migration; **no seed**. FK from `config.SettingDefinition.AnsiCode` added now (type NVARCHAR(10) already matched) |
| `ref.SchemeMemberRole`, `ref.ConditionKind` | | seeded from §7.2 / §7.5 lists (both marked extensible) |
| `scheme.Scheme` (+ registry) | `scheme/Tables/Scheme.sql` | scheme type = `Program.SchemeType` version RowId; `SystemDesignation` 10 (design: 10); FK from `location.NodeFunction.SchemeEntityId` added now |
| `scheme.SchemeProtects` | | unique per (scheme, asset, zone role) over the current period |
| `scheme.SchemeMember` (BiTemporal) | | `MemberKind` CHECK (ProtectionFunction, Asset, Connection, Channel); `IsInService` default 1 (the designed state) |
| `scheme.FunctionCapability`, `scheme.CommissionedFunction` | | unique (position, ANSI code) over the current period; `EnabledFromConfigurationFileRevisionRowId` → `document.ConfigurationFile` |
| `scheme.SchemeAction` | | MW / Mvar DECIMAL(18,4); unique sequence per scheme |
| `scheme.ProtectionCondition` (BiTemporal) | | `SubjectKind` CHECK (ProtectionFunction, Scheme, Connection, Device); compliance/record/work FKs steps 12, 10, 9 |
| `scheme.ProtectionOperation` (BiTemporal) | | `TimeSourceQuality` CHECK 0–4; `RecloseAttempts` TINYINT; record/compliance FKs steps 10, 12; snapshot + exception on raise are PROCEDURES.md #13 |
| `scheme.ProtectionOperationScheme` | | class **ValidTime** with own registry (design gives no class) |
| `scheme.ProtectionOperationSnapshot` (AppendOnly) | | `SubjectKind` CHECK (ConfigurationFileRevision, ProtectionCondition, SchemeMember); `SubjectRowId` is a fact version; `CapturedAt` added |
| `scheme.FaultRecord` | | precisions this project's: km DECIMAL(12,3), % DECIMAL(7,3), kA DECIMAL(12,4), Ω DECIMAL(18,6); `PatrolRecordEntityId` FK step 10 |
| `scheme.AlternateKey` | | `SchemeNumber` |

Defaulted types: `Scheme.Notes` MAX · `ProtectionCondition.ConditionValue` 200 (design: 200), `Reason` 400 · `ProtectionOperation.ElementsOperated` 400 (design: 400), `Notes` MAX · `FaultRecord.FaultType`/`LocationMethod` 40, `PhasesInvolved` 10 · `AnsiFunction.Category` 40, `DefaultLnClass` 10.

| `scheme.AddSchemeMember`, `scheme.vSchemeExpanded`, `scheme.RaiseProtectionOperation` | `scheme/Procedures/*`, `scheme/Views/vSchemeExpanded.sql` | PROCEDURES.md #12, #13 (built 2026-09-04). Choices: the operation's schemes are those in `SchemeProtects` for the primary asset plus `@SchemeEntityId`; the snapshot covers member rows as-of the event, conditions on the schemes / member functions / member connections / devices installed at the functions' positions, and configuration files in service on those devices; an Incorrect outcome requires `@MisoperationRuleVersionRowId` because `compliance.Exception` cites a rule version (§12.8); `ClockDueAt` is stored only when supplied (#23 partial) |

#12, #13 built 2026-09-04.

## Step 8 — documents, configuration files, rationale, drawings ✅ (wave 3)

| Object | File | Notes |
|---|---|---|
| `document.Document` (+ registry) | `document/Tables/Document.sql` | `ClassificationMarking` is an open list ("…") → NVARCHAR(40), no CHECK; document class = a `CharacteristicSchema.DocumentClass` definition entity |
| `document.Revision` (BiTemporal) | | four dated actors; `SupersedesRevisionRowId` self-FK; prepared ≠ approved is PROCEDURES.md #16 |
| `document.FileStore` | `document/Tables/FileStore.sql` | **FILESTREAM FileTable** (class `FileTable`, new): filegroup `FileStreamData` + file in `Storage/Filegroups.sql`; sqlproj `NonTransactedFileStreamAccess=Full`, `FilestreamDirectoryName=PnCPlatform`. **Published to VM01 without error**; smoke confirms `is_filetable = 1`. Generator emits a pass-through view only |
| `document.File` | | `Sha256` NOT NULL; `FileStreamId` → `FileStore.stream_id`, **nullable** for archive-tier bytes (§13.4 says the same row points elsewhere; no archive column is in the design) |
| `document.File_Write`, `document.fChildPathLocator` | `document/Procedures/File_Write.sql`, `document/Functions/fChildPathLocator.sql` | **rehearsal 2 follow-on (MIGRATION-PLAN.md Q14, decided 2026-09-04)**: bytes in → FileTable row (one root directory per revision, named by the revision `RowId`; the file under its own name) → generated `File_Add` with the `stream_id`, size and SHA-256 computed by `HASHBYTES`; a caller-supplied `@Sha256` must match (50131); duplicate name within a revision refused (50133). Hand-written, verb-first; `File_Add` stays the generated base. `fChildPathLocator` is the FileTable `path_locator` convention (three integers from a GUID under the parent) as a deterministic function so the procedure can call it with `NEWID()` |
| `config.StandardSettingEntry` (+ registry) | `config/Tables/StandardSettingEntry.sql` | **rehearsal 2 follow-on (MIGRATION-PLAN.md Q9, decided 2026-09-04)**: §8.6's rows of a `CharacteristicSchema.StandardSettings` version — (`SettingCode`, `ExpectedValue`, `Tolerance`, `Basis`) — as a `Versioned` table shaped like `config.SettingDefinition`; `UX_StandardSettingEntry_Code` unique per (version, code) while live. `Category` and `DisplayOrder` **added beyond the design's four columns** so the predecessor's `SettingTemplateEntry.Category` and an authoring order survive; `Notes` lands in `Basis`. The design gives no type for `Tolerance` (text such as `±5 %` or `±0.02`) → NVARCHAR(100), not parsed. Generated `v…`, `v…History`, `_Add`, `_Update`, `_SoftDelete` emitted with the generator's own emitters offline (no catalog reachable at the time); `deploy.py` regenerates and `check_generated.py` confirms on the next deploy |
| `document.RevisionLink` | | `LinkKind` CHECK (six kinds); `SubjectKind` CHECK per §8.2 |
| `document.ConfigurationFile` | | class **`Subclass`** (new): keyed by the revision's `RowId`, system-versioned, audit block, `_Add`/`_Update`/`_SoftDelete` by that key (CONVENTIONS.md). In-service invariant = `UX_ConfigurationFile_InService` (NativeSettings, `InServiceFrom` set, `InServiceTo` null, not deleted). **`IsInServiceUnapproved` is not a computed column** (needs `Revision.Status`): it is a column of the hand-written `document.vConfigurationFileStatus`. CHECK: only an SCD may lack a device. `DifferentialRecordEntityId` FK step 10 |
| `document.SettingsIssuePackageItem` | | ValidTime with own registry; cascade approval is PROCEDURES.md #15 |
| `document.ParsedSetting` | | typed values as §2.4 (`CK_…_OneValue`); unique per (revision, setting, group) over the current period |
| `document.Study`, `Rationale`, `Drawing` | | `Subclass` as above. `Rationale` stores the two resolved template versions (`SchemeTypeTemplate…`, `DeviceTemplate…`) per §2.2's rule; §8.8 lists no other columns. `Study.IsStale` stored, set by rule (PROCEDURES.md #28); `NetworkModelCaseEntityId` FK step 13 |
| `document.CharacteristicValue` | | host = **the revision's `RowId`** (`HostRevisionRowId`), chosen from §8.8 "a rationale revision's content"; `SourceRecordRowId` FK step 10 |
| `ref.DrawingStatus` | | "the predecessor's six states, lifted" — not named in the design → **no seed** (migration) |
| `document.AlternateKey` | | `DocumentNumber`, `LegacyReference`, `DrawingNumber` |
| FKs added to earlier tables now | `asset.Classification`, `device.Advisory`, `party.EntityAgreement`, `ref.FirmwareVersion` | the step-8 document references |

Defaulted types: `Document.Title` 200, `Description`/`Notes` MAX · `Revision.RevisionLabel` 20 (design: 20), `ChangeNote` MAX · `File.FileName` 260, `MimeType` 100, `SizeBytes` BIGINT · `StandardSettingEntry.SettingCode` 100, `ExpectedValue` 400, `Tolerance` 100, `Basis` 400, `Category` 100, `DisplayOrder` INT · `RevisionLink.DrawingKey` 100 (design: 100) · `ConfigurationFile.ParseStatus` 20, `ParseError` MAX · `ParsedSetting.RangeCheckNote` 400 · `Study.Software` 100, `SoftwareVersion` 40, `TopologyReference`/`ValidWhile` 400 (design: 400 for ValidWhile) · `Drawing` title-block texts 200, numbers 100, `Orientation`/`PaperSize` 20, `Scale` 40, `SheetNumber`/`SheetCount` INT.

| `document.ApproveRevision`, `document.ApproveSettingsIssuePackage`, `document.SetInService` | `document/Procedures/*` | PROCEDURES.md #16, #15, #14 (built 2026-09-04). Choices: approval and in-service changes are applied to the current row in place (system versioning keeps history) because subclasses, files, links and package items key the revision by `RowId`; "open package" = package revision Draft or Checked; preparer = `PreparedByActorId` else `CreatedBy`; `SetInService` writes no finding — the design names no category for in-service-while-unapproved (**open**) |

Not built: PROCEDURES.md #28.

## Step 9 — Work Requests, workflow, Cascade, notifications ✅ (wave 4)

| Object | File | Notes |
|---|---|---|
| `ref.Priority` | `ref/Tables/Priority.sql` | **no rows seeded**: the design states no priority values |
| `work.WorkRequest` (+ registry) | `work/Tables/WorkRequest.sql` | status, assignee and due are not stored (design); `PriorityCode` nullable because `ref.Priority` is empty; `ScopeKind` CHECK per §9.1; parent ≠ self |
| `work.WorkflowInstance`, `work.WorkflowTransition` (AppendOnly) | | **removed in V2 W0** — re-homed as `process.WorkflowInstance` / `process.WorkflowTransition` (`docs/design/PROCEDURE-ENGINE.md` §4); the interpreter (PROCEDURES.md #17) went with them |
| `work.CascadeWorkOrder` | | `CascadeNumber` held as a column with a unique filtered index (the design calls it an alternate key; `work.AlternateKey` names Work Requests) — flag |
| `work.WorkRequestCascadeLink` | | link table, cardinality open (design) |
| `work.Notification`, `work.Subscription`, `work.NotificationDelivery` (AppendOnly) | | `Notification.SubjectKind` → `ref.SubjectKind` (no list stated); recipient = actor or role (CHECK one present); `Subscription.ScopeFilter` JSON |
| `work.AlternateKey` | | subject → `WorkRequestRegistry` (`WorkRequestNumber`, `LegacyChangeRequestNumber`) |

Defaulted types: `WorkRequest.OutageApprovalReference` 100 · `WorkflowTransition.TransitionName` 100, `Reason` 400 · `CascadeWorkOrder.CascadeNumber` 100, `CascadeStatus` 40, `CascadeWorkOrderType` 40 · `Notification.Summary` 400, `Detail` MAX · `NotificationDelivery.DeliveryStatus` 40.

| `work.StartWorkflow`, `work.Transition`, `work.AssignPerson` | `work/Procedures/*` | PROCEDURES.md #17, #18 (built 2026-09-04). Choices: `Program.Workflow` payload `{"initial","states":[…],"final":[…],"transitions":[{"name","from","to","guard"?}]}` with guards as `fEvaluate` predicates on the subject; one open instance per (subject, workflow); `Program.QualificationRequirement` payload `{"requirements":[{"workType"|"*","deviceCategory"|"*","qualificationTypeCode","mode"}]}`, device category from an Asset-scoped request's model; assignment role `Assignee` seeded (`RoleKind` Assignment) |

Not built (PROCEDURES.md #33): notification engine; work type / workflow / notification-type definitions are data.

## Step 10 — records, test plans, sheets, results, instruments ✅ (wave 4)

| Object | File | Notes |
|---|---|---|
| `ref.RecordKind`, `ref.FindingCategory` | `ref/Tables/*` | seeded from §10.1 (+ `VulnerabilityAssessment`, `TrainingAttendance`) and §10.6 |
| `record.Record` (+ registry) | `record/Tables/Record.sql` | `SubjectKind` CHECK per §10.1 plus `Audit`, `SecurityPerimeter` (§12.8, §12.10); `SecondSubjectKind` may be `TrainingModule` (§11.6); `TimeSourceQuality` default 3 (manual) |
| `record.CharacteristicValue` | | §10.1 "record.CharacteristicValue rows (§2.4)": host = record |
| `record.Acceptance` (BiTemporal) | | decision 42 |
| `record.TestSheet`, `record.Finding`, `record.Readback`, `record.ConsistencyCheck` | | record subclasses = **extensions keyed by the record's EntityId** (as `device.Device` to `asset.Asset`), so generated `_Add` takes the record's id |
| `record.Instrument` | | asset extension; `CalibrationIntervalDays` is a characteristic per the design, not a column |
| `record.TestResult`, `record.TestReading` | | `NotPerformed` requires a reason (CHECK); one typed value per reading (CHECK) |
| `record.CommissioningPackageItem` | | acceptance cascade is PROCEDURES.md #20 |
| forward FKs closed | | `asset`/`document.CharacteristicValue.SourceRecordRowId`, `DefinitionVersion.TestEvidenceRecordId`, `Connection.VerifiedByRecordEntityId`, `LifecycleEvent.RecordEntityId`, `ConfigurationFile.DifferentialRecordEntityId`, `FaultRecord.PatrolRecordEntityId`, `ProtectionCondition.NotificationRecordEntityId`, `ProtectionOperation.ReviewRecordEntityId`; step 9's `WorkRequestEntityId` FKs on Placement, Connection, AdvisoryDisposition, FirmwareHistory, LifecycleEvent, ProtectionCondition |

Defaulted types: `Record.Summary` 1000 (design) · `TestSheet.AmbientConditions` 400 · `TestResult.NotPerformedReason` 400 · `Instrument.InstrumentKind` 40, `Range`/`Accuracy` 100 · `Finding.AsFoundValue`/`ExpectedValue` 400 (design).

| `record.RecordReadback`, `record.AcceptRecord`, `record.RunConsistencyCheck`, `record.RecordTestResult` | `record/Procedures/*` | PROCEDURES.md #19, #20, #21, #31 (built 2026-09-04). Choices: finding severities `AsFoundDrift` Major, `ConsistencyMismatch` Minor (the design states none); a finding is a `Finding` record whose second subject is the readback / check record; the consistency registry side is every current device with an `IedName` key; the package cascade does not re-run segregation per member; `IsPartial` = any required step with a current `NotPerformed` result, set in place |

Flags: `TestSheet.IsPartial` is "computed" in the design but needs `TestResult` rows — stored, set by `record.RecordTestResult`. No `record.AlternateKey`: no key kind lands on records.

## Step 11 — personnel, actors, security, qualifications, authorisations ✅ (wave 4)

| Object | File | Notes |
|---|---|---|
| `personnel.Person`, `security.User` | | `User` carries no credential or session (decision 160); `UserPrincipalName` unique among current rows; AD SID and employee/badge numbers are alternate keys |
| `personnel.Position`, `PositionHolder`, `security.Group`, `GroupMember` | | |
| `security.Role`, `Permission`, `RolePermission` | | `Role` seeded (vision §3.2 + predecessor names); **`RoleKind` null except Administrator = Positional** — the design does not classify the others; `Permission` seeded as 12 subject classes × 6 verbs (§11.3 paragraph; list is open-ended); **no `RolePermission` rows** (none stated) |
| `security.fHasPermission` | `security/Functions/fHasPermission.sql` | PROCEDURES.md #44 (built 2026-09-06, decision 237): the one access decision the API calls on every request; `Seed_security_RolePermission.sql` seeds Administrator = every permission, ReadOnly = every `.Read`, nothing else |
| `security.Grant` (BiTemporal) | | one scope column set per `ScopeKind` (CHECK) |
| `security.Delegation` (BiTemporal) | | from ≠ to; positional-only enforced by `security.Delegate` (`security/Procedures/Delegate.sql`, PROCEDURES.md #34, built 2026-09-04) |
| `personnel.QualificationType`, `TrainingModule`, `QualificationTypeModule` | | reference; rows are migration |
| `personnel.PersonQualification` | | `OjtHoursCompleted` derived by rule (PROCEDURES.md #32) |
| `security.SegregationOverride` (AppendOnly) | | `SubjectKind` → `ref.SubjectKind` (no list stated) |
| `ref.AuthorisationRightKind` (seeded §11.8), `personnel.Authorisation` (BiTemporal) | | scope kinds `NodeSubtree`, `DeviceCategory`, `SecurityPerimeter`, `DocumentClass`; `DeviceCategory` is a code so `ScopeCode` carries it (added column) |
| `personnel.AlternateKey`, `security.AlternateKey` | | |
| `personnel.Actor` FKs | `personnel/Tables/Actor.sql` | Person, ActingUser, Delegation FKs added |
| `personnel.ResolveActor` | `personnel/Procedures/ResolveActor.sql` | now: SESSION_CONTEXT ActorId → UPN → User → Person, delegation in force (Delegated) or `@SponsoredPersonEntityId` (Sponsored) → System actor per login |
| `config.Definition.OwningRoleCode` FK → `security.Role`; `party.EntityAgreement.ContactPersonEntityId` FK | | closed |
| project folders | `Database/Schemas.sql`, `Database/Roles.sql` | moved out of `Security/` so the `security` schema folder is unambiguous (case-insensitive file system) |

Defaulted types: `Person.FirstName`/`LastName` 100, `Email` 200, `Phone` 50 · `User.UserPrincipalName` 200, `DisabledReason` 400 · `Position.Title` 200 · `Grant.RevocationReason` 400, `ScopeDeviceCategory` 40 · `Delegation.Reason` 400 · `QualificationType.WorkCategory` 40, `RequiredOjtHours` DECIMAL(8,2), `RequiredExperienceYears` DECIMAL(4,1) · `TrainingModule.Category`/`DeliveryMethod`/`CipModuleCode` 40, `DurationHours` DECIMAL(6,2) · `QualificationTypeModule.MinimumPassScore` DECIMAL(5,2) · `SegregationOverride.ActionTaken` 100, `Reason` 400 · `Authorisation.AuthorisationBasis` 200 (design), `RevocationReason` 400.

| `security.CheckSegregation` + `PostDeploy/Seed_config_SegregationRules.sql` | `security/Procedures/CheckSegregation.sql` | PROCEDURES.md #1 (built 2026-09-04). Choices: payload `{"rules":[{"actionA","actionB","subjectKind" (or "*"),"mode"}]}`; WarnAndLog = proceed only with `@OverrideReason`, override appended with `ApprovedByActorId` null; Block = refuse unless another person approves (`@OverrideApprovedByActorId`) with a reason; the strictest matching rule wins; no matching rule → no constraint. Seeded rules: Prepare/Approve ConfigurationFileRevision, Author/Approve DefinitionVersion, Test/Accept Record — all WarnAndLog per vision §9.5 |

Assignment gating (#18) is `work.AssignPerson` (step 9).

## Step 12 — compliance objects and the fact catalogue ✅ (wave 4)

| Object | File | Notes |
|---|---|---|
| `compliance.Standard` (Reference), `StandardVersion` (BiTemporal), `Requirement` | | no seed (standards are migration/Administrator content, §14.2); `Requirement.SubjectKinds` is a JSON array |
| `compliance.RuleEvaluationRun` (AppendOnly) | | `Trigger` CHECK per §12.4 |
| `compliance.ObligationInstance` (BiTemporal), `ObligationInstanceFact` (AppendOnly) | | `SubjectKind` per §12.2; `Platform` needs no entity id (CHECK) |
| `compliance.EvidenceLink` (BiTemporal) | | cites `record.Record.RowId` (decision 47) |
| `compliance.Assertion` (BiTemporal) + `AssertionSupportingInstance` | | the child table for `SupportingInstanceRowIds` |
| `compliance.EvidencePackage` (Versioned) + `EvidencePackageManifest` (AppendOnly) | | the design's `PackageId` is the `EntityId`; immutability after approval is PROCEDURES.md #24 |
| `compliance.Audit`, `AuditRequest`, `Exception` (BiTemporal), `Interpretation` | | |
| `compliance.vFactCatalogue` | `compliance/Views/vFactCatalogue.sql` | hand-written view (decision 163): fixed facts `asset.voltage_class`, `device.model`, `device.technology`, `device.firmware`, `station.type`, `scheme.type`, `function.commissioned`, `station.classification.<kind>`, `line.classification.<kind>`; published `asset.template.<key>` / `device.template.<key>` (asset templates), `device.settings.<code>` (settings-parse transforms), `asset.formula.<key>` (formulas). **Not yet listed** (each needs a parameterised read the placeholder grammar cannot express, or a later wave): `scheme.members[role]`, `function.logical_node`, `device.connections[realisation]`, `device.advisories[open]`, `network.*` (`network.routable` = PROCEDURES.md #11), `channel.*`, `asset.owner_of_record`, `record.last`, `study.is_stale`, `person.*`, `entity.agreements`, `document.revision.current`, `platform.*` (wave 5 for backup/restore) — PROCEDURES.md #35 |
| interpreter | `compliance/Functions/f*.sql`, `Procedures/ValidateProgramFacts.sql`, `RunRulePreview.sql` | **grammar 1 (2026-09-05, FORMULA-GRAMMAR.md)**: `fEvalNode` (one recursive scalar function — T-SQL functions cannot be mutually recursive, so facts, calls, quantifiers and cadence live in it), `fEvaluate` / `fEvaluateWith` (Boolean wrappers: 1 / 0 / NULL = Unknown), `fFactRead` (typed reads incl. `scheme.members[role]`, `record.last[kind, accepted]`, `record.occurred_at`), `fUpgradeNode` (grammar 0 → 1 on read), `fCompare`, `fArith`, `fFold`, `fDurationSeconds`, unit helpers `fConvertUnit` / `fUnitProduct` / `fBaseUnitOf` / `fDecText` / `fTypedValue`; `vFactCatalogue` gains `Base`, `ReferenceKind`, `Parameters`; `RunRulePreview` returns `Status` Scoped / Indeterminate with the reason; `work.Transition` refuses an Unknown guard. Values travel between the functions as typed JSON (`{"k":"num","v":"2","u":"A","b":"Secondary"}`). `matches` / `decode` are Unknown here (no regular expressions on SQL Server 2022). `fSettingFactValue` reads the in-service settings file's parsed value for the device's active settings group (decision 121). Seeds: `ref.Unit` + `km`, `mi`, `min` |
| `config.AddDefinitionVersion` | | now validates Program payloads against the catalogue (PROCEDURES.md #3 done) |
| `compliance.vObligationDue` | — | **not built**: cadence lives in the rule payload, which the placeholder grammar does not define (PROCEDURES.md #22) |
| forward FKs closed | | `ProtectionCondition.RevertObligationInstanceEntityId`, `ProtectionOperation.ExceptionEntityId` |

Defaulted types: `Standard.Family` 40, `Subject` 200 · `StandardVersion.VersionLabel` 40 · `Requirement.RequirementNumber`/`SubRequirement` 40, `SubjectKinds` 400 · `AuditRequest.RequestReference` 100 · `Exception.ReportReference` 100, `ClosureBasis` 400.

Flags: `function.commissioned` returns the principal ANSI code at the node (§4.3). ~~A rule literal is assumed to be in the fact's definition unit~~ — withdrawn 2026-09-05: the grammar carries units (FORMULA-GRAMMAR.md §4.6, decision 192).

| catalogue facts (#35) | `compliance/Functions/fFactRead.sql`, `Views/vFactCatalogue.sql`, `Functions/fRuleSubjects.sql`, `personnel/Tables/TrainingModule.sql`, `compliance/Tables/ObligationInstance.sql` | PROCEDURES.md #35 (built 2026-09-06): one branch per relation-valued or parameterised fact, each reading the current rows valid at `@at`; empty relation = empty set, absent value = Unknown. `TrainingModule.EntityId` (default `NEWID()`, unique) so a `TrainingAttendance` record can cite its module as second subject; `ObligationInstance.SubjectKind` gains Node, Line, ProtectionFunction; `fRuleSubjects` gains the non-physical kinds and Platform (one subject, null id) |
| `compliance.RunRuleEffective`, `RederiveExceptionClocks`, `fRuleSubjects`, `fResolveRequirement`, `fObligationDue`, `fClockDue`, `vObligationDue` | `compliance/Procedures/*`, `Functions/*`, `Views/vObligationDue.sql` | PROCEDURES.md #22, #23 (built 2026-09-05). Choices: one cursor per run (subjects are few thousand at most; the per-subject work is procedural — add, revise, facts, work); period for an interval cadence is `[due − every, due]` with due from `fEvalNode`; Unknown anchor → `[EffectiveFrom, EffectiveFrom + every]` flagged in `ObligationInstanceFact`; `Exception` status instances are left untouched by the run; `ValidateProgramFacts` takes the definition kind so an obligation rule's requirement is checked at authoring (`AddDefinitionVersion` passes it) |
| `compliance.ApproveEvidencePackage`, triggers `compliance.trEvidencePackageFrozen` / `trEvidencePackageManifestFrozen` | `compliance/Procedures/ApproveEvidencePackage.sql`, `compliance/Triggers/*` | PROCEDURES.md #24 (built 2026-09-04). Choice: read-only after approval is enforced by AFTER triggers — the only way to stop the generated `_Update` / `_SoftDelete` / `_Append`; `PackageHash` = SHA-256 over `ItemKind:ItemRowId:FileSha256` in manifest order |

## Step 13 — network model, event tier, archive seam ✅ (wave 5)

| Object | File | Notes |
|---|---|---|
| `network.Layer`, `LayerNode`, `LayerNodeEndpoint`, `LayerBranch` (+ registries), `LayerBranchConstants` (AppendOnly), `Case` (snapshot: `LayerEntityId`, `Origin` Imported/Platform), `SourceEquivalent`, `MutualCoupling` | `network/Tables/*` | §13.1 rewritten 2026-09-05 (decisions 186–190, MIGRATION-PLAN Q27); `Bus` and `Branch` removed. `LayerNode.ExternalNumber` unique per layer; one primary endpoint per (node, line) (filtered unique); `AnchorKind`/`AnchorEntityId` is a poly pair — `ref.SubjectKind` rows `Structure`, `Layer`, `LayerNode`, `LayerBranch`, `Case` added |
| `network.AddLayerNodeEndpoint`, `network.ApplyReconciliation`, `network.vLayerBranchPath` | `network/Procedures/*`, `network/Views/vLayerBranchPath.sql` | endpoint verified against the scoped line's route, prior primary demoted; accepted candidates applied once (marked `applied_endpoint`); path derived over route steps, none while an end is unresolved |
| `network.AlternateKey` (+ registry) | | subject = layer node; kind `LayerNodeNumber` scoped to the layer (replaces the mis-seeded `BusNumber`) |
| `record.Record` CHECKs, `ref.RecordKind` `LayerReconciliation` / `LayerMatchCandidate`, `ref.DefinitionKind` `CharacteristicSchema.RecordTemplate`, `config.TransformMapping.TargetKind` `LayerField` | `record/Tables/Record.sql`, `PostDeploy/*` | reconciliation as records; a record kind's characteristic template has its own kind (choice) |
| `ref.ConductorType` | `ref/Tables/ConductorType.sql` | §13.2 conductor library; **each measure carries its own `…UnitCode`** because the design states no units; no seed (TLM at migration) |
| `network.LineSection` (+ registry) | | §13.2; "ConductorAssetTypeCode / ConductorTemplate" modelled as `ConductorTypeCode` → `ref.ConductorType` |
| `network.ConstantsRun` (AppendOnly) | | `Method` CHECK (CarsonSimplified, DeriSemlyen); `Status` no CHECK (no list stated) |
| `network.LineSectionConstants`, `LineSectionMutualConstants` (AppendOnly) | | per-km and total Z1/Z0 (R, X) and B1/B0; `InputHash`; mutual terms in the child |
| `event.Event`, `Channel`, `SampleBlock`, `SerRecord`, `PmuStream`, `PhasorBlock` (AppendOnly) | `event/Tables/*` | §13.3; data `ON [EventData]`, indexes `ON [EventIndex]`; `TimeSourceQuality` on `Event` and `SerRecord` |
| `archive.Manifest` (AppendOnly), `archive.Retention` (Reference) | `archive/Tables/*` | §13.4; `Retention` keyed by `RetentionCode`, naming exactly one of `RecordKindCode` / `EventKind` and the rule definition (`RuleDefinitionEntityId` → `config.DefinitionRegistry`); no seed (no values stated) |
| `document.Study.NetworkModelCaseEntityId` | `document/Tables/Study.sql` | forward FK closed |

Defaulted types: sequence parameters (`R1`…`B0`, `Z1R`…`X0m`, all constants) **DECIMAL(18,8)** rather than the (18,4) default, since per-unit impedances need the precision; `Bus.BusNumber` NVARCHAR(100); `Branch.CircuitId` 40; `LengthKm` DECIMAL(18,4); `Event.Format` / `Encoding` / `SourceFormat` 40; `TriggerDescription` 400; `Channel.Phase` 10; `SampleRateHz`, `NominalFrequencyHz`, `CtRatio`, `PtRatio`, `ReportingRateHz`, `EarthResistivityOhmM`, `FrequencyHz` DECIMAL(18,4); `Manifest.KeyRangeFrom/To` 100, `DestinationReference` 400; `RestoredToServer` 200.

Flags:
- `Bus.VoltageClassCode` nullable (not marked required).
- `Event.RawFileEntityId` nullable (an SER-derived event may have no raw file); `Event.IngestRunId` → `migration.Run` (the design names no separate ingest-run table).
- `PmuStream.ConfigurationFileRevisionRowId` nullable (shape only, decision 175).
- Archive seam: filegroups `EventData`, `EventIndex`, `BulkFiles`, `FileStreamData` exist from the first deployment; the generated views do **not** yet `UNION ALL` across a separate archive database (PROCEDURES.md #37).

Not built (PROCEDURES.md #36–#37, #40–#41): the line-constants engine run, archive move/verify, layer candidate generation, layer branch constants roll-up.

## Step 14 — predecessor mapping and data sources — no DDL; MIGRATION-PLAN.md
## Step 15 — backup, restore, integrity ✅ (wave 5)

### 15.6 The platform as a subject, and the lightning landing ✅ (wave 7, 2026-09-06)

| Object | File | Notes |
|---|---|---|
| `platform` schema; `platform.Release`, `platform.Deployment` (AppendOnly) | `platform/Tables/*` | generated `_Append` + views; `tools/record_release.py` appends both at the end of `deploy.py` (skip with `--no-record`); `<DacVersion>` in the sqlproj is the version (bump per release) |
| `event.LightningStrike` (AppendOnly, `EventData`) | `event/Tables/LightningStrike.sql` | unique (`SourceSystem`, `SourceStrikeId`); spatial index; `FeedRunId` → `migration.Run` |
| facts `platform.release`, `platform.baseline`, `operation.lightning_nearby[km, minutes]`, `operation.lightning_count[km, minutes]` | `compliance/Functions/fFactRead.sql`, `Views/vFactCatalogue.sql` | the correlation is `geography.STDistance` against the operation's places (placement node, route step nodes) over the spatial index — set-based in SQL Server on purpose; **C++ is earned by a measurement** (vision §7.3): if QA shows the correlation slow at the migrated event volume, a native correlation module behind an interop seam is the fallback, not the default |
| `ref.AssetType` `PlatformHost`; `ref.RecordKind` `PlatformDeployment`; `CharacteristicSchema.RecordTemplate` `PlatformDeployment` | `PostDeploy/Seed_ref_AssetType_Platform.sql`, `Seed_ref_RecordKind.sql`, `Seed_config_PlatformDeploymentTemplate.sql` | idempotent seeds |
| `record.Record` subject `Platform` | `record/Tables/Record.sql` | `SubjectEntityId` nullable only for that kind (`CK_Record_Subject`) |


| Object | File | Notes |
|---|---|---|
| `Program.BackupPolicy` | (definition kind, seeded in step 2) | §15.1: the policy is a definition payload; no table |
| `config.vEffectiveBackupPolicy` | `config/Views/vEffectiveBackupPolicy.sql` | the effective policy version's payload; SELECT to `agent_backup` and `app_execute` |
| `audit.BackupRun`, `audit.RestoreTest` (AppendOnly) | `audit/Tables/*` | §15.2; `BackupKind` and `BackupRun.Outcome` CHECKed per the design's lists; `RestoreTest.Outcome` no CHECK (no list stated) |
| `audit.RecordBackupRun`, `audit.RecordRestoreTest` | `audit/Procedures/*` | the SQL Agent job's write path (§15.3, decision 184); EXECUTE granted to `agent_backup`; `AchievedRpoMinutes` from the last succeeded Log backup, `AchievedRtoMinutes` from the test's own instants |
| `compliance.vFactCatalogue` platform facts | `compliance/Views/vFactCatalogue.sql`, `Functions/fFixedFactValue.sql` | §15.2's `platform.backup.last(kind)` spelled `platform.backup.last.Full` / `.Differential` / `.Log` / `.FilegroupFull`, and `platform.restore_test.last`; value = completion instant (ISO 8601) of the last succeeded run at or before `@at`; subject kind `Platform` |
| `config.ReadLoggedClass` seed | `PostDeploy/Seed_config_ReadLoggedClass.sql` | decision 65: `document.ConfigurationFile`, `compliance.EvidencePackage` on |

Note: `app_execute` holds schema-level EXECUTE on `audit`, so the application *could* call the record procedures; the design's boundary (the application never issues `BACKUP`) is about the backup itself, which no procedure here performs. `TargetRpoMinutes` / `TargetRtoMinutes` live in the policy payload, null until NB Power sets them (decision 185).

## Step 16 — the `process` schema ✅ (W3, 2026-09-12)

PROCEDURE-ENGINE.md §4, decision #100. Every table carries the CONVENTIONS block verbatim; domain columns are the
design's own lists. Types defaulted by the rules above: `BlockPath` NVARCHAR(400), `StepId` NVARCHAR(64) (the schema's
id pattern, max 64), `RoleAlias` / `RoleCode` / `State` / `Outcome` NVARCHAR(40), `CalleeKey` NVARCHAR(100), JSON
columns (`RequiresAst`, `Inputs`, `Produced`, `Draft`, `GuardEvaluation`, `StepMapping`) NVARCHAR(MAX) with an ISJSON
CHECK; `CaptureTimeQuality` TINYINT 0–4 like `TimeSourceQuality`.

| Object | File | Notes |
|---|---|---|
| `process.ProcedureStep` (+ `Ordinal`, `RequiresWitness`, `HasPrecondition`, `AdvancesWorkflowKey` / `AdvancesTransition`, `ProducesName` / `ProducesKind` beyond the design's list — what the projection can read off the document for free and screens will want) | `process/Tables/ProcedureStep.sql` | unique (`DefinitionVersionRowId`, `StepId`) among live rows |
| `process.ProcedureStepRole`, `ProcedureFactUse`, `ProcedureCall` | `process/Tables/*` | Versioned; rebuilt by `ProjectProcedureVersion` (prior rows soft-deleted) |
| `process.WorkflowInstance`, `ProcedureInstance`, `InstanceVersionSet`, `BlockInstance`, `StepInstance`, `HoldInstance`, `InstanceMigration` | `process/Tables/*` | Versioned; state sets CHECKed per §4; `BlockKind` includes `branch` (a parallel branch is its own activation); W4 writes them |
| `process.WorkflowTransition` | `process/Tables/WorkflowTransition.sql` | AppendOnly (`TransitionId` identity); `_Append` is the only write path |
| `process.fProcedureBlocks`, `fExpressionSites` | `process/Functions/*` | the block tree as rows (depth-first, `BlockPath`, `ScopePath` for the C1 check); the expression sites of one block |
| the five procedures | `process/Procedures/*` | PROCEDURES.md #45 |
| `ref.DefinitionKind` `Program.Procedure`; eleven `ref.RecordKind` rows; `ref.SubjectKind` `SettingsIssuePackage` (→ `document.Revision.RowId`), `ProcedureInstance`, `WorkflowInstance` | `PostDeploy/Seed_ref_*` | idempotent |
| `compliance.vFactCatalogue` engine facts; `work.outage_*` in `fFixedFactValue` | `compliance/Views/vFactCatalogue.sql`, `Functions/fFixedFactValue.sql` | decision #101 |
| `DRAWING_REVISION` placeholder definition; `Standard` workflow retired | `PostDeploy/Seed_config_Procedure_Placeholders.sql`, `Seed_config_Workflow_Standard.sql` | decision #102 |
| the two electromechanical templates | `PostDeploy/Seed_config_SettingsTemplates_Electromechanical.sql` | decision #104 |

Lesson: OPENJSON's `key` column is `Latin1_General_BIN2`; every comparison or concatenation with document text
carries `COLLATE DATABASE_DEFAULT`, or the procedure fails at run time with a collation conflict that the build does
not see.

## Step 17 — the interpreter's procedures ✅ (W4, 2026-09-12)

PROCEDURE-ENGINE.md §2–§6, decisions #106–#118. No new table: the `process` runtime tables of step 16 are written by
sixteen hand-written procedures (PROCEDURES.md #47), the `Engine` branches of `compliance.fFactRead` (#46) and the
seeds below. Schema changes: `record.Record` subject kinds and `document.ConfigurationFile.FileKind` widened (#108).

| Object | File | Notes |
|---|---|---|
| `process.StartWorkflow`, `StartProcedure`, `MaterialiseBlock`, `SetBlockState`, `SetStepState`, `OpenHold`, `ReleaseHold`, `CompleteInstance`, `Transition` | `process/Procedures/*` | the run; `StartProcedure` walks the call graph in a loop (a recursive CTE may carry neither TOP nor an outer join) |
| `process.ClaimStep`, `ReleaseStep`, `TakeOverStep`, `SaveDraft`, `WitnessStep` | `process/Procedures/*` | the claim (#55) and the witness (#114); the role is the grant's (`security.fGrantAsOf`) |
| `process.CommitStep`, `WriteConfigurationRevision`, `WriteEvidence`, `ParseSettingsText` | `process/Procedures/*` | §5 in one transaction; §5.1 by record kind; the text reader (#113) |
| `compliance.fFactRead` Engine branches | `compliance/Functions/fFactRead.sql` | #107 |
| `Seed_config_DocumentClasses.sql`, `Seed_config_SegregationRules.sql` v2, `Seed_ref_Model_SEL421.sql`, `Seed_config_Procedure_DrawingRevision.sql`, `Seed_config_ReadLoggedClass.sql` (`process.StepInstance`) | `PostDeploy/*` | #109, #110, #113, #112, #68 |

Lessons: an EXEC argument may not be a CASE expression (compute it into a variable first); an OUTPUT variable keeps
its value across a cursor's rows (reset it, or `Definition_Add` reuses the id).

## Step 18 — the parity read models ✅ (W6, 2026-09-12)

Hand-written views (CONVENTIONS.md: `<schema>/Views/<Name>.sql`, `GRANT SELECT … TO [app_execute]`; the generator leaves a
file whose first line is not its header alone). Decision #127: the dispatcher catalogues each and scopes it by its first
subject column in `Catalog.cs`'s preference order, so every view names that column on purpose.

| Object | File | Notes |
|---|---|---|
| `document.vSettingsRecord` | `document/Views/vSettingsRecord.sql` | the legacy grid: one row per designed configuration-file revision; `GridState` from the revision (#128); CDATE/VDATE (#129); subject `DeviceEntityId`; permission `ConfigurationFile.Read` by the `document.SettingsRecord` prefix |
| `document.vParsedSettingNamed` | `document/Views/vParsedSettingNamed.sql` | the setting display's rows with their definitions and one `DisplayValue`; subject `DeviceEntityId` |
| `work.vChangeRequestStatus` | `work/Views/vChangeRequestStatus.sql` | the change-request window: header, request state, the run, the two completion tracks from the branch rows and the child run's captures (#130); subject `WorkRequestEntityId` |
| `location.vFloc`, `location.vFlocScheme` | `location/Views/vFloc.sql`, `vFlocScheme.sql` | the Location / Protected Asset / Protection Function view (#57): one row per device position with the station (ParentEntityId hops — `Path` holds ancestors only, #94), panel, installed device, functions and schemes; browse by scheme through the second view; subject `NodeEntityId`; the installed asset is `InstalledAssetEntityId` so an empty position is not dropped by the scope predicate |
| `Seed_config_WorkTypes.sql` | `PostDeploy/*` | the four legacy action types as `Program.WorkType` (#131) |
| `asset.vPlacedAsset`, `location.vNodeTree` | `asset/Views/`, `location/Views/` | carried in W0 (`57b213c`) and recorded here for the first time: the assets at a node with names; the tree with `HasChildren` |

Lessons: a `RETURN` leaves only its batch (a guard before a `GO` guards nothing — W5's seed); a branch block is
materialised *Pending* when the run starts, so *Pending* is *Not Started*, not *In Progress*.

## Step 19 — migration (W7, 2026-09-12)

| Object | File | Notes |
|---|---|---|
| `process.LandMigratedInstance` | `process/Procedures/LandMigratedInstance.sql` | an open legacy change landed at COMPLETION with its two tracks (#56, #141); 50175–50177 |
| `@MigrationRunId` on `StartWorkflow`, `StartProcedure`, `MaterialiseBlock`, `WriteEvidence`, `WriteConfigurationRevision`, `Transition` | `process/Procedures/*` | passed through to the generated `_Add`s (#138); `WriteConfigurationRevision` also `@FileKindOverride`, `@Status` (#140); a migration run's `Transition` skips the person's role check |
| `Seed_ref_FindingCategory.sql` + `MigrationReconciliation` | `PostDeploy/*` | #142 |
| `Seed_config_ReadLoggedClass.sql` + `document.File` | `PostDeploy/*` | #144: every download a logged read |
| `docs/schema/migration/` (the toolkit, #137), `tools/cutover_diff.py` (#32) | — | MIGRATION-PLAN.md v2.0 |

Lessons: the schema smoke's obligation `run` needed the same one-second patience as `evaluate()` (VM01's clock 0.7 s
ahead of the laptop, #79); `document.SetInService` refuses a period that does not start after the prior one (50247), so
a chain whose revisions share a VDATE is dated one second apart, quality 2, flagged.

Performance (#145): a hand-written read model must not put an `OUTER APPLY … TOP (1)` against a generated current view —
the ROW_NUMBER inside the view is evaluated over the whole table per outer row. Read the base table with the filtered
index's own predicate (`[ValidTo] IS NULL AND [IsDeleted] = 0`; `[IsDeleted] = 0` for the process tables), and expect
the API to order and page the view in memory (`Api:MaterialiseBeforePaging`). New indexes: `IX_Record_SecondSubject`,
`IX_BlockInstance_Member`, `IX_NodeFunction_Node`.

## Reconciliation — every table the design names

Method: every `schema.Table` token in SCHEMA-DESIGN.md steps 0–15 and Appendix B, compared with `*/Tables/*.sql` in this project (2026-09-04, after wave 5).

- **Present:** every table the design defines for the new schema — 288 table files, including 107 registries; history tables are created by system versioning.
- **Named but deliberately no table**, each by the design's own text: `config.BackupPolicy` (§15.1, a definition), `document.DocumentClass` (§8.1, a definition kind), `document.SettingsIssuePackage` (§8.4, a revision whose class is the package; only `SettingsIssuePackageItem` is a table), `record.CommissioningPackage` (§10.7, a record of that kind; only `CommissioningPackageItem` is a table), `compliance.vFactCatalogue` (§12.3, a view), `connection.vCyberAsset` and `device.vBaseline` (§5.8, §6.8, views — the first built, the second PROCEDURES.md #29).
- **Predecessor names** (`core.*`, `protection.*`, `comms.*`, `events.*`, `hardware.*`, `notify.*`, `supplychain.*`, `training.*`, `workflow.*`, `workplan.*`, `compliance.CIP*`, `compliance.RegulatoryRequirement`, `config.AttributeKey`) appear in the design only as comparison rows and are not project tables by design (§14).
- **Catalog by class** (smoke output after wave 5): ValidTime 89, BiTemporal 17, Versioned 9, Subclass 4, Reference 37, AppendOnly 24, FileTable 1, Registry 107 — 288 tables; 811 generated objects; every `v%` view granted to `app_execute`; no table grant to `app_execute`.
