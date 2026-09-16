-- W8 (owner's W7 card E and W8 card B, decision #153): the first three SEL templates, seeded AS FOUND — every setting name
-- that the legacy SET1 text carries for the model, spelled as SEL's own software spells it (the owner: "they need to match the
-- format required by the SEL setting software such that no translation will be needed"). No units or limits yet — those
-- come from the manuals later; a name whose every value parsed as a number is Decimal, the rest Text. Generated from the
-- source on 2026-09-13 (docs/schema/migration/SET1 profile). The model row is the migrated one (SEL, the legacy label as its
-- code) when it exists, else created here with a fixed id so a fresh database carries the template before its load.
-- Idempotent: a template that exists is left alone.
IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @author   UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';
IF NOT EXISTS (SELECT 1 FROM [personnel].[Actor] WHERE [ActorId] = @approver)
    INSERT [personnel].[Actor] ([ActorId], [ActorKind], [SystemName]) VALUES (@approver, N'System', N'Platform.SeedApprover');
DECLARE @selEntity UNIQUEIDENTIFIER, @sel UNIQUEIDENTIFIER;
SELECT @sel = [ManufacturerId], @selEntity = [EntityEntityId] FROM [ref].[vManufacturer] WHERE [ShortCode] = N'SEL';
IF @sel IS NULL
BEGIN
    SELECT @selEntity = [EntityId] FROM [party].[vEntity] WHERE [EntityKind] = N'Manufacturer' AND [Name] = N'Schweitzer Engineering Laboratories';
    IF @selEntity IS NULL EXEC [party].[Entity_Add] @Name = N'Schweitzer Engineering Laboratories', @ShortName = N'SEL', @EntityKind = N'Manufacturer', @ActorId = @author, @EntityId = @selEntity OUTPUT;
    SET @sel = 'A0000000-0000-4000-8000-0000000005E1';
    EXEC [ref].[Manufacturer_Upsert] @ManufacturerId = @sel, @EntityEntityId = @selEntity, @ShortCode = N'SEL', @ActorId = @author;
END
DECLARE @def UNIQUEIDENTIFIER, @ver UNIQUEIDENTIFIER, @no INT, @r UNIQUEIDENTIFIER, @model UNIQUEIDENTIFIER;


-- ---- SEL-551: 73 names as found
SET @def = NULL; SET @ver = NULL; SET @model = NULL;
SELECT @model = [ModelId] FROM [ref].[vModel] WHERE [ManufacturerId] = @sel AND [ModelCode] = N'SEL-551';
IF @model IS NULL
BEGIN
    SET @model = 'A0000000-0000-4000-8000-00000000C551';
    EXEC [ref].[Model_Upsert] @ModelId = @model, @ManufacturerId = @sel, @ModelCode = N'SEL-551', @ModelName = N'SEL-551 overcurrent relay',
         @AssetTypeCode = N'ProtectiveRelay', @DeviceCategory = N'Relay', @Technology = N'Microprocessor', @ActorId = @author;
END
IF NOT EXISTS (SELECT 1 FROM [config].[Definition] WHERE [DefinitionKind] = N'Transform.SettingsParse' AND [DefinitionKey] = N'SETTINGS_TEXT_SEL_551' AND [IsDeleted] = 0)
BEGIN
    EXEC [config].[AddDefinition] @DefinitionKind = N'Transform.SettingsParse', @DefinitionKey = N'SETTINGS_TEXT_SEL_551',
         @Name = N'SEL-551 — text settings template (as found)', @Description = N'Every setting name the legacy SET1 text carries for the SEL-551, as SEL spells it; seeded as found on the owner''s ruling (W8 card B, #153); units and limits to follow',
         @ActorId = @author, @EntityId = @def OUTPUT;
    EXEC [config].[AddDefinitionVersion] @DefinitionKey = N'SETTINGS_TEXT_SEL_551', @DefinitionKind = N'Transform.SettingsParse',
         @ChangeNote = N'W8 seed as found from the legacy SET1 profile of 2026-09-13', @ActorId = @author, @VersionRowId = @ver OUTPUT, @VersionNumber = @no OUTPUT;
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'TID', @Name = N'TID', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 455 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'RID', @Name = N'RID', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 453 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'CTR', @Name = N'CTR', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 450 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'TDURD', @Name = N'TDURD', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 444 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'CTRN', @Name = N'CTRN', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 442 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'50P1P', @Name = N'50P1P', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 374 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'50G1P', @Name = N'50G1P', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 370 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'OUT1', @Name = N'OUT1', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 367 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'TR', @Name = N'TR', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 365 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'ULTR', @Name = N'ULTR', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 361 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'ER1', @Name = N'ER1', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 347 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'SV5', @Name = N'SV5', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 287 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'SV5PU', @Name = N'SV5PU', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 286 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51P1P', @Name = N'51P1P', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 242 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'SV5DO', @Name = N'SV5DO', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 225 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51P1C', @Name = N'51P1C', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 206 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51P1TD', @Name = N'51P1TD', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 206 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51P1RS', @Name = N'51P1RS', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 200 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'SER1', @Name = N'SER1', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 113 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'50P2P', @Name = N'50P2P', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 112 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51P1TC', @Name = N'51P1TC', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 107 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51N1P', @Name = N'51N1P', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 103 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51P2P', @Name = N'51P2P', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 101 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'50N1P', @Name = N'50N1P', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 85 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'50ABCP', @Name = N'50ABCP', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 84 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'50P3P', @Name = N'50P3P', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 69 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'50N2P', @Name = N'50N2P', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 69 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'50P4P', @Name = N'50P4P', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 66 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'50P5P', @Name = N'50P5P', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 66 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'50P6P', @Name = N'50P6P', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 66 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'50_P1P', @Name = N'50_P1P', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 56 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'DATE_F', @Name = N'DATE_F', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 49 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51N1C', @Name = N'51N1C', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 44 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'OUT2', @Name = N'OUT2', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 41 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'SV6', @Name = N'SV6', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 40 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'SV6PU', @Name = N'SV6PU', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 39 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'OUT3', @Name = N'OUT3', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 28 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51N1TD', @Name = N'51N1TD', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 27 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51N1RS', @Name = N'51N1RS', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 23 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51P2C', @Name = N'51P2C', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 21 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51P2TD', @Name = N'51P2TD', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 21 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51P2RS', @Name = N'51P2RS', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 21 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51G1P', @Name = N'51G1P', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 20 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51G1C', @Name = N'51G1C', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 20 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51G1TD', @Name = N'51G1TD', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 20 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51N1TC', @Name = N'51N1TC', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 17 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51G1TC', @Name = N'51G1TC', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 17 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51G1RS', @Name = N'51G1RS', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 16 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'SV6DO', @Name = N'SV6DO', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 13 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'50G2P', @Name = N'50G2P', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 8 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'OUT4', @Name = N'OUT4', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 7 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'DP1', @Name = N'DP1', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 6 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'DP1_1', @Name = N'DP1_1', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 6 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'DP1_0', @Name = N'DP1_0', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 6 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'DP2', @Name = N'DP2', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 6 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'SER', @Name = N'SER', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 5 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'CFD', @Name = N'CFD', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 4 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51Q1P', @Name = N'51Q1P', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 4 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51Q1C', @Name = N'51Q1C', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 4 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51Q1TD', @Name = N'51Q1TD', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 4 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51Q1RS', @Name = N'51Q1RS', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 4 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'ER', @Name = N'ER', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 4 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'79OI1', @Name = N'79OI1', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 2 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'NFREQ', @Name = N'NFREQ', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 2 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'PHROT', @Name = N'PHROT', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 2 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'79OI2', @Name = N'79OI2', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 1 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'79RSD', @Name = N'79RSD', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 1 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'SET1', @Name = N'SET1', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 1 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'RST1', @Name = N'RST1', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 1 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'SET2', @Name = N'SET2', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 1 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'OUT102', @Name = N'OUT102', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 1 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'OUT103', @Name = N'OUT103', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 1 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'ID', @Name = N'ID', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 1 rows
    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @ver, @ActorId = @approver;
END
SELECT @def = [EntityId] FROM [config].[Definition] WHERE [DefinitionKind] = N'Transform.SettingsParse' AND [DefinitionKey] = N'SETTINGS_TEXT_SEL_551' AND [IsDeleted] = 0;
IF NOT EXISTS (SELECT 1 FROM [ref].[vFirmwareVersion] WHERE [ModelId] = @model AND [ParseTransformDefinitionEntityId] = @def)
    EXEC [ref].[FirmwareVersion_Upsert] @FirmwareVersionId = 'A0000000-0000-4000-8000-0000000C551F', @ModelId = @model, @VersionString = N'n/a', @ParseTransformDefinitionEntityId = @def, @ActorId = @author;

-- ---- SEL-311C: 116 names as found
SET @def = NULL; SET @ver = NULL; SET @model = NULL;
SELECT @model = [ModelId] FROM [ref].[vModel] WHERE [ManufacturerId] = @sel AND [ModelCode] = N'SEL-311C';
IF @model IS NULL
BEGIN
    SET @model = 'A0000000-0000-4000-8000-00000000311C';
    EXEC [ref].[Model_Upsert] @ModelId = @model, @ManufacturerId = @sel, @ModelCode = N'SEL-311C', @ModelName = N'SEL-311C distance relay',
         @AssetTypeCode = N'ProtectiveRelay', @DeviceCategory = N'Relay', @Technology = N'Microprocessor', @ActorId = @author;
END
IF NOT EXISTS (SELECT 1 FROM [config].[Definition] WHERE [DefinitionKind] = N'Transform.SettingsParse' AND [DefinitionKey] = N'SETTINGS_TEXT_SEL_311C' AND [IsDeleted] = 0)
BEGIN
    EXEC [config].[AddDefinition] @DefinitionKind = N'Transform.SettingsParse', @DefinitionKey = N'SETTINGS_TEXT_SEL_311C',
         @Name = N'SEL-311C — text settings template (as found)', @Description = N'Every setting name the legacy SET1 text carries for the SEL-311C, as SEL spells it; seeded as found on the owner''s ruling (W8 card B, #153); units and limits to follow',
         @ActorId = @author, @EntityId = @def OUTPUT;
    EXEC [config].[AddDefinitionVersion] @DefinitionKey = N'SETTINGS_TEXT_SEL_311C', @DefinitionKind = N'Transform.SettingsParse',
         @ChangeNote = N'W8 seed as found from the legacy SET1 profile of 2026-09-13', @ActorId = @author, @VersionRowId = @ver OUTPUT, @VersionNumber = @no OUTPUT;
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z1MAG', @Name = N'Z1MAG', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 208 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'LL', @Name = N'LL', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 206 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z1ANG', @Name = N'Z1ANG', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 203 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'CTR', @Name = N'CTR', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 194 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'TID', @Name = N'TID', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 191 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'RID', @Name = N'RID', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 189 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'PTR', @Name = N'PTR', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 189 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'PTRS', @Name = N'PTRS', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 166 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z0MAG', @Name = N'Z0MAG', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 161 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z0ANG', @Name = N'Z0ANG', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 161 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'E21P', @Name = N'E21P', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 128 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'E21MG', @Name = N'E21MG', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 127 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'CTRP', @Name = N'CTRP', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 119 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z1MG', @Name = N'Z1MG', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 113 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z1P', @Name = N'Z1P', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 110 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z2MG', @Name = N'Z2MG', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 103 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z2P', @Name = N'Z2P', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 100 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'E21XG', @Name = N'E21XG', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 100 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'K0M1', @Name = N'K0M1', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 93 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'APP', @Name = N'APP', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 93 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'E50P', @Name = N'E50P', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 93 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'E50G', @Name = N'E50G', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 92 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'ELOP', @Name = N'ELOP', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 90 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'K0A1', @Name = N'K0A1', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 81 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'E50Q', @Name = N'E50Q', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 81 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'E51G', @Name = N'E51G', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 77 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'E32', @Name = N'E32', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 77 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'E51P', @Name = N'E51P', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 74 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'E51Q', @Name = N'E51Q', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 73 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'EOOS', @Name = N'EOOS', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 72 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z3P', @Name = N'Z3P', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 57 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z3MG', @Name = N'Z3MG', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 57 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z2D', @Name = N'Z2D', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 54 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'50G1P', @Name = N'50G1P', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 54 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'ELOAD', @Name = N'ELOAD', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 49 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'ZOMAG', @Name = N'ZOMAG', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 47 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'ZOANG', @Name = N'ZOANG', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 47 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z4P', @Name = N'Z4P', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 43 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z4MG', @Name = N'Z4MG', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 41 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51GP', @Name = N'51GP', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 31 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'ESOTF', @Name = N'ESOTF', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 27 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'50P1P', @Name = N'50P1P', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 24 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'EVOLT', @Name = N'EVOLT', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 24 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51GC', @Name = N'51GC', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 20 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51GTD', @Name = N'51GTD', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 18 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'ESV', @Name = N'ESV', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 17 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'51GRS', @Name = N'51GRS', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 15 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'EFLOC', @Name = N'EFLOC', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 14 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'79OI1', @Name = N'79OI1', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 12 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'79RSD', @Name = N'79RSD', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 12 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'59P', @Name = N'59P', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 12 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z2PD', @Name = N'Z2PD', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 12 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'ECOMM', @Name = N'ECOMM', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 11 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'79RSLD', @Name = N'79RSLD', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 11 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'K0M', @Name = N'K0M', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 11 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'K0A', @Name = N'K0A', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 11 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'TDURD', @Name = N'TDURD', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 10 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z2GD', @Name = N'Z2GD', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 10 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z2DG', @Name = N'Z2DG', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 8 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'27P', @Name = N'27P', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 8 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z2DP', @Name = N'Z2DP', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 7 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'27SP', @Name = N'27SP', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 7 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'TGR', @Name = N'TGR', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 7 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'NFREQ', @Name = N'NFREQ', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 7 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'PHROT', @Name = N'PHROT', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 7 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'DATE_F', @Name = N'DATE_F', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 7 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'FP_TO', @Name = N'FP_TO', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 7 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'SCROLD', @Name = N'SCROLD', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 7 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'LER', @Name = N'LER', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 7 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'PRE', @Name = N'PRE', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 7 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'DCLOP', @Name = N'DCLOP', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 7 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'DCHIP', @Name = N'DCHIP', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 7 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'IN101D', @Name = N'IN101D', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 7 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'IN102D', @Name = N'IN102D', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 7 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'IN103D', @Name = N'IN103D', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 7 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'IN104D', @Name = N'IN104D', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 7 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'IN105D', @Name = N'IN105D', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 7 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'IN106D', @Name = N'IN106D', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 7 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'EBMON', @Name = N'EBMON', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 7 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z3D', @Name = N'Z3D', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 6 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'TR', @Name = N'TR', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 6 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'CFD', @Name = N'CFD', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 6 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'ELAT', @Name = N'ELAT', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 6 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z1ZNG', @Name = N'Z1ZNG', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 5 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'E25', @Name = N'E25', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 5 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z4D', @Name = N'Z4D', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 4 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'E79', @Name = N'E79', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 4 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'KOM', @Name = N'KOM', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 3 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'KOA', @Name = N'KOA', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 3 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z4DG', @Name = N'Z4DG', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 3 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'50P2P', @Name = N'50P2P', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 3 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'ID', @Name = N'ID', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 3 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'50PP1', @Name = N'50PP1', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 3 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'DIR3', @Name = N'DIR3', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 3 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'50G2P', @Name = N'50G2P', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 2 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z2T', @Name = N'Z2T', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 2 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'52A', @Name = N'52A', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 2 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'ULCL', @Name = N'ULCL', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 2 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'79RI', @Name = N'79RI', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 2 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'79RIS', @Name = N'79RIS', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 2 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z4DP', @Name = N'Z4DP', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 2 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'59SP', @Name = N'59SP', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 2 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'K01M', @Name = N'K01M', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 2 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'K01A', @Name = N'K01A', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 2 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'ALL_OUTPUTS', @Name = N'ALL_OUTPUTS', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 2 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'3P27', @Name = N'3P27', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 1 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'79CLS', @Name = N'79CLS', @Category = N'As found', @DataType = N'Text', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 1 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z3PD', @Name = N'Z3PD', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 1 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z3DG', @Name = N'Z3DG', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 1 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'27B81P', @Name = N'27B81P', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 1 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'E81', @Name = N'E81', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 1 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'81D1P', @Name = N'81D1P', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 1 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'81D1D', @Name = N'81D1D', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 1 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'Z4PD', @Name = N'Z4PD', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 1 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'E21N', @Name = N'E21N', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 1 rows
    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = N'5RID', @Name = N'5RID', @Category = N'As found', @DataType = N'Decimal', @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;   -- 1 rows
    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @ver, @ActorId = @approver;
END
SELECT @def = [EntityId] FROM [config].[Definition] WHERE [DefinitionKind] = N'Transform.SettingsParse' AND [DefinitionKey] = N'SETTINGS_TEXT_SEL_311C' AND [IsDeleted] = 0;
IF NOT EXISTS (SELECT 1 FROM [ref].[vFirmwareVersion] WHERE [ModelId] = @model AND [ParseTransformDefinitionEntityId] = @def)
    EXEC [ref].[FirmwareVersion_Upsert] @FirmwareVersionId = 'A0000000-0000-4000-8000-0000000311CF', @ModelId = @model, @VersionString = N'n/a', @ParseTransformDefinitionEntityId = @def, @ActorId = @author;

-- ---- SEL-221F Z1-3=.125-64 OHMS: the model row only — its template is Seed_config_SettingsTemplate_SEL221F.sql (#168)
SET @model = NULL;
SELECT @model = [ModelId] FROM [ref].[vModel] WHERE [ManufacturerId] = @sel AND [ModelCode] = N'SEL-221F Z1-3=.125-64 OHMS';
IF @model IS NULL
    EXEC [ref].[Model_Upsert] @ModelId = 'A0000000-0000-4000-8000-00000000221F', @ManufacturerId = @sel, @ModelCode = N'SEL-221F Z1-3=.125-64 OHMS', @ModelName = N'SEL-221F distance relay (legacy label ''SEL-221F Z1-3=.125-64 OHMS'')',
         @AssetTypeCode = N'ProtectiveRelay', @DeviceCategory = N'Relay', @Technology = N'Microprocessor', @ActorId = @author;
GO

