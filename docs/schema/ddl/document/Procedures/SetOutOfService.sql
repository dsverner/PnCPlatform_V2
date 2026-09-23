-- Decision #227 (2026-09-22). A device's settings taken out of service with nothing in their place — the old program's
-- Delete Order: the in-service record is archived and no new one goes in service (prog_frmRelaySettingChangeStatus.cpp:
-- 236-295). The partner of document.SetInService, which always opens a new period when it closes one; this only closes.
-- The revision keeps everything else it had; its row in the settings book moves to Archived because its period has ended.
--   50320 the revision carries no settings file of a device   50321 it is not in service   50322 it cannot end before it began
CREATE PROCEDURE [document].[SetOutOfService]
    @RevisionRowId UNIQUEIDENTIFIER,
    @OutOfServiceAt DATETIMEOFFSET(7) = NULL,
    @WorkRequestEntityId UNIQUEIDENTIFIER = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @OutOfServiceAt = ISNULL(@OutOfServiceAt, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;

    DECLARE @device UNIQUEIDENTIFIER, @kind NVARCHAR(20), @from DATETIMEOFFSET(7), @to DATETIMEOFFSET(7), @q TINYINT,
            @model UNIQUEIDENTIFIER, @fw UNIQUEIDENTIFIER, @capture NVARCHAR(20), @diff UNIQUEIDENTIFIER, @ps NVARCHAR(20), @pe NVARCHAR(MAX), @sg TINYINT;
    SELECT @device = [DeviceEntityId], @kind = [FileKind], @from = [InServiceFrom], @to = [InServiceTo], @q = [InServiceFromQuality], @model = [ModelId],
           @fw = [FirmwareVersionId], @capture = [CaptureKind], @diff = [DifferentialRecordEntityId], @ps = [ParseStatus], @pe = [ParseError], @sg = [SettingsGroupCount]
      FROM [document].[vConfigurationFile] WHERE [RevisionRowId] = @RevisionRowId;
    IF @kind IS NULL OR @kind NOT IN (N'NativeSettings', N'SettingsText') OR @device IS NULL
        THROW 50320, N'document.SetOutOfService: the revision carries no settings file of a device.', 1;
    IF @from IS NULL OR @to IS NOT NULL THROW 50321, N'document.SetOutOfService: the revision is not in service.', 1;
    IF @OutOfServiceAt <= @from THROW 50322, N'document.SetOutOfService: the period cannot end before it began.', 1;

    BEGIN TRANSACTION;
    EXEC [document].[ConfigurationFile_Update] @RevisionRowId = @RevisionRowId, @DeviceEntityId = @device, @FileKind = @kind, @ModelId = @model, @FirmwareVersionId = @fw,
         @CaptureKind = @capture, @InServiceFrom = @from, @InServiceTo = @OutOfServiceAt, @InServiceFromQuality = @q,
         @DifferentialRecordEntityId = @diff, @ParseStatus = @ps, @ParseError = @pe, @SettingsGroupCount = @sg, @ActorId = @ActorId;
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"settings-out-of-service","at":"', CONVERT(NVARCHAR(40), @OutOfServiceAt, 127),
        N'","workRequest":', CASE WHEN @WorkRequestEntityId IS NULL THEN N'null' ELSE N'"' + CONVERT(NVARCHAR(36), @WorkRequestEntityId) + N'"' END, N'}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'document', @SubjectTable = N'ConfigurationFile',
         @SubjectEntityId = @device, @SubjectRowId = @RevisionRowId, @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @OutOfServiceAt;
    COMMIT TRANSACTION;
END;
GO
GRANT EXECUTE ON [document].[SetOutOfService] TO [app_execute];
GO
