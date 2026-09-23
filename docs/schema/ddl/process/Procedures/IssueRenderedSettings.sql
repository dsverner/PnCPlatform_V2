-- #168 increment 2 (2026-09-16): the settings file written by the platform. When the settings step of a change commits with
-- no file attached, the outstanding revision's parsed settings — edited in the platform — are rendered as the model's
-- settings text (process.RenderSettingsText: the template's SET order, the logic masks after) and filed as the revision's
-- Native file: the file the technician loads, with no retyping. Filing goes through process.RefileRevision, which parses
-- the platform's own file back through the same reader every filed text gets — the round trip is the writer's proof, in
-- place (#168): the rows after the re-read are the rows that were rendered. The bytes are encoded the way CommitStep
-- decodes an attached text file (VARCHAR of the database collation), so a file attached and a file written read alike.
-- A rendered text identical to the file already filed changes nothing (@Written = 0).
-- #230 (2026-09-23): no longer only at the settings step — every change to an outstanding record's settings rewrites its file
-- (process.SetParsedSetting; RebaseDraft and the rationale apply once per act), so the file loaded to the relay and the
-- file a later change is copied from always carry the settings the record shows. Those rewrites pass @Reparse = 0: the rows
-- are the source and are not read back (a re-read closes and re-adds every row); the settings step, when it writes, keeps
-- the re-read. The writer's round trip is proved by the smoke (#168) and docs/schema/migration/roundtrip_settings.py. The file is written only from a complete reading: a file whose text holds settings the template does not
-- read (ParseStatus Partial) or was never read (NotParsed) would lose them in the rewrite, so it is refused (50188) and a
-- corrected file is attached instead. An empty file (a new relay's settings being entered) is written from what is entered.
CREATE PROCEDURE [process].[IssueRenderedSettings]
    @ConfigurationFileRevisionRowId UNIQUEIDENTIFIER,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @Reparse BIT = 1,
    @FileName NVARCHAR(255) = NULL OUTPUT,
    @Written BIT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @device UNIQUEIDENTIFIER, @kind NVARCHAR(20), @status NVARCHAR(20), @inService DATETIMEOFFSET(7), @parse NVARCHAR(20), @parseError NVARCHAR(MAX);
    SELECT @device = cf.[DeviceEntityId], @kind = cf.[FileKind], @inService = cf.[InServiceFrom], @status = r.[Status], @parse = cf.[ParseStatus], @parseError = cf.[ParseError]
    FROM [document].[ConfigurationFile] cf JOIN [document].[Revision] r ON r.[RowId] = cf.[RevisionRowId]
    WHERE cf.[RevisionRowId] = @ConfigurationFileRevisionRowId AND cf.[IsDeleted] = 0;
    IF @device IS NULL THROW 50180, N'process.IssueRenderedSettings: the revision is not a device configuration file.', 1;
    IF @status <> N'Draft' OR @inService IS NOT NULL THROW 50183, N'process.IssueRenderedSettings: only an outstanding (draft) revision is issued; an in-service or archived revision is the record.', 1;
    IF @kind <> N'SettingsText' THROW 50183, N'process.IssueRenderedSettings: the revision holds a native vendor file; no writer exists for that format yet, so the platform cannot write it.', 1;
    IF ISNULL(@parse, N'NotParsed') NOT IN (N'Parsed', N'Empty')
    BEGIN
        DECLARE @m6 NVARCHAR(800) = CASE WHEN @parse = N'Partial'
            THEN CONCAT(N'process.IssueRenderedSettings: the settings file holds settings this relay''s template does not read (', LEFT(ISNULL(@parseError, N'?'), 300), N'). Writing the file from the settings would drop them. Attach a corrected settings file instead.')
            ELSE N'process.IssueRenderedSettings: the settings file has not been read against this relay''s template, so the file cannot be written from its settings. Attach a corrected settings file instead.' END;
        THROW 50188, @m6, 1;
    END
    -- the settings step issues a file and needs settings to issue; a rewrite after edits (@Reparse = 0) writes what there is
    IF ISNULL(@Reparse, 1) = 1 AND NOT EXISTS (SELECT 1 FROM [document].[ParsedSetting] WHERE [ConfigurationFileRevisionRowId] = @ConfigurationFileRevisionRowId AND [IsDeleted] = 0 AND [ValidTo] IS NULL)
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
    -- the name: the file the change started from, else the device's name; RefileRevision keeps it unique in the store. A
    -- " (n)" RefileRevision added last time is taken off first, so rewrites number the name rather than nest it (#230)
    DECLARE @devName NVARCHAR(200) = (SELECT TOP (1) [Name] FROM [asset].[vAsset] WHERE [EntityId] = @device);
    DECLARE @stem NVARCHAR(255) = CASE WHEN @curName IS NULL THEN ISNULL(@devName, N'settings')
                                       WHEN @curName LIKE N'%.%' THEN LEFT(@curName, LEN(@curName) - CHARINDEX(N'.', REVERSE(@curName))) ELSE @curName END;
    IF @stem LIKE N'% ([0-9])' OR @stem LIKE N'% ([0-9][0-9])' OR @stem LIKE N'% ([0-9][0-9][0-9])' OR @stem LIKE N'% ([0-9][0-9][0-9][0-9])'
        SET @stem = LEFT(@stem, LEN(@stem) - CHARINDEX(N'( ', REVERSE(@stem)) - 1);
    DECLARE @name NVARCHAR(255) = LEFT(@stem, 240) + N'.txt';
    DECLARE @fsid UNIQUEIDENTIFIER;
    EXEC [process].[RefileRevision] @ConfigurationFileRevisionRowId = @ConfigurationFileRevisionRowId, @FileName = @name, @MimeType = N'text/plain', @Content = @bytes, @TextContent = @text,
         @Reparse = @Reparse, @ActorId = @ActorId, @FiledName = @FileName OUTPUT, @FileStreamId = @fsid OUTPUT;
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"settings-file-written","file":"', STRING_ESCAPE(@FileName, 'json'), N'","bytes":', DATALENGTH(@bytes), N'}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'document', @SubjectTable = N'ConfigurationFile', @SubjectEntityId = @device, @SubjectRowId = @ConfigurationFileRevisionRowId,
         @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now;
    SET @Written = 1;
END;
GO
