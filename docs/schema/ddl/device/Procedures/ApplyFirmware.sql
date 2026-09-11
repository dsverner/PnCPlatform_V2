-- SCHEMA-DESIGN §5.1 (decision 98), §5.3 (100); PROCEDURES.md #7, #8.
-- Opens a new device.FirmwareHistory period for a device (closing the prior one) and derives
-- device.Device.CurrentFirmwareVersionId from it — the column is never edited directly.
-- Refuses when the firmware version has no parse transform (the Transform.SettingsParse definition
-- that reads its native file), naming what is missing. Logs a FirmwareChanged action: the settings
-- re-validation the design fires is a Program.ObligationRule or workflow, not code (§5.3), and it
-- consumes this action (implementation choice recorded in STEPS.md step 5).
CREATE PROCEDURE [device].[ApplyFirmware]
    @DeviceEntityId UNIQUEIDENTIFIER,
    @FirmwareVersionId UNIQUEIDENTIFIER,
    @AppliedAt DATETIMEOFFSET(7) = NULL,
    @ValidFromQuality TINYINT = 0,
    @VerifiedByActorId UNIQUEIDENTIFIER = NULL,
    @VerifiedAt DATETIMEOFFSET(7) = NULL,
    @WorkRequestEntityId UNIQUEIDENTIFIER = NULL,
    @AdvisoryDispositionEntityId UNIQUEIDENTIFIER = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,
    @HistoryEntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @HistoryRowId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @AppliedAt = ISNULL(@AppliedAt, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;

    IF NOT EXISTS (SELECT 1 FROM [device].[vDevice] WHERE [EntityId] = @DeviceEntityId)
        THROW 50220, N'device.ApplyFirmware: the device is not a current device.', 1;
    DECLARE @part NVARCHAR(100), @hw NVARCHAR(50), @mfd DATE, @currentFw UNIQUEIDENTIFIER, @notes NVARCHAR(MAX), @assetModel UNIQUEIDENTIFIER;
    SELECT @part = d.[PartNumber], @hw = d.[HardwareRevision], @mfd = d.[ManufacturedAt], @currentFw = d.[CurrentFirmwareVersionId], @notes = d.[Notes], @assetModel = a.[ModelId]
    FROM [device].[vDevice] d JOIN [asset].[vAsset] a ON a.[EntityId] = d.[EntityId]
    WHERE d.[EntityId] = @DeviceEntityId;

    DECLARE @fwModel UNIQUEIDENTIFIER, @version NVARCHAR(100), @transform UNIQUEIDENTIFIER, @fwActive BIT;
    SELECT @fwModel = [ModelId], @version = [VersionString], @transform = [ParseTransformDefinitionEntityId], @fwActive = [IsActive]
    FROM [ref].[FirmwareVersion] WHERE [FirmwareVersionId] = @FirmwareVersionId;
    IF @fwModel IS NULL OR @fwActive = 0 THROW 50221, N'device.ApplyFirmware: unknown or inactive firmware version.', 1;
    IF @assetModel IS NOT NULL AND @assetModel <> @fwModel THROW 50222, N'device.ApplyFirmware: the firmware version belongs to another model than the device.', 1;

    DECLARE @modelCode NVARCHAR(100) = (SELECT [ModelCode] FROM [ref].[Model] WHERE [ModelId] = @fwModel);
    IF @transform IS NULL
    BEGIN
        DECLARE @m1 NVARCHAR(400) = CONCAT(N'device.ApplyFirmware: firmware ', @modelCode, N' ', @version, N' names no parse transform; define a Transform.SettingsParse for it and attach it to ref.FirmwareVersion.ParseTransformDefinitionEntityId (§5.3).');
        THROW 50223, @m1, 1;
    END;
    DECLARE @transformKey NVARCHAR(100), @transformKind NVARCHAR(40);
    SELECT @transformKey = [DefinitionKey], @transformKind = [DefinitionKind] FROM [config].[vDefinition] WHERE [EntityId] = @transform;
    IF @transformKey IS NULL
    BEGIN
        DECLARE @m2 NVARCHAR(400) = CONCAT(N'device.ApplyFirmware: the parse transform attached to firmware ', @modelCode, N' ', @version, N' is not a current definition (§5.3).');
        THROW 50224, @m2, 1;
    END;
    IF @transformKind <> N'Transform.SettingsParse'
    BEGIN
        DECLARE @m3 NVARCHAR(400) = CONCAT(N'device.ApplyFirmware: definition ', @transformKey, N' is a ', @transformKind, N', not a Transform.SettingsParse (§5.2).');
        THROW 50225, @m3, 1;
    END;

    DECLARE @priorEntity UNIQUEIDENTIFIER = (SELECT [EntityId] FROM [device].[vFirmwareHistory] WHERE [DeviceEntityId] = @DeviceEntityId);

    BEGIN TRANSACTION;
    IF @priorEntity IS NULL
        EXEC [device].[FirmwareHistory_Add] @DeviceEntityId = @DeviceEntityId, @FirmwareVersionId = @FirmwareVersionId, @AppliedByActorId = @ActorId,
             @VerifiedByActorId = @VerifiedByActorId, @VerifiedAt = @VerifiedAt, @WorkRequestEntityId = @WorkRequestEntityId, @AdvisoryDispositionEntityId = @AdvisoryDispositionEntityId,
             @ValidFrom = @AppliedAt, @ValidFromQuality = @ValidFromQuality, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId,
             @EntityId = @HistoryEntityId OUTPUT, @RowId = @HistoryRowId OUTPUT;
    ELSE
    BEGIN
        SET @HistoryEntityId = @priorEntity;
        EXEC [device].[FirmwareHistory_Revise] @EntityId = @priorEntity, @DeviceEntityId = @DeviceEntityId, @FirmwareVersionId = @FirmwareVersionId, @AppliedByActorId = @ActorId,
             @VerifiedByActorId = @VerifiedByActorId, @VerifiedAt = @VerifiedAt, @WorkRequestEntityId = @WorkRequestEntityId, @AdvisoryDispositionEntityId = @AdvisoryDispositionEntityId,
             @ValidFrom = @AppliedAt, @ValidFromQuality = @ValidFromQuality, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @RowId = @HistoryRowId OUTPUT;
    END;

    -- derived column on the device (§5.1): a new fact version carrying the other columns forward
    EXEC [device].[Device_Revise] @EntityId = @DeviceEntityId, @PartNumber = @part, @HardwareRevision = @hw, @ManufacturedAt = @mfd,
         @CurrentFirmwareVersionId = @FirmwareVersionId, @Notes = @notes,
         @ValidFrom = @AppliedAt, @ValidFromQuality = @ValidFromQuality, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId;

    DECLARE @detail NVARCHAR(MAX) = (SELECT @currentFw AS [priorFirmwareVersionId], @FirmwareVersionId AS [firmwareVersionId], @transformKey AS [parseTransform] FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC [audit].[LogAction] @ActionKindCode = N'FirmwareChanged', @SubjectSchema = N'device', @SubjectTable = N'FirmwareHistory',
                             @SubjectEntityId = @DeviceEntityId, @SubjectRowId = @HistoryRowId, @Detail = @detail, @ActorId = @ActorId, @OccurredAt = @AppliedAt;
    COMMIT TRANSACTION;
END;
GO
