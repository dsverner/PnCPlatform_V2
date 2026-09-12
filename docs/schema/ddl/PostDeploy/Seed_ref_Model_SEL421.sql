-- W4 fixture (PHASE-1-WORKFLOW W4: "one SEL-421, one CGE BDD15B, one Westinghouse CYL"). The microprocessor relay of
-- the fixture: manufacturer SEL as a party entity, model SEL-421 (Technology Microprocessor), a Transform.SettingsParse
-- definition SETTINGS_NATIVE_SEL421 with no settings (no parser for the native file exists yet — the configuration file
-- is stored, ParseStatus NotParsed, decision #113), and a firmware row 'n/a' bound to it so device.ApplyFirmware accepts
-- the device. The migrated model list arrives in W7 (§14.2); this row is the fixture's. Idempotent (fixed ids).
IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @author   UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';
DECLARE @selEntity UNIQUEIDENTIFIER;
SELECT @selEntity = [EntityId] FROM [party].[vEntity] WHERE [EntityKind] = N'Manufacturer' AND [Name] = N'Schweitzer Engineering Laboratories';
IF @selEntity IS NULL EXEC [party].[Entity_Add] @Name = N'Schweitzer Engineering Laboratories', @ShortName = N'SEL', @EntityKind = N'Manufacturer', @ActorId = @author, @EntityId = @selEntity OUTPUT;
DECLARE @sel UNIQUEIDENTIFIER = 'A0000000-0000-4000-8000-0000000005E1';
EXEC [ref].[Manufacturer_Upsert] @ManufacturerId = @sel, @EntityEntityId = @selEntity, @ShortCode = N'SEL', @ActorId = @author;
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'ProtectiveRelay', @Name = N'Protective relay',
     @Description = N'A protection relay of any technology (W3 fixture; the migrated asset-type list arrives in W7)',
     @AssetClassCode = N'Secondary', @IsDevice = 1, @ActorId = @author;
DECLARE @m421 UNIQUEIDENTIFIER = 'A0000000-0000-4000-8000-000000000421';
EXEC [ref].[Model_Upsert] @ModelId = @m421, @ManufacturerId = @sel, @ModelCode = N'SEL-421', @ModelName = N'SEL-421 protection, automation and control system',
     @AssetTypeCode = N'ProtectiveRelay', @DeviceCategory = N'Relay', @Technology = N'Microprocessor', @VendorSoftware = N'AcSELerator QuickSet', @ProjectFileExtension = N'.rdb', @ActorId = @author;
DECLARE @def UNIQUEIDENTIFIER, @ver UNIQUEIDENTIFIER, @no INT;
IF NOT EXISTS (SELECT 1 FROM [config].[Definition] WHERE [DefinitionKind] = N'Transform.SettingsParse' AND [DefinitionKey] = N'SETTINGS_NATIVE_SEL421' AND [IsDeleted] = 0)
BEGIN
    EXEC [config].[AddDefinition] @DefinitionKind = N'Transform.SettingsParse', @DefinitionKey = N'SETTINGS_NATIVE_SEL421',
         @Name = N'SEL-421 — native settings file (no parser yet)', @Description = N'Placeholder parse transform (W4 fixture): the native file is stored as a configuration-file revision with ParseStatus NotParsed; a reader arrives with the vendor-file work of a later wave',
         @ActorId = @author, @EntityId = @def OUTPUT;
    EXEC [config].[AddDefinitionVersion] @DefinitionKey = N'SETTINGS_NATIVE_SEL421', @DefinitionKind = N'Transform.SettingsParse',
         @ChangeNote = N'W4 fixture', @ActorId = @author, @VersionRowId = @ver OUTPUT, @VersionNumber = @no OUTPUT;
    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @ver, @ActorId = @approver;
END
SELECT @def = [EntityId] FROM [config].[Definition] WHERE [DefinitionKind] = N'Transform.SettingsParse' AND [DefinitionKey] = N'SETTINGS_NATIVE_SEL421' AND [IsDeleted] = 0;
EXEC [ref].[FirmwareVersion_Upsert] @FirmwareVersionId = 'A0000000-0000-4000-8000-000000421F01', @ModelId = @m421, @VersionString = N'n/a',
     @ParseTransformDefinitionEntityId = @def, @ActorId = @author;
GO
