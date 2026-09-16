-- #167 (2026-09-15): the legacy settings record's columnless fields — class, use, responsibility, bulk power element,
-- protection group, element, line type, number of relays, the CT and PT ratios — as characteristics of a settings
-- revision (owner: "fine as characteristics since I don't see any value in indexing, grouping etc. on them"). One
-- CharacteristicSchema.RecordTemplate definition, SETTINGS_RECORD, with an Effective version; the record screen lays
-- out whatever it carries by DisplayGroup and DisplayOrder, so adding a field is a row here, not a column. Idempotent:
-- an existing key is left alone (an Administrator's edits stand).
IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @author UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001', @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';
IF NOT EXISTS (SELECT 1 FROM [config].[Definition] WHERE [DefinitionKind] = N'CharacteristicSchema.RecordTemplate' AND [DefinitionKey] = N'SETTINGS_RECORD' AND [IsDeleted] = 0)
BEGIN
    DECLARE @e UNIQUEIDENTIFIER, @v UNIQUEIDENTIFIER, @no INT;
    EXEC [config].[AddDefinition] @DefinitionKind = N'CharacteristicSchema.RecordTemplate', @DefinitionKey = N'SETTINGS_RECORD', @Name = N'Settings record characteristics',
         @Description = N'The classification and instrument-transformer fields of a settings revision (the legacy record''s columnless fields, #167).', @ActorId = @author, @EntityId = @e OUTPUT;
    EXEC [config].[AddDefinitionVersion] @DefinitionKey = N'SETTINGS_RECORD', @DefinitionKind = N'CharacteristicSchema.RecordTemplate', @ChangeNote = N'seed (#167)', @ActorId = @author, @VersionRowId = @v OUTPUT, @VersionNumber = @no OUTPUT;
    DECLARE @k NVARCHAR(100), @n NVARCHAR(200), @t NVARCHAR(20), @g NVARCHAR(100), @o INT;
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT [Key], [Name], [DataType], [DisplayGroup], [DisplayOrder] FROM (VALUES
            (N'CLASS',                N'Class',                N'Text',    N'Classification',         10),
            (N'USE',                  N'Use',                  N'Text',    N'Classification',         20),
            (N'RESPONSIBILITY',       N'Responsibility',       N'Text',    N'Classification',         30),
            (N'BULK_POWER_ELEMENT',   N'Bulk power element',   N'Text',    N'Classification',         40),
            (N'PROTECTION_GROUP',     N'Protection group',     N'Text',    N'Classification',         50),
            (N'ELEMENT',              N'Element',              N'Text',    N'Classification',         60),
            (N'LINE_TYPE',            N'Line type',            N'Text',    N'Classification',         70),
            (N'NUMBER_OF_RELAYS',     N'Number of relays',     N'Integer', N'Classification',         80),
            (N'CT_MAIN1',             N'CT main 1',            N'Text',    N'Instrument transformers', 10),
            (N'CT_MAIN2',             N'CT main 2',            N'Text',    N'Instrument transformers', 20),
            (N'CT_MAIN3',             N'CT main 3',            N'Text',    N'Instrument transformers', 30),
            (N'CT_MAIN4',             N'CT main 4',            N'Text',    N'Instrument transformers', 40),
            (N'PT_MAIN',              N'PT main',              N'Text',    N'Instrument transformers', 50),
            (N'CT_AUX1',              N'CT aux 1',             N'Text',    N'Instrument transformers', 60),
            (N'CT_AUX2',              N'CT aux 2',             N'Text',    N'Instrument transformers', 70),
            (N'CT_AUX3',              N'CT aux 3',             N'Text',    N'Instrument transformers', 80),
            (N'CT_AUX4',              N'CT aux 4',             N'Text',    N'Instrument transformers', 90),
            (N'PT_AUX',               N'PT aux',               N'Text',    N'Instrument transformers', 100)
        ) x ([Key], [Name], [DataType], [DisplayGroup], [DisplayOrder]);
    OPEN c; FETCH NEXT FROM c INTO @k, @n, @t, @g, @o;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC [config].[AddCharacteristic] @DefinitionVersionRowId = @v, @CharacteristicKey = @k, @Name = @n, @DataType = @t, @DisplayGroup = @g, @DisplayOrder = @o, @ActorId = @author;
        FETCH NEXT FROM c INTO @k, @n, @t, @g, @o;
    END
    CLOSE c; DEALLOCATE c;
    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @v, @ActorId = @approver;
END
GO
