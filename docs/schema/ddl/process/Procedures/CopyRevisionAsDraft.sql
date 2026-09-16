-- #168 increment 2 (2026-09-16): the legacy procedure done right. In the legacy program "request change" on the in-service
-- settings (the A) created the change request's own copy (the M) that the engineer edited; completing the request made the
-- M the A and the A the P. Here: when a change's request step produces the settings-issue package, every device the step
-- names gets a draft revision copied from its in-service revision — the same file bytes filed again under the new revision
-- (a settings text is parsed against the template, so the copy's rows are its own to edit) and added to the package. The
-- settings book shows it Outstanding at once. A device with no in-service revision gets no copy (the settings step then
-- attaches a file, as before); a device already holding a draft in this package is not copied twice.
CREATE PROCEDURE [process].[CopyRevisionAsDraft]
    @DeviceEntityId UNIQUEIDENTIFIER,
    @PackageRevisionRowId UNIQUEIDENTIFIER,
    @PreparedByActorId UNIQUEIDENTIFIER = NULL,
    @At DATETIMEOFFSET(7) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @SourceRevisionRowId UNIQUEIDENTIFIER = NULL OUTPUT,
    @RevisionRowId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = ISNULL(@At, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    SET @RevisionRowId = NULL; SET @SourceRevisionRowId = NULL;
    IF NOT EXISTS (SELECT 1 FROM [document].[Revision] WHERE [RowId] = @PackageRevisionRowId AND [IsDeleted] = 0)
        THROW 50196, N'process.CopyRevisionAsDraft: the settings-issue package revision is not live.', 1;
    -- already in the package: the draft the device holds there
    SELECT TOP (1) @RevisionRowId = cf.[RevisionRowId]
    FROM [document].[SettingsIssuePackageItem] it JOIN [document].[ConfigurationFile] cf ON cf.[RevisionRowId] = it.[ConfigurationFileRevisionRowId] AND cf.[IsDeleted] = 0
    WHERE it.[PackageRevisionRowId] = @PackageRevisionRowId AND it.[IsDeleted] = 0 AND it.[ValidTo] IS NULL AND cf.[DeviceEntityId] = @DeviceEntityId
    ORDER BY it.[Sequence] DESC;
    IF @RevisionRowId IS NOT NULL RETURN;
    -- the in-service revision: the settings book's Active row
    SELECT TOP (1) @SourceRevisionRowId = sr.[RevisionRowId] FROM [document].[vSettingsRecord] sr
    WHERE sr.[DeviceEntityId] = @DeviceEntityId AND sr.[GridState] = N'Active' ORDER BY sr.[RowSeq] DESC;
    IF @SourceRevisionRowId IS NULL RETURN;
    DECLARE @kind NVARCHAR(20) = (SELECT [FileKind] FROM [document].[ConfigurationFile] WHERE [RevisionRowId] = @SourceRevisionRowId AND [IsDeleted] = 0);
    DECLARE @name NVARCHAR(255), @mime NVARCHAR(100), @stream UNIQUEIDENTIFIER, @bytes VARBINARY(MAX), @text NVARCHAR(MAX);
    SELECT TOP (1) @name = f.[FileName], @mime = f.[MimeType], @stream = f.[FileStreamId] FROM [document].[vFile] f
    WHERE f.[RevisionRowId] = @SourceRevisionRowId AND f.[FileRole] = N'Native' ORDER BY f.[RowSeq] DESC;
    IF @stream IS NULL THROW 50186, N'process.CopyRevisionAsDraft: the in-service revision has no file to copy.', 1;
    SELECT @bytes = [file_stream] FROM [document].[FileStore] WHERE [stream_id] = @stream;
    IF @bytes IS NULL SET @bytes = 0x;
    IF @kind = N'SettingsText' SET @text = CONVERT(NVARCHAR(MAX), CONVERT(VARCHAR(MAX), @bytes));

    SET @mime = ISNULL(@mime, N'application/octet-stream');
    BEGIN TRANSACTION;
    DECLARE @fk NVARCHAR(20);
    EXEC [process].[WriteConfigurationRevision] @DeviceEntityId = @DeviceEntityId, @CaptureKind = N'Designed', @FileName = @name, @MimeType = @mime, @Content = @bytes, @TextContent = @text,
         @PreparedByActorId = @PreparedByActorId, @At = @now, @ActorId = @ActorId, @FileKindOverride = @kind, @Status = N'Draft', @RevisionRowId = @RevisionRowId OUTPUT, @FileKind = @fk OUTPUT;
    DECLARE @seq INT = 1 + (SELECT COUNT(*) FROM [document].[SettingsIssuePackageItem] WHERE [PackageRevisionRowId] = @PackageRevisionRowId AND [IsDeleted] = 0 AND [ValidTo] IS NULL), @ie UNIQUEIDENTIFIER, @ir UNIQUEIDENTIFIER;
    EXEC [document].[SettingsIssuePackageItem_Add] @PackageRevisionRowId = @PackageRevisionRowId, @ConfigurationFileRevisionRowId = @RevisionRowId, @Sequence = @seq, @ActorId = @ActorId, @EntityId = @ie OUTPUT, @RowId = @ir OUTPUT;
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"revision-copied-as-draft","source":"', LOWER(CONVERT(NVARCHAR(36), @SourceRevisionRowId)), N'","draft":"', LOWER(CONVERT(NVARCHAR(36), @RevisionRowId)), N'","package":"', LOWER(CONVERT(NVARCHAR(36), @PackageRevisionRowId)), N'"}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'document', @SubjectTable = N'ConfigurationFile', @SubjectEntityId = @DeviceEntityId, @SubjectRowId = @RevisionRowId,
         @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now;
    COMMIT TRANSACTION;
END;
GO
