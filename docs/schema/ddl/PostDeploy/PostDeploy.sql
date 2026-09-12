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
:r .\Seed_config_PlatformDeploymentTemplate.sql
:r .\Seed_config_NotificationType.sql
:r .\Seed_config_Workflow_Standard.sql
:r .\Seed_location_Divisions.sql
