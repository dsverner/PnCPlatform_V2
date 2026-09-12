-- W3 (PHASE-1-WORKFLOW W3 "two electromechanical model templates seeded by hand"; decisions #61, #104). Two per-model
-- settings templates for W4's fixture: CGE BDD15B (transformer differential) and Westinghouse CYL (distance). A
-- template is the existing mechanism, not a new one: a Transform.SettingsParse definition whose Effective version
-- carries config.SettingDefinition rows flagged IsCatalogueFact, bound to the model through ref.FirmwareVersion
-- (VersionString 'n/a' — an electromechanical relay has no firmware; the binding column is where the platform looks).
-- Every setting is then read as device.settings.<code> (compliance.vFactCatalogue).
--
-- Field sets come from the legacy dbo.SETTINGS.SET1 text profiled read-only on 2026-09-12 (dbRelayManagement_Legacy):
--   BDD15B family, 89 rows: WDG1 (78), WDG2 (78), SLOPE (86), HARMONIC RESTRAINT (86); the DEVICE label reads
--   "BDD15B 2.9-8.7 A SL=15/25/40%", which gives the tap range and the slope taps.
--   CYL, 26 rows: COMPENSATOR (18, also COMP 5 and a misspelling), INST (10); labels "CYL 1.4-10 OHMS", "CYL INST=4-16 A".
-- The final per-model field sets are W7's card to the owner; these two are the fixture's. Idempotent (fixed ids).
IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @author   UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';
IF NOT EXISTS (SELECT 1 FROM [personnel].[Actor] WHERE [ActorId] = @approver)
    INSERT [personnel].[Actor] ([ActorId], [ActorKind], [SystemName]) VALUES (@approver, N'System', N'Platform.SeedApprover');

-- the asset type of a protective relay (asset types are otherwise migration content, §14.2; this one the fixture needs)
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'ProtectiveRelay', @Name = N'Protective relay',
     @Description = N'A protection relay of any technology (W3 fixture; the migrated asset-type list arrives in W7)',
     @AssetClassCode = N'Secondary', @IsDevice = 1, @ActorId = @author;

-- manufacturers as party entities (kind Manufacturer), then ref.Manufacturer rows with fixed ids
DECLARE @cgeEntity UNIQUEIDENTIFIER, @wEntity UNIQUEIDENTIFIER;
SELECT @cgeEntity = [EntityId] FROM [party].[vEntity] WHERE [EntityKind] = N'Manufacturer' AND [Name] = N'Canadian General Electric';
IF @cgeEntity IS NULL EXEC [party].[Entity_Add] @Name = N'Canadian General Electric', @ShortName = N'CGE', @EntityKind = N'Manufacturer', @ActorId = @author, @EntityId = @cgeEntity OUTPUT;
SELECT @wEntity = [EntityId] FROM [party].[vEntity] WHERE [EntityKind] = N'Manufacturer' AND [Name] = N'Westinghouse';
IF @wEntity IS NULL EXEC [party].[Entity_Add] @Name = N'Westinghouse', @ShortName = N'Westinghouse', @EntityKind = N'Manufacturer', @ActorId = @author, @EntityId = @wEntity OUTPUT;

DECLARE @cge UNIQUEIDENTIFIER = 'A0000000-0000-4000-8000-00000000C6E1';
DECLARE @wh  UNIQUEIDENTIFIER = 'A0000000-0000-4000-8000-0000000000E5';
EXEC [ref].[Manufacturer_Upsert] @ManufacturerId = @cge, @EntityEntityId = @cgeEntity, @ShortCode = N'CGE', @ActorId = @author;
EXEC [ref].[Manufacturer_Upsert] @ManufacturerId = @wh,  @EntityEntityId = @wEntity,   @ShortCode = N'WH',  @ActorId = @author;

-- models
DECLARE @bdd UNIQUEIDENTIFIER = 'A0000000-0000-4000-8000-0000000BDD15';
DECLARE @cyl UNIQUEIDENTIFIER = 'A0000000-0000-4000-8000-000000000CE1';
EXEC [ref].[Model_Upsert] @ModelId = @bdd, @ManufacturerId = @cge, @ModelCode = N'BDD15B', @ModelName = N'CGE BDD15B transformer differential relay',
     @AssetTypeCode = N'ProtectiveRelay', @DeviceCategory = N'Relay', @Technology = N'Electromechanical', @ActorId = @author;
EXEC [ref].[Model_Upsert] @ModelId = @cyl, @ManufacturerId = @wh,  @ModelCode = N'CYL',    @ModelName = N'Westinghouse CYL distance relay',
     @AssetTypeCode = N'ProtectiveRelay', @DeviceCategory = N'Relay', @Technology = N'Electromechanical', @ActorId = @author;

-- templates: one Transform.SettingsParse definition per model, its settings on the version, approved, bound
DECLARE @def UNIQUEIDENTIFIER, @ver UNIQUEIDENTIFIER, @no INT, @r UNIQUEIDENTIFIER;

IF NOT EXISTS (SELECT 1 FROM [config].[Definition] WHERE [DefinitionKind] = N'Transform.SettingsParse' AND [DefinitionKey] = N'SETTINGS_TEXT_BDD15B' AND [IsDeleted] = 0)
BEGIN
    EXEC [config].[AddDefinition] @DefinitionKind = N'Transform.SettingsParse', @DefinitionKey = N'SETTINGS_TEXT_BDD15B',
         @Name = N'CGE BDD15B — text settings template', @Description = N'Settings the BDD15B carries, parsed from a name=value text file (legacy SET1 form); decision #61',
         @ActorId = @author, @EntityId = @def OUTPUT;
    EXEC [config].[AddDefinitionVersion] @DefinitionKey = N'SETTINGS_TEXT_BDD15B', @DefinitionKind = N'Transform.SettingsParse',
         @ChangeNote = N'W3 seed from the legacy SET1 profile', @ActorId = @author, @VersionRowId = @ver OUTPUT, @VersionNumber = @no OUTPUT;
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'WDG1', @Name = N'Winding 1 tap', @Category = N'Differential',
         @DataType = N'Decimal', @UnitCode = N'A', @MinValue = 2.9, @MaxValue = 8.7, @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'WDG2', @Name = N'Winding 2 tap', @Category = N'Differential',
         @DataType = N'Decimal', @UnitCode = N'A', @MinValue = 2.9, @MaxValue = 8.7, @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'SLOPE', @Name = N'Percentage slope', @Category = N'Differential',
         @DataType = N'Decimal', @UnitCode = N'%', @MinValue = 15, @MaxValue = 40, @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'HARMONIC_RESTRAINT', @Name = N'Harmonic restraint', @Category = N'Differential',
         @DataType = N'Decimal', @UnitCode = N'%', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;
    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @ver, @ActorId = @approver;
END
SELECT @def = [EntityId] FROM [config].[Definition] WHERE [DefinitionKind] = N'Transform.SettingsParse' AND [DefinitionKey] = N'SETTINGS_TEXT_BDD15B' AND [IsDeleted] = 0;
EXEC [ref].[FirmwareVersion_Upsert] @FirmwareVersionId = 'A0000000-0000-4000-8000-00000BDD15F1', @ModelId = @bdd, @VersionString = N'n/a',
     @ParseTransformDefinitionEntityId = @def, @ActorId = @author;

SET @def = NULL; SET @ver = NULL;
IF NOT EXISTS (SELECT 1 FROM [config].[Definition] WHERE [DefinitionKind] = N'Transform.SettingsParse' AND [DefinitionKey] = N'SETTINGS_TEXT_CYL' AND [IsDeleted] = 0)
BEGIN
    EXEC [config].[AddDefinition] @DefinitionKind = N'Transform.SettingsParse', @DefinitionKey = N'SETTINGS_TEXT_CYL',
         @Name = N'Westinghouse CYL — text settings template', @Description = N'Settings the CYL carries, parsed from a name=value text file (legacy SET1 form); decision #61',
         @ActorId = @author, @EntityId = @def OUTPUT;
    EXEC [config].[AddDefinitionVersion] @DefinitionKey = N'SETTINGS_TEXT_CYL', @DefinitionKind = N'Transform.SettingsParse',
         @ChangeNote = N'W3 seed from the legacy SET1 profile', @ActorId = @author, @VersionRowId = @ver OUTPUT, @VersionNumber = @no OUTPUT;
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'COMPENSATOR', @Name = N'Compensator reach', @Category = N'Distance',
         @DataType = N'Decimal', @UnitCode = N'Ω', @MinValue = 1.4, @MaxValue = 10, @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'INST', @Name = N'Instantaneous unit pickup', @Category = N'Distance',
         @DataType = N'Decimal', @UnitCode = N'A', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;
    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @ver, @ActorId = @approver;
END
SELECT @def = [EntityId] FROM [config].[Definition] WHERE [DefinitionKind] = N'Transform.SettingsParse' AND [DefinitionKey] = N'SETTINGS_TEXT_CYL' AND [IsDeleted] = 0;
EXEC [ref].[FirmwareVersion_Upsert] @FirmwareVersionId = 'A0000000-0000-4000-8000-000000CE1F01', @ModelId = @cyl, @VersionString = N'n/a',
     @ParseTransformDefinitionEntityId = @def, @ActorId = @author;
GO
