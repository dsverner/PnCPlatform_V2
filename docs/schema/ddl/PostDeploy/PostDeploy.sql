/*
  Post-deployment script. Seeds reference rows the design states literally (SCHEMA-DESIGN
  step sections), idempotently (MERGE). Predecessor-derived lists (asset types, ANSI codes,
  models …) are migration content (§14.2), not seeds, and do not appear here.
  Each seed file is included with :r in step order.
*/
:r .\Seed_personnel_Actor_System.sql
:r .\Seed_ref_SubjectKind.sql
:r .\Seed_ref_DefinitionKind.sql
:r .\Seed_ref_AppliesToDimension.sql
:r .\Seed_ref_Unit.sql
:r .\Seed_ref_ActionKind.sql
:r .\Seed_ref_AlternateKeyKind.sql
:r .\Seed_ref_LocationNodeType.sql
:r .\Seed_ref_LocationNodeTypeParent.sql
:r .\Seed_ref_AssetClass.sql
:r .\Seed_ref_ClassificationKind.sql
:r .\Seed_config_SegregationRules.sql
:r .\Seed_config_DocumentClasses.sql
:r .\Seed_config_Enumerations.sql
:r .\Seed_ref_PortKind.sql
:r .\Seed_ref_ConnectionRealisation.sql
:r .\Seed_ref_SchemeMemberRole.sql
:r .\Seed_ref_ConditionKind.sql
:r .\Seed_ref_RecordKind.sql
:r .\Seed_ref_FindingCategory.sql
:r .\Seed_security_Role.sql
:r .\Seed_security_Permission.sql
:r .\Seed_security_RolePermission.sql
:r .\Seed_ref_AuthorisationRightKind.sql
:r .\Seed_config_ReadLoggedClass.sql
:r .\Seed_ref_AssetType_Platform.sql
:r .\Seed_ref_AssetType_Primary.sql
:r .\Seed_config_AssetTemplate_InstrumentTransformers.sql
:r .\Seed_ref_AssetType_Hybrid.sql
:r .\Seed_ref_VoltageClass.sql
:r .\Seed_config_PlatformDeploymentTemplate.sql
:r .\Seed_config_NotificationType.sql
:r .\Seed_config_Workflow_Standard.sql
:r .\Seed_config_Procedure_Placeholders.sql
:r .\Seed_config_SettingsTemplates_Electromechanical.sql
:r .\Seed_config_SettingsTemplates_SEL.sql
:r .\Seed_ref_AnsiFunction_Core.sql
:r .\Seed_config_SettingsTemplate_SEL221F.sql
:r .\Seed_config_RelayWord_SEL221F.sql
:r .\Seed_ref_Model_SEL421.sql
:r .\Seed_config_Procedure_DrawingRevision.sql
:r .\Seed_config_WorkTypes.sql
:r .\Seed_config_Procedure_InstrumentTransformerTests.sql
:r .\Seed_config_Workflow_InstrumentTransformerTests.sql
:r .\Seed_config_SchemeType_Legacy.sql
:r .\Seed_config_Screens.sql
:r .\Seed_config_CharacteristicSchema_SettingsRecord.sql
:r .\Seed_location_Divisions.sql
:r .\Seed_location_StationCodes.sql
:r .\Seed_location_BuildingCodes.sql
:r .\Seed_scheme_FunctionCapability_SEL221F.sql
:r .\Seed_config_AssetTemplate_SEL221F.sql
:r .\Seed_scheme_RepointCommissionedFunctions.sql
:r .\Seed_config_AssetTemplate_Line.sql   -- #219: the line's impedance and length as characteristics of the line asset
:r .\Seed_config_Rationale_SEL221F.sql   -- #219: the SEL-221F line-distance rationale template, one section per element
:r .\Seed_asset_PlacementOccupancy.sql
:r .\Seed_asset_InstrumentTransformersFromLegacy.sql
:r .\Seed_scheme_AnalogInputs.sql
:r .\Seed_asset_InstrumentWindings.sql
:r .\Seed_compliance_Standards_NB.sql
:r .\Seed_compliance_Standards_NPCC.sql
:r .\Seed_config_Formulas_PRC023.sql
:r .\Seed_config_ClassificationDerivations.sql
:r .\Seed_config_ObligationRules.sql
