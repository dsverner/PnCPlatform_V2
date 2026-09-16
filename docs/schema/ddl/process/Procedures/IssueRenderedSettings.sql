-- #168 increment 2 (2026-09-16): the settings file written by the platform. When the settings step of a change commits with
-- no file attached, the outstanding revision's parsed settings — edited in the platform — are rendered as the model's
-- settings text (process.RenderSettingsText: the template's SET order, the logic masks after) and filed as the revision's
-- Native file: the file the technician loads, with no retyping. Filing goes through process.RefileRevision, which parses
-- the platform's own file back through the same reader every filed text gets — the round trip is the writer's proof, in
-- place (#168): the rows after the re-read are the rows that were rendered. The bytes are encoded the way CommitStep
-- decodes an attached text file (VARCHAR of the database collation), so a file attached and a file written read alike.
-- A rendered text identical to the file already filed changes nothing (@Written = 0).
CREATE PROCEDURE [process].[IssueRenderedSettings]
    @ConfigurationFileRevisionRowId UNIQUEIDENTIFIER,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @FileName NVARCHAR(255) = NULL OUTPUT,
    @Written BIT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @device UNIQUEIDENTIFIER, @kind NVARCHAR(20), @status NVARCHAR(20), @inService DATETIMEOFFSET(7);
    SELECT @device = cf.[DeviceEntityId], @kind = cf.[FileKind], @inService = cf.[InServiceFrom], @status = r.[Status]
    FROM [document].[ConfigurationFile] cf JOIN [document].[Revision] r ON r.[RowId] = cf.[RevisionRowId]
    WHERE cf.[RevisionRowId] = @ConfigurationFileRevisionRowId AND cf.[IsDeleted] = 0;
    IF @device IS NULL THROW 50180, N'process.IssueRenderedSettings: the revision is not a device configuration file.', 1;
    IF @status <> N'Draft' OR @inService IS NOT NULL THROW 50183, N'process.IssueRenderedSettings: only an outstanding (draft) revision is issued; an in-service or archived revision is the record.', 1;
    IF @kind <> N'SettingsText' THROW 50183, N'process.IssueRenderedSettings: the revision holds a native vendor file; no writer exists for that format yet, so the platform cannot write it.', 1;
    IF NOT EXISTS (SELECT 1 FROM [document].[ParsedSetting] WHERE [ConfigurationFileRevisionRowId] = @ConfigurationFileRevisionRowId AND [IsDeleted] = 0 AND [ValidTo] IS NULL)
        THROW 50185, N'process.IssueRenderedSettings: the revision has no parsed settings to write; attach a settings file instead.', 1;

    DECLARE @text NVARCHAR(MAX);
    EXEC [process].[RenderSettingsText] @ConfigurationFileRevisionRowId = @ConfigurationFileRevisionRowId, @Text = @text OUTPUT;
    DECLARE @bytes VARBINARY(MAX) = CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX), @text));

    DECLARE @curName NVARCHAR(255), @curStream UNIQUEIDENTIFIER;
    SELECT TOP (1) @curName = f.[FileName], @curStream = f.[FileStreamId] FROM [document].[vFile] f
    WHERE f.[RevisionRowId] = @ConfigurationFileRevisionRowId AND f.[FileRole] = N'Native' ORDER BY f.[RowSeq] DESC;
    IF @curStream IS NOT NULL AND (SELECT [file_stream] FROM [document].[FileStore] WHERE [stream_id] = @curStream) = @bytes
    BEGIN
        SET @FileName = @curName; SET @Written = 0; RETURN;
    END
    -- the name: the file the change started from, else the device's name; RefileRevision keeps it unique in the store
    DECLARE @devName NVARCHAR(200) = (SELECT TOP (1) [Name] FROM [asset].[vAsset] WHERE [EntityId] = @device);
    DECLARE @stem NVARCHAR(255) = CASE WHEN @curName IS NULL THEN ISNULL(@devName, N'settings')
                                       WHEN @curName LIKE N'%.%' THEN LEFT(@curName, LEN(@curName) - CHARINDEX(N'.', REVERSE(@curName))) ELSE @curName END;
    DECLARE @name NVARCHAR(255) = LEFT(@stem, 240) + N'.txt';
    DECLARE @fsid UNIQUEIDENTIFIER;
    EXEC [process].[RefileRevision] @ConfigurationFileRevisionRowId = @ConfigurationFileRevisionRowId, @FileName = @name, @MimeType = N'text/plain', @Content = @bytes, @TextContent = @text,
         @ActorId = @ActorId, @FiledName = @FileName OUTPUT, @FileStreamId = @fsid OUTPUT;
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"settings-file-written","file":"', STRING_ESCAPE(@FileName, 'json'), N'","bytes":', DATALENGTH(@bytes), N'}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'document', @SubjectTable = N'ConfigurationFile', @SubjectEntityId = @device, @SubjectRowId = @ConfigurationFileRevisionRowId,
         @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now;
    SET @Written = 1;
END;
GO
