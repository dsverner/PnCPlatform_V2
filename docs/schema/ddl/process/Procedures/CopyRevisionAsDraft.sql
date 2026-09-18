-- #168 increment 2 (2026-09-16): the legacy procedure done right. In the legacy program "request change" on the in-service
-- settings (the A) created the change request's own copy (the M) that the engineer edited; completing the request made the
-- M the A and the A the P. Here: when a change's request step produces the settings-issue package, every device the step
-- names gets a draft revision copied from its in-service revision — the same file bytes filed again under the new revision
-- (a settings text is parsed against the template, so the copy's rows are its own to edit) and added to the package. The
-- settings book shows it Outstanding at once. A device already holding a draft in this package is not copied twice.
-- #187 (2026-09-18): a device with NO in-service revision — a relay just placed, its first settings — gets an EMPTY draft:
-- a SettingsText revision with no text, parsed against the model's template to zero rows, so the settings sheet opens
-- with every setting "not set" and editable, and the file is written by the platform at issue. Until now such a device
-- got nothing and the settings step expected a file to be attached, against the owner's ruling that settings are edited
-- in the platform and the native file is written by it (#168, feedback-native-settings-round-trip).
-- #191 (2026-09-18): a SECOND change on a device while one is open. Until now the second copied the in-service revision
-- and never saw the first's edits, and whichever went in service last silently overwrote the other. The owner ruled for
-- pending modifications: the second's draft starts from the first's CURRENT settings (its parsed rows rendered by
-- RenderSettingsText, not its file, which is rewritten only when its settings step commits) and is linked BasedOn to it;
-- CommitStep refuses to put it in service before the first. The basis is the device's newest Outstanding record outside
-- this package whose request is not cancelled. Increment 2 freezes the basis and flags the second when the first changes.
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
    DECLARE @kind NVARCHAR(20), @name NVARCHAR(255), @mime NVARCHAR(100), @stream UNIQUEIDENTIFIER, @bytes VARBINARY(MAX), @text NVARCHAR(MAX);
    -- #191: the basis — another request's open draft for this device, its current settings
    DECLARE @basisEntity UNIQUEIDENTIFIER, @basisTitle NVARCHAR(200);
    SELECT TOP (1) @SourceRevisionRowId = sr.[RevisionRowId], @basisTitle = sr.[WorkRequestTitle]
    FROM [document].[vSettingsRecord] sr
    WHERE sr.[DeviceEntityId] = @DeviceEntityId AND sr.[GridState] = N'Outstanding'
      AND (sr.[PackageRevisionRowId] IS NULL OR sr.[PackageRevisionRowId] <> @PackageRevisionRowId)
      AND NOT EXISTS (SELECT 1 FROM [process].[WorkflowInstance] wi WHERE wi.[IsDeleted] = 0 AND wi.[SubjectKind] = N'WorkRequest' AND wi.[SubjectEntityId] = sr.[WorkRequestEntityId] AND wi.[CurrentState] = N'Cancelled')
    ORDER BY sr.[RowSeq] DESC;
    IF @SourceRevisionRowId IS NOT NULL
    BEGIN
        SET @basisEntity = @SourceRevisionRowId;   -- a DocumentRevision subject is the revision's RowId (meta.fEntityExists)
        EXEC [process].[RenderSettingsText] @ConfigurationFileRevisionRowId = @SourceRevisionRowId, @Text = @text OUTPUT;
        IF @text IS NOT NULL
        BEGIN
            SET @kind = N'SettingsText'; SET @name = N'settings.txt'; SET @mime = N'text/plain'; SET @bytes = CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX), @text));
        END
    END
    ELSE
        -- the in-service revision: the settings book's Active row
        SELECT TOP (1) @SourceRevisionRowId = sr.[RevisionRowId] FROM [document].[vSettingsRecord] sr
        WHERE sr.[DeviceEntityId] = @DeviceEntityId AND sr.[GridState] = N'Active' ORDER BY sr.[RowSeq] DESC;
    IF @SourceRevisionRowId IS NULL
    BEGIN
        -- #187: the first settings of a device — an empty text, the template's rows all unset
        SET @kind = N'SettingsText'; SET @name = N'settings.txt'; SET @mime = N'text/plain'; SET @bytes = 0x; SET @text = N'';
    END
    ELSE IF @bytes IS NULL   -- the in-service revision, or a basis with no template to render: its file, byte for byte
    BEGIN
    SET @kind = (SELECT [FileKind] FROM [document].[ConfigurationFile] WHERE [RevisionRowId] = @SourceRevisionRowId AND [IsDeleted] = 0);
    SELECT TOP (1) @name = f.[FileName], @mime = f.[MimeType], @stream = f.[FileStreamId] FROM [document].[vFile] f
    WHERE f.[RevisionRowId] = @SourceRevisionRowId AND f.[FileRole] = N'Native' ORDER BY f.[RowSeq] DESC;
    IF @stream IS NULL THROW 50186, N'process.CopyRevisionAsDraft: the in-service revision has no file to copy.', 1;
    SELECT @bytes = [file_stream] FROM [document].[FileStore] WHERE [stream_id] = @stream;
    IF @bytes IS NULL SET @bytes = 0x;
    IF @kind = N'SettingsText' SET @text = CONVERT(NVARCHAR(MAX), CONVERT(VARCHAR(MAX), @bytes));
    END

    SET @mime = ISNULL(@mime, N'application/octet-stream');
    BEGIN TRANSACTION;
    DECLARE @fk NVARCHAR(20);
    EXEC [process].[WriteConfigurationRevision] @DeviceEntityId = @DeviceEntityId, @CaptureKind = N'Designed', @FileName = @name, @MimeType = @mime, @Content = @bytes, @TextContent = @text,
         @PreparedByActorId = @PreparedByActorId, @At = @now, @ActorId = @ActorId, @FileKindOverride = @kind, @Status = N'Draft', @RevisionRowId = @RevisionRowId OUTPUT, @FileKind = @fk OUTPUT;
    DECLARE @seq INT = 1 + (SELECT COUNT(*) FROM [document].[SettingsIssuePackageItem] WHERE [PackageRevisionRowId] = @PackageRevisionRowId AND [IsDeleted] = 0 AND [ValidTo] IS NULL), @ie UNIQUEIDENTIFIER, @ir UNIQUEIDENTIFIER;
    EXEC [document].[SettingsIssuePackageItem_Add] @PackageRevisionRowId = @PackageRevisionRowId, @ConfigurationFileRevisionRowId = @RevisionRowId, @Sequence = @seq, @ActorId = @ActorId, @EntityId = @ie OUTPUT, @RowId = @ir OUTPUT;
    IF @basisEntity IS NOT NULL
        EXEC [document].[RevisionLink_Add] @RevisionRowId = @RevisionRowId, @LinkKind = N'BasedOn', @SubjectKind = N'DocumentRevision', @SubjectEntityId = @basisEntity, @ActorId = @ActorId;
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"', CASE WHEN @SourceRevisionRowId IS NULL THEN N'first-draft-from-template' WHEN @basisEntity IS NOT NULL THEN N'draft-based-on-open-draft' ELSE N'revision-copied-as-draft' END, N'","source":"', ISNULL(LOWER(CONVERT(NVARCHAR(36), @SourceRevisionRowId)), N''), N'","draft":"', LOWER(CONVERT(NVARCHAR(36), @RevisionRowId)), N'","package":"', LOWER(CONVERT(NVARCHAR(36), @PackageRevisionRowId)), N'"}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'document', @SubjectTable = N'ConfigurationFile', @SubjectEntityId = @DeviceEntityId, @SubjectRowId = @RevisionRowId,
         @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now;
    COMMIT TRANSACTION;
END;
GO
