-- #219 (2026-09-21): record one input of a rationale by its key — the guarded, audited way in (the pattern of
-- asset.SetAssetCharacteristic, #216, over document.CharacteristicValue). The key is resolved against the rationale template
-- version the document.Rationale row points at; the value is typed by the definition's DataType (a Reference takes an entity
-- id; an Enumeration is checked against its list); the prior row is closed in valid time; NULL clears. Only a Draft rationale
-- takes a value — the rationale freezes with the settings revision it justifies (document.ApproveRevision).
--   50293 the template knows no such key   50294 not in the allowed list   50295 not a number / boolean / id   50297 not Draft
CREATE PROCEDURE [document].[SetRationaleValue]
    @RevisionRowId UNIQUEIDENTIFIER,
    @CharacteristicKey NVARCHAR(100),
    @Value NVARCHAR(400) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @EntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @Outcome NVARCHAR(20) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    DECLARE @ver UNIQUEIDENTIFIER, @status NVARCHAR(20), @revEntity UNIQUEIDENTIFIER;
    SELECT @ver = ra.[DeviceTemplateDefinitionVersionRowId], @status = r.[Status], @revEntity = r.[EntityId]
      FROM [document].[Rationale] ra JOIN [document].[vRevision] r ON r.[RowId] = ra.[RevisionRowId]
     WHERE ra.[RevisionRowId] = @RevisionRowId AND ra.[IsDeleted] = 0;
    IF @ver IS NULL THROW 50293, N'document.SetRationaleValue: no rationale with a template stands on that revision.', 1;
    IF @status <> N'Draft' THROW 50297, N'document.SetRationaleValue: the rationale is issued with its settings revision and is not edited after.', 1;
    DECLARE @def UNIQUEIDENTIFIER, @type NVARCHAR(20), @allowed UNIQUEIDENTIFIER, @name NVARCHAR(200);
    SELECT @def = [RowId], @type = [DataType], @allowed = [AllowedValuesDefinitionRowId], @name = [Name]
      FROM [config].[CharacteristicDefinition]
     WHERE [DefinitionVersionRowId] = @ver AND [CharacteristicKey] = @CharacteristicKey AND [IsDeleted] = 0;
    IF @def IS NULL THROW 50293, N'document.SetRationaleValue: the rationale template knows no input with that key.', 1;

    SET @Value = NULLIF(LTRIM(RTRIM(@Value)), N'');
    DECLARE @text NVARCHAR(400), @int BIGINT, @dec DECIMAL(28,10), @bit BIT, @ref UNIQUEIDENTIFIER;
    IF @Value IS NOT NULL
    BEGIN
        IF @type = N'Enumeration'
        BEGIN
            SELECT @text = [ValueCode] FROM [config].[EnumerationValue] WHERE [DefinitionVersionRowId] = @allowed AND [IsDeleted] = 0 AND [ValueCode] = @Value;
            IF @text IS NULL THROW 50294, N'document.SetRationaleValue: the value is not in the input''s allowed list.', 1;
        END
        ELSE IF @type = N'Boolean'
        BEGIN
            SET @bit = CASE WHEN @Value IN (N'1', N'Y', N'y', N'true', N'True', N'TRUE', N'yes', N'Yes', N'YES') THEN 1
                            WHEN @Value IN (N'0', N'N', N'n', N'false', N'False', N'FALSE', N'no', N'No', N'NO') THEN 0 END;
            IF @bit IS NULL THROW 50295, N'document.SetRationaleValue: a Boolean input takes Y or N.', 1;
        END
        ELSE IF @type = N'Integer'
        BEGIN
            SET @int = TRY_CONVERT(BIGINT, @Value);
            IF @int IS NULL THROW 50295, N'document.SetRationaleValue: an Integer input takes a whole number.', 1;
        END
        ELSE IF @type = N'Decimal'
        BEGIN
            SET @dec = TRY_CONVERT(DECIMAL(28,10), @Value);
            IF @dec IS NULL THROW 50295, N'document.SetRationaleValue: a Decimal input takes a number.', 1;
        END
        ELSE IF @type = N'Reference'
        BEGIN
            SET @ref = TRY_CONVERT(UNIQUEIDENTIFIER, @Value);
            IF @ref IS NULL THROW 50295, N'document.SetRationaleValue: a Reference input takes an entity id.', 1;
        END
        ELSE SET @text = @Value;
    END

    DECLARE @from NVARCHAR(400);
    SELECT TOP (1) @EntityId = v.[EntityId],
           @from = COALESCE(v.[TextValue], CONVERT(NVARCHAR(40), v.[IntegerValue]), CONVERT(NVARCHAR(60), v.[DecimalValue]), CASE v.[BooleanValue] WHEN 1 THEN N'Y' WHEN 0 THEN N'N' END, CONVERT(NVARCHAR(36), v.[ReferenceEntityId]))
      FROM [document].[CharacteristicValue] v
     WHERE v.[HostRevisionRowId] = @RevisionRowId AND v.[CharacteristicDefinitionRowId] = @def AND v.[ValidTo] IS NULL AND v.[IsDeleted] = 0
     ORDER BY v.[RowSeq] DESC;
    DECLARE @to NVARCHAR(400) = CASE WHEN @Value IS NULL THEN NULL WHEN @type = N'Boolean' THEN CASE @bit WHEN 1 THEN N'Y' ELSE N'N' END
                                     WHEN @type = N'Reference' THEN CONVERT(NVARCHAR(36), @ref) WHEN @type = N'Decimal' THEN CONVERT(NVARCHAR(60), @dec) ELSE @Value END;
    IF ISNULL(@from, N'') = ISNULL(@to, N'') BEGIN SET @Outcome = N'Unchanged'; RETURN; END

    BEGIN TRANSACTION;
    IF @Value IS NULL
    BEGIN
        EXEC [document].[CharacteristicValue_SoftDelete] @EntityId = @EntityId, @ActorId = @ActorId;
        SET @Outcome = N'Cleared';
    END
    ELSE IF @EntityId IS NULL
    BEGIN
        EXEC [document].[CharacteristicValue_Add] @HostRevisionRowId = @RevisionRowId, @CharacteristicDefinitionRowId = @def,
             @TextValue = @text, @IntegerValue = @int, @DecimalValue = @dec, @BooleanValue = @bit, @ReferenceEntityId = @ref, @ValidFrom = @now, @ActorId = @ActorId, @EntityId = @EntityId OUTPUT;
        SET @Outcome = N'Set';
    END
    ELSE
    BEGIN
        EXEC [document].[CharacteristicValue_Revise] @EntityId = @EntityId, @HostRevisionRowId = @RevisionRowId, @CharacteristicDefinitionRowId = @def,
             @TextValue = @text, @IntegerValue = @int, @DecimalValue = @dec, @BooleanValue = @bit, @ReferenceEntityId = @ref, @ValidFrom = @now, @ActorId = @ActorId;
        SET @Outcome = N'Changed';
    END
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"rationale-input-recorded","key":"', STRING_ESCAPE(@CharacteristicKey, 'json'),
        N'","name":"', STRING_ESCAPE(@name, 'json'), N'","from":', CASE WHEN @from IS NULL THEN N'null' ELSE N'"' + STRING_ESCAPE(@from, 'json') + N'"' END,
        N',"to":', CASE WHEN @to IS NULL THEN N'null' ELSE N'"' + STRING_ESCAPE(@to, 'json') + N'"' END, N'}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'document', @SubjectTable = N'Revision', @SubjectEntityId = @revEntity, @SubjectRowId = @RevisionRowId,
         @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now;
    COMMIT TRANSACTION;
END;
GO
GRANT EXECUTE ON [document].[SetRationaleValue] TO [app_execute];
GO
