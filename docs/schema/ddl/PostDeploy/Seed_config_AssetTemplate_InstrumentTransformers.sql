-- #201 (2026-09-19): the nameplate of an instrument transformer, as two CharacteristicSchema.AssetTemplate definitions —
-- CT_Template (current transformers, auxiliary CTs, metering units) and VT_Template (voltage transformers, auxiliary VTs,
-- CVTs, CCPDs). Bound to the asset TYPES through ref.AssetType.DefaultTemplateDefinitionEntityId (set in
-- Seed_ref_AssetType_Hybrid, which runs after this in name order), not to a model: a CT's nameplate is the CT's, whatever
-- its make. The keys a relay setting is expressed against come first: RatioInUse is what the record's Analog inputs tab
-- checks CTR / PTR / SPTR against (scheme.vSchemeSource parses "1200:5" to 240). No migration rule writes these: the
-- legacy record's CT/PT strings stay the record's declared ratios (its SETTINGS_RECORD characteristics) — no transformer is
-- invented from a string (the never-fabricate rule).
-- Idempotent: adds the version only when no Effective version carries this change note.
IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @author UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001', @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';
DECLARE @e UNIQUEIDENTIFIER, @v UNIQUEIDENTIFIER, @no INT, @note NVARCHAR(200) = N'seed (#201): the instrument-transformer nameplate';

-- ---------------------------------------------------------------- CT_Template
SELECT @e = [EntityId] FROM [config].[Definition] WHERE [DefinitionKind] = N'CharacteristicSchema.AssetTemplate' AND [DefinitionKey] = N'CT_Template' AND [IsDeleted] = 0;
IF @e IS NULL
    EXEC [config].[AddDefinition] @DefinitionKind = N'CharacteristicSchema.AssetTemplate', @DefinitionKey = N'CT_Template',
         @Name = N'Current transformer nameplate', @Description = N'What is true of a current transformer as equipment: its ratio taps and the one in use, its cores, accuracy class, burden, knee point and polarity marking (#201).',
         @ActorId = @author, @EntityId = @e OUTPUT;
IF NOT EXISTS (SELECT 1 FROM [config].[vDefinitionVersion] WHERE [DefinitionEntityId] = @e AND [Status] = N'Effective' AND [ChangeNote] = @note)
BEGIN
    EXEC [config].[AddDefinitionVersion] @DefinitionKey = N'CT_Template', @DefinitionKind = N'CharacteristicSchema.AssetTemplate', @ChangeNote = @note, @ActorId = @author, @VersionRowId = @v OUTPUT, @VersionNumber = @no OUTPUT;
    EXEC [config].[CharacteristicDefinition_Add] @DefinitionVersionRowId = @v, @CharacteristicKey = N'RatioInUse',       @Name = N'Ratio in use',        @DataType = N'Text',    @DisplayGroup = N'Ratio',       @DisplayOrder = 10, @Description = N'The tap connected, primary:secondary, e.g. 1200:5 — the relay''s CTR is checked against it', @ActorId = @author;
    EXEC [config].[CharacteristicDefinition_Add] @DefinitionVersionRowId = @v, @CharacteristicKey = N'RatioTaps',        @Name = N'Ratio taps available', @DataType = N'Text',   @DisplayGroup = N'Ratio',       @DisplayOrder = 20, @Description = N'Every tap the winding offers, e.g. 1200:5, 600:5, 300:5', @ActorId = @author;
    EXEC [config].[CharacteristicDefinition_Add] @DefinitionVersionRowId = @v, @CharacteristicKey = N'Cores',            @Name = N'Cores',               @DataType = N'Integer', @DisplayGroup = N'Ratio',       @DisplayOrder = 30, @Description = N'The number of secondary cores (one per protection or metering circuit it feeds)', @ActorId = @author;
    EXEC [config].[CharacteristicDefinition_Add] @DefinitionVersionRowId = @v, @CharacteristicKey = N'RatedSecondary',   @Name = N'Rated secondary',     @DataType = N'Text',    @DisplayGroup = N'Nameplate',   @DisplayOrder = 40, @Description = N'5 A or 1 A', @ActorId = @author;
    EXEC [config].[CharacteristicDefinition_Add] @DefinitionVersionRowId = @v, @CharacteristicKey = N'AccuracyClass',    @Name = N'Accuracy class',      @DataType = N'Text',    @DisplayGroup = N'Nameplate',   @DisplayOrder = 50, @Description = N'The protection or metering class as marked, e.g. C800, 10P20, 0.3B-1.8', @ActorId = @author;
    EXEC [config].[CharacteristicDefinition_Add] @DefinitionVersionRowId = @v, @CharacteristicKey = N'RatedBurden',      @Name = N'Rated burden',        @DataType = N'Text',    @DisplayGroup = N'Nameplate',   @DisplayOrder = 60, @Description = N'As marked, e.g. 2.0 Ω / B-2.0 / 30 VA', @ActorId = @author;
    EXEC [config].[CharacteristicDefinition_Add] @DefinitionVersionRowId = @v, @CharacteristicKey = N'KneePointVoltage', @Name = N'Knee point voltage',  @DataType = N'Decimal', @UnitCode = N'V', @DisplayGroup = N'Performance', @DisplayOrder = 70, @Description = N'From the excitation (saturation) curve — the test record when one exists (#202), else the nameplate', @ActorId = @author;
    EXEC [config].[CharacteristicDefinition_Add] @DefinitionVersionRowId = @v, @CharacteristicKey = N'PolarityMark',     @Name = N'Polarity marking',    @DataType = N'Text',    @DisplayGroup = N'Performance', @DisplayOrder = 80, @Description = N'The marked polarity terminals (H1/X1 …) and which way faces the protected element', @ActorId = @author;
    EXEC [config].[CharacteristicDefinition_Add] @DefinitionVersionRowId = @v, @CharacteristicKey = N'Nameplate',        @Name = N'Nameplate, other',    @DataType = N'Text',    @DisplayGroup = N'Nameplate',   @DisplayOrder = 90, @Description = N'Anything else the nameplate says: type, BIL, thermal rating factor, year', @ActorId = @author;
    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @v, @ActorId = @approver;
END

-- ---------------------------------------------------------------- VT_Template
SET @e = NULL;   -- a SELECT that finds no row leaves the variable as it was (the CT's) - found on the first deploy
SELECT @e = [EntityId] FROM [config].[Definition] WHERE [DefinitionKind] = N'CharacteristicSchema.AssetTemplate' AND [DefinitionKey] = N'VT_Template' AND [IsDeleted] = 0;
IF @e IS NULL
    EXEC [config].[AddDefinition] @DefinitionKind = N'CharacteristicSchema.AssetTemplate', @DefinitionKey = N'VT_Template',
         @Name = N'Voltage transformer nameplate', @Description = N'What is true of a voltage transformer (inductive, CVT or CCPD) as equipment: its ratio, secondary windings, accuracy class, burden and polarity marking (#201).',
         @ActorId = @author, @EntityId = @e OUTPUT;
IF NOT EXISTS (SELECT 1 FROM [config].[vDefinitionVersion] WHERE [DefinitionEntityId] = @e AND [Status] = N'Effective' AND [ChangeNote] = @note)
BEGIN
    EXEC [config].[AddDefinitionVersion] @DefinitionKey = N'VT_Template', @DefinitionKind = N'CharacteristicSchema.AssetTemplate', @ChangeNote = @note, @ActorId = @author, @VersionRowId = @v OUTPUT, @VersionNumber = @no OUTPUT;
    EXEC [config].[CharacteristicDefinition_Add] @DefinitionVersionRowId = @v, @CharacteristicKey = N'RatioInUse',     @Name = N'Ratio in use',           @DataType = N'Text',    @DisplayGroup = N'Ratio',       @DisplayOrder = 10, @Description = N'The winding connected, primary:secondary, e.g. 2000:1 or 132800:115 — the relay''s PTR / SPTR is checked against it', @ActorId = @author;
    EXEC [config].[CharacteristicDefinition_Add] @DefinitionVersionRowId = @v, @CharacteristicKey = N'RatioTaps',      @Name = N'Ratios available',       @DataType = N'Text',    @DisplayGroup = N'Ratio',       @DisplayOrder = 20, @Description = N'Every ratio the windings offer', @ActorId = @author;
    EXEC [config].[CharacteristicDefinition_Add] @DefinitionVersionRowId = @v, @CharacteristicKey = N'Cores',          @Name = N'Secondary windings',     @DataType = N'Integer', @DisplayGroup = N'Ratio',       @DisplayOrder = 30, @Description = N'The number of secondary windings', @ActorId = @author;
    EXEC [config].[CharacteristicDefinition_Add] @DefinitionVersionRowId = @v, @CharacteristicKey = N'RatedSecondary', @Name = N'Rated secondary',        @DataType = N'Text',    @DisplayGroup = N'Nameplate',   @DisplayOrder = 40, @Description = N'115 V, 120 V, 66.4 V L-N …', @ActorId = @author;
    EXEC [config].[CharacteristicDefinition_Add] @DefinitionVersionRowId = @v, @CharacteristicKey = N'AccuracyClass',  @Name = N'Accuracy class',         @DataType = N'Text',    @DisplayGroup = N'Nameplate',   @DisplayOrder = 50, @Description = N'As marked, e.g. 0.3 W X Y Z, 3P', @ActorId = @author;
    EXEC [config].[CharacteristicDefinition_Add] @DefinitionVersionRowId = @v, @CharacteristicKey = N'RatedBurden',    @Name = N'Rated burden',           @DataType = N'Text',    @DisplayGroup = N'Nameplate',   @DisplayOrder = 60, @Description = N'As marked, VA at power factor', @ActorId = @author;
    EXEC [config].[CharacteristicDefinition_Add] @DefinitionVersionRowId = @v, @CharacteristicKey = N'PolarityMark',   @Name = N'Polarity marking',       @DataType = N'Text',    @DisplayGroup = N'Performance', @DisplayOrder = 80, @Description = N'The marked polarity terminals', @ActorId = @author;
    EXEC [config].[CharacteristicDefinition_Add] @DefinitionVersionRowId = @v, @CharacteristicKey = N'Nameplate',      @Name = N'Nameplate, other',       @DataType = N'Text',    @DisplayGroup = N'Nameplate',   @DisplayOrder = 90, @Description = N'Anything else the nameplate says: type, BIL, capacitance (CVT), year', @ActorId = @author;
    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @v, @ActorId = @approver;
END
GO
