-- #167 (2026-09-15): the legacy settings record's columnless fields as characteristics of a settings revision (owner: "fine
-- as characteristics since I don't see any value in indexing, grouping etc. on them"). One CharacteristicSchema.RecordTemplate
-- definition, SETTINGS_RECORD, with an Effective version; the record screen lays out whatever it carries by DisplayGroup and
-- DisplayOrder, so adding a field is a row here, not a column.
-- #194 (2026-09-19): the eight classification fields (CLASS, USE, RESPONSIBILITY, BULK_POWER_ELEMENT, PROTECTION_GROUP,
-- ELEMENT, LINE_TYPE, NUMBER_OF_RELAYS) are gone — the owner: "all can go and the tab removed, I do not trust any of the data
-- in those fields". Version 2 carries the ten instrument-transformer characteristics only. Idempotent: the version is added
-- once (by its change note); a version an Administrator authored stands beside it and the newest Effective one is read.
-- migration-rule: #194 the legacy classification columns are dropped (untrusted); the CT/PT ratio columns stay as characteristics
IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @author UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001', @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';
DECLARE @note NVARCHAR(200) = N'seed v2 (#194): the eight classification fields dropped as untrusted; instrument transformers only';
DECLARE @e UNIQUEIDENTIFIER, @v UNIQUEIDENTIFIER, @no INT;
SELECT @e = [EntityId] FROM [config].[Definition] WHERE [DefinitionKind] = N'CharacteristicSchema.RecordTemplate' AND [DefinitionKey] = N'SETTINGS_RECORD' AND [IsDeleted] = 0;
IF @e IS NULL
    EXEC [config].[AddDefinition] @DefinitionKind = N'CharacteristicSchema.RecordTemplate', @DefinitionKey = N'SETTINGS_RECORD', @Name = N'Settings record characteristics',
         @Description = N'The instrument-transformer fields of a settings revision (the legacy record''s columnless CT/PT fields, #167; the classification fields dropped in #194).', @ActorId = @author, @EntityId = @e OUTPUT;
IF NOT EXISTS (SELECT 1 FROM [config].[vDefinitionVersion] WHERE [DefinitionEntityId] = @e AND [Status] = N'Effective' AND [ChangeNote] = @note)
BEGIN
    EXEC [config].[AddDefinitionVersion] @DefinitionKey = N'SETTINGS_RECORD', @DefinitionKind = N'CharacteristicSchema.RecordTemplate', @ChangeNote = @note, @ActorId = @author, @VersionRowId = @v OUTPUT, @VersionNumber = @no OUTPUT;
    DECLARE @k NVARCHAR(100), @n NVARCHAR(200), @t NVARCHAR(20), @g NVARCHAR(100), @o INT;
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT [Key], [Name], [DataType], [DisplayGroup], [DisplayOrder] FROM (VALUES
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
