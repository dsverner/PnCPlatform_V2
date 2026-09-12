-- PROCEDURE-ENGINE §5.1 (W4, decisions #108, #109, #113). A configuration file captured at a step becomes a revision of
-- the device's DeviceConfiguration document: the vendor's native file for a microprocessor relay (FileKind
-- NativeSettings), the name=value text file for anything else (SettingsText, #61), CaptureKind Designed (the design)
-- or AsLeftReadback (the readback). The document is created on the device's first file. A text file is parsed against
-- the model's template at once (ParseSettingsText); a native file is stored NotParsed until a reader exists.
CREATE PROCEDURE [process].[WriteConfigurationRevision]
    @DeviceEntityId UNIQUEIDENTIFIER,
    @CaptureKind NVARCHAR(20),
    @FileName NVARCHAR(255),
    @MimeType NVARCHAR(100),
    @Content VARBINARY(MAX),
    @TextContent NVARCHAR(MAX) = NULL,
    @PreparedByActorId UNIQUEIDENTIFIER = NULL,
    @At DATETIMEOFFSET(7) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @RevisionRowId UNIQUEIDENTIFIER = NULL OUTPUT,
    @FileKind NVARCHAR(20) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = ISNULL(@At, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    IF @CaptureKind NOT IN (N'Designed', N'AsLeftReadback') THROW 50151, N'process.WriteConfigurationRevision: CaptureKind is Designed or AsLeftReadback.', 1;
    DECLARE @model UNIQUEIDENTIFIER, @tech NVARCHAR(20), @fw UNIQUEIDENTIFIER, @name NVARCHAR(200);
    SELECT TOP (1) @model = a.[ModelId], @tech = m.[Technology], @name = a.[Name] FROM [asset].[vAsset] a LEFT JOIN [ref].[Model] m ON m.[ModelId] = a.[ModelId] WHERE a.[EntityId] = @DeviceEntityId;
    IF @model IS NULL THROW 50197, N'process.WriteConfigurationRevision: the device has no model; a configuration file needs one (#61).', 1;
    SELECT @fw = [CurrentFirmwareVersionId] FROM [device].[vDevice] WHERE [EntityId] = @DeviceEntityId;
    SET @FileKind = CASE WHEN @tech IN (N'Microprocessor', N'IEC61850') THEN N'NativeSettings' ELSE N'SettingsText' END;

    -- the device's configuration document: through any prior configuration file of the device, else created now
    DECLARE @docEntity UNIQUEIDENTIFIER;
    SELECT TOP (1) @docEntity = r.[DocumentEntityId] FROM [document].[ConfigurationFile] cf JOIN [document].[Revision] r ON r.[RowId] = cf.[RevisionRowId]
    WHERE cf.[DeviceEntityId] = @DeviceEntityId AND cf.[IsDeleted] = 0 ORDER BY r.[RowSeq] DESC;
    BEGIN TRANSACTION;
    IF @docEntity IS NULL
    BEGIN
        DECLARE @class UNIQUEIDENTIFIER = (SELECT [EntityId] FROM [config].[Definition] WHERE [DefinitionKind] = N'CharacteristicSchema.DocumentClass' AND [DefinitionKey] = N'DeviceConfiguration' AND [IsDeleted] = 0);
        IF @class IS NULL THROW 50198, N'process.WriteConfigurationRevision: the DeviceConfiguration document class is not seeded.', 1;
        DECLARE @title NVARCHAR(200) = LEFT(N'Configuration — ' + ISNULL(@name, LOWER(CONVERT(NVARCHAR(36), @DeviceEntityId))), 200);
        EXEC [document].[Document_Add] @DocumentClassDefinitionEntityId = @class, @Title = @title, @ActorId = @ActorId, @EntityId = @docEntity OUTPUT;
    END
    DECLARE @label NVARCHAR(20) = CONVERT(NVARCHAR(20), 1 + (SELECT COUNT(*) FROM [document].[Revision] WHERE [DocumentEntityId] = @docEntity AND [IsDeleted] = 0 AND [ValidTo] IS NULL));
    EXEC [document].[Revision_Add] @DocumentEntityId = @docEntity, @RevisionLabel = @label, @Status = N'Draft', @PreparedByActorId = @PreparedByActorId, @PreparedAt = @now, @ActorId = @ActorId, @RowId = @RevisionRowId OUTPUT;
    DECLARE @captured BIT = CASE WHEN @CaptureKind = N'AsLeftReadback' THEN 1 ELSE 0 END;
    EXEC [document].[ConfigurationFile_Add] @RevisionRowId = @RevisionRowId, @DeviceEntityId = @DeviceEntityId, @FileKind = @FileKind, @ModelId = @model, @FirmwareVersionId = @fw,
         @CaptureKind = @CaptureKind, @ParseStatus = N'NotParsed', @ActorId = @ActorId;
    DECLARE @fsid UNIQUEIDENTIFIER, @fe UNIQUEIDENTIFIER, @fr UNIQUEIDENTIFIER;
    EXEC [document].[File_Write] @RevisionRowId = @RevisionRowId, @FileName = @FileName, @MimeType = @MimeType, @Content = @Content, @FileRole = N'Native',
         @IsCapturedFromDevice = @captured, @ActorId = @ActorId, @FileStreamId = @fsid OUTPUT, @EntityId = @fe OUTPUT, @RowId = @fr OUTPUT;
    IF @FileKind = N'SettingsText' AND @TextContent IS NOT NULL
    BEGIN
        DECLARE @pm INT, @pu INT;
        EXEC [process].[ParseSettingsText] @ConfigurationFileRevisionRowId = @RevisionRowId, @Text = @TextContent, @ActorId = @ActorId, @Matched = @pm OUTPUT, @Unmatched = @pu OUTPUT;
    END
    COMMIT TRANSACTION;
END;
GO
