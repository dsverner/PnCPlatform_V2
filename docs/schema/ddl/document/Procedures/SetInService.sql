-- SCHEMA-DESIGN §8.3 (decision 127); PROCEDURES.md #14.
-- Opens the in-service period of a NativeSettings configuration-file revision for its device and
-- closes the device's prior open period in the same transaction, so the filtered unique index
-- (one open NativeSettings per device) never refuses a legitimate change-over. In service is a
-- fact from readback, distinct from approval (decision 55): an unapproved revision may be put in
-- service; that state is IsInServiceUnapproved in document.vConfigurationFileStatus and is returned
-- here as @IsUnapproved. The design names no finding category for it (STEPS.md step 8, open), so
-- no record.Finding row is written; the state is reported, not repaired.
CREATE PROCEDURE [document].[SetInService]
    @RevisionRowId UNIQUEIDENTIFIER,
    @InServiceFrom DATETIMEOFFSET(7) = NULL,
    @InServiceFromQuality TINYINT = 0,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @IsUnapproved BIT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @InServiceFrom = ISNULL(@InServiceFrom, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;

    DECLARE @device UNIQUEIDENTIFIER, @kind NVARCHAR(20), @from DATETIMEOFFSET(7), @to DATETIMEOFFSET(7),
            @model UNIQUEIDENTIFIER, @fw UNIQUEIDENTIFIER, @capture NVARCHAR(20), @diff UNIQUEIDENTIFIER, @ps NVARCHAR(20), @pe NVARCHAR(MAX), @sg TINYINT;
    SELECT @device = [DeviceEntityId], @kind = [FileKind], @from = [InServiceFrom], @to = [InServiceTo], @model = [ModelId], @fw = [FirmwareVersionId],
           @capture = [CaptureKind], @diff = [DifferentialRecordEntityId], @ps = [ParseStatus], @pe = [ParseError], @sg = [SettingsGroupCount]
    FROM [document].[vConfigurationFile] WHERE [RevisionRowId] = @RevisionRowId;
    IF @kind IS NULL THROW 50244, N'document.SetInService: the revision carries no current configuration file.', 1;
    IF @kind <> N'NativeSettings' OR @device IS NULL THROW 50245, N'document.SetInService: only a NativeSettings file of a device has an in-service period (§8.3).', 1;
    IF @from IS NOT NULL AND @to IS NULL THROW 50246, N'document.SetInService: the revision is already in service.', 1;

    DECLARE @priorRev UNIQUEIDENTIFIER, @priorFrom DATETIMEOFFSET(7);
    SELECT @priorRev = [RevisionRowId], @priorFrom = [InServiceFrom]
    FROM [document].[vConfigurationFile]
    WHERE [DeviceEntityId] = @device AND [FileKind] = N'NativeSettings' AND [InServiceFrom] IS NOT NULL AND [InServiceTo] IS NULL AND [RevisionRowId] <> @RevisionRowId;
    IF @priorFrom IS NOT NULL AND @priorFrom >= @InServiceFrom
        THROW 50247, N'document.SetInService: the new period must start after the prior period began.', 1;

    BEGIN TRANSACTION;
    IF @priorRev IS NOT NULL
    BEGIN
        DECLARE @pModel UNIQUEIDENTIFIER, @pFw UNIQUEIDENTIFIER, @pCapture NVARCHAR(20), @pDiff UNIQUEIDENTIFIER, @pPs NVARCHAR(20), @pPe NVARCHAR(MAX), @pSg TINYINT, @pQ TINYINT;
        SELECT @pModel = [ModelId], @pFw = [FirmwareVersionId], @pCapture = [CaptureKind], @pDiff = [DifferentialRecordEntityId], @pPs = [ParseStatus], @pPe = [ParseError], @pSg = [SettingsGroupCount], @pQ = [InServiceFromQuality]
        FROM [document].[vConfigurationFile] WHERE [RevisionRowId] = @priorRev;
        EXEC [document].[ConfigurationFile_Update] @RevisionRowId = @priorRev, @DeviceEntityId = @device, @FileKind = N'NativeSettings', @ModelId = @pModel, @FirmwareVersionId = @pFw,
             @CaptureKind = @pCapture, @InServiceFrom = @priorFrom, @InServiceTo = @InServiceFrom, @InServiceFromQuality = @pQ,
             @DifferentialRecordEntityId = @pDiff, @ParseStatus = @pPs, @ParseError = @pPe, @SettingsGroupCount = @pSg, @ActorId = @ActorId;
    END;
    EXEC [document].[ConfigurationFile_Update] @RevisionRowId = @RevisionRowId, @DeviceEntityId = @device, @FileKind = N'NativeSettings', @ModelId = @model, @FirmwareVersionId = @fw,
         @CaptureKind = @capture, @InServiceFrom = @InServiceFrom, @InServiceTo = NULL, @InServiceFromQuality = @InServiceFromQuality,
         @DifferentialRecordEntityId = @diff, @ParseStatus = @ps, @ParseError = @pe, @SettingsGroupCount = @sg, @ActorId = @ActorId;
    COMMIT TRANSACTION;

    SELECT @IsUnapproved = [IsInServiceUnapproved] FROM [document].[vConfigurationFileStatus] WHERE [RevisionRowId] = @RevisionRowId;
END;
GO
