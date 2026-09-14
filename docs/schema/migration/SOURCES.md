# Migration sources as found on VM01 (10.10.70.25)

Generated 2026-09-04 by `catalogue_sources.py`, read-only, as `dev_pnc`. Row counts are the live copies'.

## `dbRelayManagement_Legacy` — the 1990s settings database (the one live import, decision 181)

Capture on `Z:\Reference\SqlBackup\dbRelayManagement_legacy.bak` dated 2026-04-22; restored on VM01. `dbo.Users` (32 rows, with passwords) is never migrated.

### `dbo.LOCATIONS` — 825 rows

| Column | Type | Nullable |
|---|---|---|
| `Location` | nchar(30) | no |
| `USERNAME` | nchar(20) | yes |

### `dbo.Relay Document Management` — 8,409 rows

| Column | Type | Nullable |
|---|---|---|
| `Change Request ID` | int | yes |
| `Relay ID Number` | nvarchar(5) | yes |
| `Status` | nvarchar(50) | yes |
| `Notes` | nvarchar | yes |
| `Date` | datetime | yes |

### `dbo.Setting Database Management` — 8,408 rows

| Column | Type | Nullable |
|---|---|---|
| `Change Request ID` | int | yes |
| `Relay ID Number` | nvarchar(5) | yes |
| `Status` | nvarchar(50) | yes |
| `Notes` | nvarchar | yes |
| `Date` | datetime | yes |

### `dbo.Setting Software Data` — 4 rows

| Column | Type | Nullable |
|---|---|---|
| `Relay Type` | nvarchar(50) | yes |
| `Firmware Version` | nvarchar(50) | yes |
| `Exe` | nvarchar(200) | yes |
| `FileType` | nvarchar(5) | yes |

### `dbo.Setting Software Management` — 8,408 rows

| Column | Type | Nullable |
|---|---|---|
| `Change Request ID` | int | yes |
| `Relay ID Number` | nvarchar(5) | yes |
| `Status` | nvarchar(50) | yes |
| `Notes` | nvarchar | yes |
| `Date` | datetime | yes |

### `dbo.SETTINGS` — 14,211 rows

| Column | Type | Nullable |
|---|---|---|
| `OLD_NO` | char(5) | no |
| `Change Request ID` | bigint | no |
| `LOCATION` | char(30) | no |
| `ASSET` | smallint | yes |
| `EQUIPMENT` | char(50) | no |
| `DEVICE` | char(125) | yes |
| `FUNCTIONS` | char(75) | yes |
| `SERIAL_NUMBER` | char(25) | yes |
| `SOFTWARE_VERSION` | char(50) | yes |
| `CT_MAIN1` | char(8) | yes |
| `PT_MAIN` | char(8) | yes |
| `SET1` | nvarchar | yes |
| `SETTINGS2` | nvarchar | yes |
| `DESC1` | char(4) | yes |
| `DESC2` | char(4) | yes |
| `DESC3` | char(4) | yes |
| `DESC4` | char(4) | yes |
| `CT_MAIN2` | char(8) | yes |
| `CT_MAIN3` | char(8) | yes |
| `CT_MAIN4` | char(8) | yes |
| `CT_AUX1` | char(8) | yes |
| `CT_AUX2` | char(8) | yes |
| `CT_AUX3` | char(8) | yes |
| `CT_AUX4` | char(8) | yes |
| `PT_AUX` | char(8) | yes |
| `REMARKS1` | char(25) | yes |
| `REMARKS2` | char(25) | yes |
| `REMARKS3` | char(25) | yes |
| `REMARKS4` | char(25) | yes |
| `CDATE` | datetime | yes |
| `VDATE` | datetime | yes |
| `REMARKS5` | nvarchar | yes |
| `CLASS` | char(2) | yes |
| `USE` | char(1) | yes |
| `RESPONSIBILITY` | char(15) | yes |
| `Bulk_Power_Element` | bit | yes |
| `Protection_Group` | char(1) | yes |
| `ELEMENT` | char(1) | yes |
| `MANUFACTURER` | char(50) | yes |
| `LINE_TYPE` | char(50) | yes |
| `NUMBER OF RELAYS` | int | yes |
| `VOLTAGE` | int | yes |
| `IDATE` | datetime | yes |

### `dbo.Settings Management` — 8,409 rows

| Column | Type | Nullable |
|---|---|---|
| `Change Request ID` | int | yes |
| `SAP Work Order Numer` | nvarchar(50) | yes |
| `Relay ID Number` | nvarchar(5) | yes |
| `Notes` | nvarchar | yes |
| `Date` | datetime | yes |
| `Type` | nvarchar(50) | yes |
| `Reqested By` | nvarchar(50) | yes |

### `dbo.sysdiagrams` — 0 rows

| Column | Type | Nullable |
|---|---|---|
| `name` | sysname(256) | no |
| `principal_id` | int | no |
| `diagram_id` | int | no |
| `version` | int | yes |
| `definition` | varbinary | yes |

### `dbo.Users` — 32 rows

| Column | Type | Nullable |
|---|---|---|
| `User` | nvarchar(50) | yes |
| `User Level` | smallint | yes |
| `Password` | nvarchar(50) | yes |

## `dbGridInfo` — TLM (transmission line model), a feed for step 13

629 tables of which 266 are live; the rest are dated `*Backup*` / `TLM_*` working copies and are excluded. Live tables with rows:

| Table | Rows |
|---|---|
| `dbo.AppSettings` | 12 |
| `dbo.ASPEN.ReferenceConstants` | 416,386 |
| `dbo.ASPEN.ReferenceMutuals` | 749,173 |
| `dbo.ASPEN_BranchCalculationPath` | 574 |
| `dbo.ASPEN_BranchCalculationResults` | 10 |
| `dbo.ASPEN_BranchMutualCalculationResults` | 6 |
| `dbo.ASPEN_BusEndpointCandidates` | 248 |
| `dbo.ASPEN_Buses` | 622 |
| `dbo.ASPEN_BusMapBindings` | 72 |
| `dbo.ASPEN_LineBranches` | 31 |
| `dbo.ASPEN_PhysicalMutualSections` | 9 |
| `dbo.ASPEN_ReconciliationSessions` | 1 |
| `dbo.Assets.AssetConnections` | 42 |
| `dbo.Assets.AssetConnectionTerminals` | 65 |
| `dbo.Assets.AssetTerminals` | 61,145 |
| `dbo.Assets.AssetTypes` | 8 |
| `dbo.Assets.DropLeadConnections` | 42 |
| `dbo.Assets.DropLeadConnectionSegments` | 85 |
| `dbo.Assets.ElectricalConnections` | 36 |
| `dbo.Assets.FunctionalLocations` | 3,715 |
| `dbo.Assets.Link.TLines_Structures` | 34,206 |
| `dbo.Assets.NetworkAssets` | 30,582 |
| `dbo.Assets.Properties` | 51 |
| `dbo.Assets.ROW.PhysicalShieldWireStructurePoints` | 44,295 |
| `dbo.Assets.StructureTypeLkp` | 6 |
| `dbo.Assets.TLines` | 255 |
| `dbo.Assets.TLines.AerialConductors` | 10 |
| `dbo.Assets.TLines.ASPENReferenceImpedance` | 16 |
| `dbo.Assets.TLines.BatchCalculationRuns` | 48 |
| `dbo.Assets.TLines.BranchTypeLkp` | 5 |
| `dbo.Assets.TLines.ConductorPrimatives` | 71 |
| `dbo.Assets.TLines.Conductors` | 31 |
| `dbo.Assets.TLines.CorridorRelationships` | 1,406 |
| `dbo.Assets.TLines.ElectricalJunctionType` | 3 |
| `dbo.Assets.TLines.GeometryViewOrientation` | 242 |
| `dbo.Assets.TLines.LineConstants` | 23,688 |
| `dbo.Assets.TLines.LineDirectionOverrides` | 7 |
| `dbo.Assets.TLines.LineSectionCalculations` | 35,434 |
| `dbo.Assets.TLines.LineSectionCircuits` | 629 |
| `dbo.Assets.TLines.LineSections` | 2,304 |
| `dbo.Assets.TLines.LineSectionSegments` | 30,872 |
| `dbo.Assets.TLines.LineSegmentCalculationInputs` | 30,793 |
| `dbo.Assets.TLines.LineSegments` | 31,976 |
| `dbo.Assets.TLines.LineSegmentWireConductors` | 120,082 |
| `dbo.Assets.TLines.MutualCouplingConstants` | 14,819 |
| `dbo.Assets.TLines.SegmentConstants` | 280,351 |
| `dbo.Assets.TLines.StructureTemplateSourceMap` | 6,881 |
| `dbo.Assets.TLines.StructureTypeAttachmentPoints` | 112,029 |
| `dbo.Assets.TLines.StructureTypeTemplates` | 36,757 |
| `dbo.Assets.TLines.TemplatePointSourceMap` | 20,643 |
| `dbo.Assets.TStructures` | 32,913 |
| `dbo.Assets.TStructures.AttachmentGeometryPoints` | 254,956 |
| `dbo.Assets.TStructures.AttachmentGeometrySets` | 84,695 |
| `dbo.Assets.TStructures.LineAttachmentGeometry` | 95,124 |
| `dbo.Assets.TStructures.LineAttachmentPoints` | 5 |
| `dbo.Assets.VoltageLevels` | 8 |
| `dbo.CableSchedules.Cables` | 3,893 |
| `dbo.CableSchedules.CableSpecifications` | 438 |
| `dbo.CableSchedules.ConductorGroupNamesPicklist` | 7 |
| `dbo.CableSchedules.Conductors` | 52,058 |
| `dbo.CableSchedules.JacketPicklist` | 21 |
| `dbo.Corporate.Areas` | 7 |
| `dbo.Corporate.Divisions` | 3 |
| `dbo.Corporate.Employees` | 71 |
| `dbo.Corporate.Employees.AccessPivot` | 33 |
| `dbo.Corporate.EntityAccesses` | 20 |
| `dbo.Corporate.JobPositions` | 14 |
| `dbo.Corporate.JobPositions.AccessPivot` | 42 |
| `dbo.Corporate.OrgChart` | 42 |
| `dbo.Debug.Messages` | 2 |
| `dbo.Documentation.Information.Tempates` | 7 |
| `dbo.Documentation.Overview` | 142 |
| `dbo.Documentation.Overview.ItemInformation` | 9 |
| `dbo.Import.AspenData` | 2,530 |
| `dbo.Import.GroundWires` | 6,467 |
| `dbo.Import.Mutuals` | 3,681 |
| `dbo.Information.Data.Metadata` | 15 |
| `dbo.PandC.ASPEN.FaultStudyLocation` | 2 |
| `dbo.PandC.ASPEN.FaultStudyProfile` | 1 |
| `dbo.PandC.Cable.CableUse` | 5 |
| `dbo.PandC.Cable.Jacket` | 12 |
| `dbo.PandC.ComplianceRequirement` | 1 |
| `dbo.PandC.ComplianceStandard` | 1 |
| `dbo.PandC.CoordinationGroup` | 1 |
| `dbo.PandC.DeviceCatalog` | 3 |
| `dbo.PandC.DeviceConfiguration` | 3 |
| `dbo.PandC.DeviceInstance` | 3 |
| `dbo.PandC.EquipmentType` | 11 |
| `dbo.PandC.FLocDivision` | 3 |
| `dbo.PandC.FLocEnclosure` | 11 |
| `dbo.PandC.FLocProperty` | 51 |
| `dbo.PandC.FLocPropertyDetail` | 9 |
| `dbo.PandC.FunctionalLocation` | 80 |
| `dbo.PandC.IECDeviceFunction` | 15 |
| `dbo.PandC.Manufacturers` | 2 |
| `dbo.PandC.RedundancySuffix` | 5 |
| `dbo.PandC.Security.Permission` | 40 |
| `dbo.PandC.Security.Role` | 7 |
| `dbo.PandC.Security.RolePermission` | 120 |
| `dbo.PandC.Security.Users` | 2 |
| `dbo.PandC.SignalType` | 32 |
| `dbo.PandC.SpecDefinition` | 33 |
| `dbo.PandC.TelecomChannel` | 1 |
| `dbo.PandC.TelecomMediumType` | 5 |
| `dbo.PandC.TerminalBlockTemplate` | 3 |
| `dbo.PandC.TerminalTemplate` | 9 |
| `dbo.PandC.Workflow.State` | 12 |
| `dbo.PandC.Workflow.StateMachine` | 3 |
| `dbo.PandC.Workflow.Transition` | 12 |
| `dbo.PandC.Workflow.WorkOrder` | 2 |
| `dbo.Picklist.FunctionalGroups` | 8 |
| `dbo.Picklist.SecurityGroups` | 5 |
| `dbo.Protection.ProtectionZoneType` | 7 |
| `dbo.Protection.StandardTemplate` | 1 |
| `dbo.Protection.TemplateRoleMap` | 39 |
| `dbo.Protection.TemplateTestCase` | 13 |
| `dbo.Protection.ValidationRule` | 37 |
| `dbo.SETTINGS` | 13,980 |
| `dbo.storage.root` | 29 |
| `dbo.tblAbnormalConditions` | 2 |
| `dbo.tblAssetDetail` | 4 |
| `dbo.tblAssetType` | 7 |
| `dbo.tblAuxInputs` | 54 |
| `dbo.tblCableuse` | 11 |
| `dbo.tblConfigurationPivot` | 100 |
| `dbo.tblDeviceConfigurations` | 100 |
| `dbo.tblDivisions` | 3 |
| `dbo.tblEquipment` | 17 |
| `dbo.tblFunctionalGroups` | 3 |
| `dbo.tblFunctionalLocations` | 9,035 |
| `dbo.tblGrouping` | 7 |
| `dbo.tblGroupRights` | 106 |
| `dbo.tblJacket` | 21 |
| `dbo.tblManufacturers` | 2 |
| `dbo.tblPandCConfigurationFiles` | 127 |
| `dbo.tblPandCFiles` | 15 |
| `dbo.tblPrimaryDevices` | 1 |
| `dbo.tblProperties` | 52 |
| `dbo.tblProtectedElements` | 61 |
| `dbo.tblProtectionZones` | 8 |
| `dbo.tblRedundantSystems` | 2 |
| `dbo.tblSecondaryDevices` | 51 |
| `dbo.tblSecurityGroups` | 5 |
| `dbo.tblSpecification` | 438 |
| `dbo.tblStatus` | 5 |
| `dbo.tblUsers` | 34 |
| `dbo.tblWorkRequests` | 15 |
| `dbo.TCable` | 3,899 |
| `dbo.TConductor` | 52,344 |
| `dbo.Test.Tasks` | 3 |
| `dbo.TEV.Config` | 2 |
| `dbo.TEV.RelayProfiles` | 13 |
| `dbo.TLM.ColumnUnitMetadata` | 145 |
| `dbo.TLM.UnitDefinitions` | 19 |
| `dbo.Weather.LightningStrikes` | 71,008 |
| `dbo.Weather.ServiceHeartbeat` | 1 |
| `dbo.WorkManagement.WorkRequestStepTable` | 5 |
| `dbo.WorkManagement.WorkRequestTable` | 1 |
| `Import.ASPENSourceFiles` | 562 |
| `Import.ASPENSOutAttachmentPoints` | 25,328 |
| `Import.ASPENSOutCircuits` | 6,293 |
| `Import.ASPENSOutConstructions` | 2,565 |
| `Import.ASPENTOutSections` | 2,207 |

### Join map and gotchas (profiled 2026-09-05 for `tlm_gridinfo.py`)

```
Assets.TLines.ID ← Link.TLines_Structures.TLineID (ordered by Sequence; 457 duplicate sequences, tie by ID)
                 ← LineSegments.TLineID, LineSections.TLineID, LineSectionCircuits.TLineID
                 → Assets.VoltageLevels.ID via VoltageLevelID (NominalKV is 92% null)
TStructures.ID   ← LineSegments.StartStructureID / EndStructureID   (Link.TLineSegments_Structures is EMPTY)
                 ← TStructures.LineAttachmentGeometry.StructureID + TLineID → AttachmentGeometrySets.SourceTemplateID (effective per-line template)
                 → StructureTypeTemplates.ID via StructureTemplateID (legacy shared template — often a transitional one)
LineSections.ID  ← LineSectionSegments.LineSectionID → LineSegments.ID
                 ← LineSectionCircuits.LineSectionID (CircuitSlot, TLineID)
                 ← LineSectionCalculations.LineSectionID → BatchCalculationRuns.ID
                 ← LineConstants.SectionID   (column is SectionID here)
LineSegments.ID  ← SegmentConstants.SegmentID (+ TemplateID; IsActive/IsDirty), MutualCouplingConstants.PrimarySegmentID (+ CorridorLineName text)
StructureTypeTemplates.ID ← StructureTypeAttachmentPoints.TemplateID, StructureTemplateSourceMap.TemplateID, TemplatePointSourceMap.TemplateID
```

- `Assets.TLines.Name` is the line number **without `L`** (`3004`; eight names end in `X`).
- `TStructures.IsActive` is NULL everywhere; `IsVirtual` False everywhere; `StructureType` 99.5% NULL and free text (does not use `Assets.StructureTypeLkp`).
- `StructureTypeTemplates`: `StructureClass = 'Normalized S.OUT'` (1,549, plain names such as `SCT Horizontal 1x3 2GW`) are the geometry templates; 34,298 bracketed names (`L3017S 8 [L3017 ROW]`, `… [094A44]`) are transitional ROW slices / ASPEN imports — evidence, not identities (TLM's `SOutTemplateNormalizationPlan.md`). In T-SQL match them with `Name LIKE '%[[]%]'`.
- Constants are **per mile** (`*_pm`); `LineSectionCalculations.Status` ∈ OK / Flagged / Failed / NoRef.
- `TLineEnds` is empty; `LineSegmentCalculationInputs` carries ρ and f only, no conductor.

### `ASPEN_*` — the TLM bus overlay (profiled 2026-09-05 for `aspen_layer.py`)

```
ASPEN_Buses.ID            ← ASPEN_BusMapBindings.BusID (0..n; SnapStructureID → TStructures.ID | SnapSegmentID → LineSegments.ID; TLineID scope; SnapMethod text; IsPrimary)
                          ← ASPEN_LineBranches.FromBusID / ToBusID (+ TLineID, CircuitID)
ASPEN_LineBranches.ID     ← ASPEN_BranchCalculationPath (SegmentID, SequenceNumber)   -- TLM stored the walk; the platform derives it
                          ← ASPEN_BranchCalculationResults (LengthMiles, Z1/Z0, From/ToSnapStructureID, IsCalculated)
                          ← ASPEN_PhysicalMutualSections / ASPEN_BranchMutualCalculationResults (percent overlaps)
ASPEN_ReconciliationSessions.ID ← ASPEN_BusEndpointCandidates (BusNumber, TLineID, StructureID, DistanceMeters, Confidence, ReviewStatus, ReasonText)
                                ← ASPEN_BusAnchorCandidates, ASPEN_BranchMatchCandidates, ASPEN_Staged* (all EMPTY)
ASPEN.ReferenceConstants / ASPEN.ReferenceMutuals (dotted names): ASPEN's own S.OUT answers per line and construction — benchmarks, not overlay
```
- Buses carry a label lat/lon of 0/0: not a location. Placement is only in bindings.
- `SnapMethod` values seen: `ManualStructureSnap`, `ReconCandidate:Endpoint`.
- Tombstones on the branch (Phase33/38/57/58): `BranchTerminals` and bus snap columns were dropped as second sources of truth.

## `dbPCPlatform_DEV` — the predecessor (schema comparison; seed lists §14.2; DEV/TRAIN population §14.1)

Full catalogue: `docs/reference/dbPCPlatform_DEV-schema.md`. Tables by schema:

| Schema | Tables | Rows |
|---|---|---|
| `comms` | 6 | 4 |
| `compliance` | 10 | 39 |
| `config` | 1 | 39 |
| `core` | 33 | 4,222 |
| `dbo` | 9 | 2,685 |
| `events` | 6 | 0 |
| `hardware` | 3 | 0 |
| `iec61850` | 15 | 336,502 |
| `notify` | 26 | 65 |
| `protection` | 48 | 3,202 |
| `supplychain` | 3 | 0 |
| `training` | 8 | 30 |
| `workflow` | 13 | 902 |
| `workplan` | 9 | 50 |

## `PNC_Dev`, `PNC_Training`, `PNC_Production`

Same predecessor schema as `dbPCPlatform_DEV` plus a few tables (209 tables). Corrected 2026-09-14 (W8): these are the environments of **pnc-platform** (`Z:\Repos\pnc-platform.git`, C++/CMake API + React) and of **Dev_Final** (`pilot/hardening-2026-06-12`, C++Builder console server + React), not of the legacy C++Builder settings program (that program's database is `dbRelayManagement_Legacy`, renamed `dbRelay` on the server by the owner on 2026-09-14). Training = Production; Dev holds the activity. Not migration sources — reference applications for UX and the function inventory (decision #158); listed so the question in the 2026-09-04 checkpoint is closed.
