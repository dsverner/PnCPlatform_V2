-- #216 (2026-09-21): record one characteristic of an asset by its key — the guarded, audited way in (the generated
-- CharacteristicValue_Add/_Revise check nothing and log nothing). The first use is a relay's HARDWARE CONFIGURATION: the
-- SEL-221F's jumper positions from its manual (JMP105 baud per port, JMP103, JMP104 — IM 981207 3-2, 6-2), which the owner
-- ruled are recorded on the device, changed under a work request, never written to the settings file. The key is resolved
-- against the asset's template — the Effective asset template bound to its model (config.vAssetTemplate) first, else the
-- type's default template; the value is typed by the definition's DataType and, for an Enumeration, checked against the
-- allowed list; the prior row is closed in valid time; NULL clears. The audit row carries key, from, to and the work request.
--   50290 the asset's template knows no such key   50291 the value is not in the allowed list   50292 not a number / not a boolean
CREATE PROCEDURE [asset].[SetAssetCharacteristic]
    @AssetEntityId UNIQUEIDENTIFIER,
    @CharacteristicKey NVARCHAR(100),
    @Value NVARCHAR(400) = NULL,
    @WorkRequestEntityId UNIQUEIDENTIFIER = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @EntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @Outcome NVARCHAR(20) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    -- the template: the model's, else the type's default
    DECLARE @ver UNIQUEIDENTIFIER;
    SELECT TOP (1) @ver = t.[DefinitionVersionRowId]
      FROM [asset].[Asset] a JOIN [config].[vAssetTemplate] t ON t.[ModelId] = a.[ModelId]
     WHERE a.[EntityId] = @AssetEntityId AND a.[ValidTo] IS NULL AND a.[IsDeleted] = 0
     ORDER BY t.[VersionNumber] DESC;
    IF @ver IS NULL
        SELECT TOP (1) @ver = dv.[RowId]
          FROM [asset].[Asset] a
          JOIN [ref].[AssetType] ty ON ty.[AssetTypeCode] = a.[AssetTypeCode]
          JOIN [config].[DefinitionVersion] dv ON dv.[DefinitionEntityId] = ty.[DefaultTemplateDefinitionEntityId] AND dv.[Status] = N'Effective' AND dv.[IsDeleted] = 0
         WHERE a.[EntityId] = @AssetEntityId AND a.[ValidTo] IS NULL AND a.[IsDeleted] = 0
         ORDER BY dv.[VersionNumber] DESC;
    DECLARE @def UNIQUEIDENTIFIER, @type NVARCHAR(20), @allowed UNIQUEIDENTIFIER, @name NVARCHAR(200);
    SELECT @def = [RowId], @type = [DataType], @allowed = [AllowedValuesDefinitionRowId], @name = [Name]
      FROM [config].[CharacteristicDefinition]
     WHERE [DefinitionVersionRowId] = @ver AND [CharacteristicKey] = @CharacteristicKey AND [IsDeleted] = 0;
    IF @def IS NULL THROW 50290, N'asset.SetAssetCharacteristic: the asset''s template knows no characteristic with that key.', 1;

    -- the value, typed
    SET @Value = NULLIF(LTRIM(RTRIM(@Value)), N'');
    DECLARE @text NVARCHAR(400), @int BIGINT, @dec DECIMAL(28,10), @bit BIT;
    IF @Value IS NOT NULL
    BEGIN
        IF @type = N'Enumeration'
        BEGIN
            SELECT @text = [ValueCode] FROM [config].[EnumerationValue] WHERE [DefinitionVersionRowId] = @allowed AND [IsDeleted] = 0 AND [ValueCode] = @Value;
            IF @text IS NULL THROW 50291, N'asset.SetAssetCharacteristic: the value is not in the characteristic''s allowed list.', 1;
        END
        ELSE IF @type = N'Boolean'
        BEGIN
            SET @bit = CASE WHEN @Value IN (N'1', N'Y', N'y', N'true', N'True', N'TRUE', N'yes', N'Yes', N'YES') THEN 1
                            WHEN @Value IN (N'0', N'N', N'n', N'false', N'False', N'FALSE', N'no', N'No', N'NO') THEN 0 END;
            IF @bit IS NULL THROW 50292, N'asset.SetAssetCharacteristic: a Boolean characteristic takes Y or N.', 1;
        END
        ELSE IF @type = N'Integer'
        BEGIN
            SET @int = TRY_CONVERT(BIGINT, @Value);
            IF @int IS NULL THROW 50292, N'asset.SetAssetCharacteristic: an Integer characteristic takes a whole number.', 1;
        END
        ELSE IF @type = N'Decimal'
        BEGIN
            SET @dec = TRY_CONVERT(DECIMAL(28,10), @Value);
            IF @dec IS NULL THROW 50292, N'asset.SetAssetCharacteristic: a Decimal characteristic takes a number.', 1;
        END
        ELSE SET @text = @Value;
    END

    -- what stands
    DECLARE @from NVARCHAR(400);
    SELECT TOP (1) @EntityId = v.[EntityId],
           @from = COALESCE(v.[TextValue], CONVERT(NVARCHAR(40), v.[IntegerValue]), CONVERT(NVARCHAR(60), v.[DecimalValue]), CASE v.[BooleanValue] WHEN 1 THEN N'Y' WHEN 0 THEN N'N' END)
      FROM [asset].[CharacteristicValue] v
     WHERE v.[HostEntityId] = @AssetEntityId AND v.[CharacteristicDefinitionRowId] = @def AND v.[ValidTo] IS NULL AND v.[IsDeleted] = 0
     ORDER BY v.[RowSeq] DESC;
    DECLARE @to NVARCHAR(400) = CASE WHEN @Value IS NULL THEN NULL WHEN @type = N'Boolean' THEN CASE @bit WHEN 1 THEN N'Y' ELSE N'N' END ELSE @Value END;
    IF ISNULL(@from, N'') = ISNULL(@to, N'') BEGIN SET @Outcome = N'Unchanged'; RETURN; END

    BEGIN TRANSACTION;
    IF @Value IS NULL
    BEGIN
        EXEC [asset].[CharacteristicValue_SoftDelete] @EntityId = @EntityId, @ActorId = @ActorId;
        SET @Outcome = N'Cleared';
    END
    ELSE IF @EntityId IS NULL
    BEGIN
        EXEC [asset].[CharacteristicValue_Add] @HostEntityId = @AssetEntityId, @CharacteristicDefinitionRowId = @def,
             @TextValue = @text, @IntegerValue = @int, @DecimalValue = @dec, @BooleanValue = @bit, @ValidFrom = @now, @ActorId = @ActorId, @EntityId = @EntityId OUTPUT;
        SET @Outcome = N'Set';
    END
    ELSE
    BEGIN
        EXEC [asset].[CharacteristicValue_Revise] @EntityId = @EntityId, @HostEntityId = @AssetEntityId, @CharacteristicDefinitionRowId = @def,
             @TextValue = @text, @IntegerValue = @int, @DecimalValue = @dec, @BooleanValue = @bit, @ValidFrom = @now, @ActorId = @ActorId;
        SET @Outcome = N'Changed';
    END
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"characteristic-recorded","key":"', STRING_ESCAPE(@CharacteristicKey, 'json'),
        N'","name":"', STRING_ESCAPE(@name, 'json'), N'","from":', CASE WHEN @from IS NULL THEN N'null' ELSE N'"' + STRING_ESCAPE(@from, 'json') + N'"' END,
        N',"to":', CASE WHEN @to IS NULL THEN N'null' ELSE N'"' + STRING_ESCAPE(@to, 'json') + N'"' END,
        N',"workRequest":', CASE WHEN @WorkRequestEntityId IS NULL THEN N'null' ELSE N'"' + CONVERT(NVARCHAR(36), @WorkRequestEntityId) + N'"' END, N'}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'asset', @SubjectTable = N'Asset', @SubjectEntityId = @AssetEntityId,
         @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now;
    COMMIT TRANSACTION;
END;
GO
GRANT EXECUTE ON [asset].[SetAssetCharacteristic] TO [app_execute];
GO
