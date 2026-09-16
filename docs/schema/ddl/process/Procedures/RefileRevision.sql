-- #168 increment 2 (2026-09-16): the file of an outstanding revision replaced. The revision keeps its identity, its place in
-- the settings-issue package and its history; the file previously filed is closed (soft-deleted, its bytes kept in the
-- store) and the new one filed as the revision's Native file, parsed against the model's template when it is a settings
-- text (process.ParseSettingsText closes the prior reading in valid time). Two callers: process.IssueRenderedSettings (the
-- platform's own file, written from the edited settings) and process.CommitStep (a vendor file attached at the settings
-- step over the copy the change started from — one outstanding revision per device per package, never two).
-- A name the revision's store already holds (the copy's file, say) gets " (2)", " (3)"… before its extension.
CREATE PROCEDURE [process].[RefileRevision]
    @ConfigurationFileRevisionRowId UNIQUEIDENTIFIER,
    @FileName NVARCHAR(255),
    @MimeType NVARCHAR(100),
    @Content VARBINARY(MAX),
    @TextContent NVARCHAR(MAX) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @FiledName NVARCHAR(255) = NULL OUTPUT,
    @FileStreamId UNIQUEIDENTIFIER = NULL OUTPUT
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
    IF @device IS NULL THROW 50180, N'process.RefileRevision: the revision is not a device configuration file.', 1;
    IF @status <> N'Draft' OR @inService IS NOT NULL THROW 50183, N'process.RefileRevision: only an outstanding (draft) revision takes a new file; an in-service or archived revision is the record.', 1;
    IF @Content IS NULL THROW 50130, N'process.RefileRevision: @Content is required.', 1;

    -- a name free in the revision's store
    DECLARE @dirName NVARCHAR(255) = LOWER(CONVERT(NVARCHAR(36), @ConfigurationFileRevisionRowId));
    DECLARE @dirPath HIERARCHYID = (SELECT [path_locator] FROM [document].[FileStore] WHERE [parent_path_locator] IS NULL AND [is_directory] = 1 AND [name] = @dirName);
    DECLARE @dot INT = CASE WHEN @FileName LIKE N'%.%' THEN LEN(@FileName) - CHARINDEX(N'.', REVERSE(@FileName)) ELSE 0 END;
    DECLARE @stem NVARCHAR(255) = CASE WHEN @dot > 0 THEN LEFT(@FileName, @dot) ELSE @FileName END, @ext NVARCHAR(255) = CASE WHEN @dot > 0 THEN SUBSTRING(@FileName, @dot + 1, 255) ELSE N'' END;
    DECLARE @k INT = 1;
    SET @FiledName = @FileName;
    WHILE @dirPath IS NOT NULL AND EXISTS (SELECT 1 FROM [document].[FileStore] WHERE [parent_path_locator] = @dirPath AND [name] = @FiledName)
    BEGIN
        SET @k += 1;
        SET @FiledName = LEFT(@stem, 240) + N' (' + CONVERT(NVARCHAR(10), @k) + N')' + @ext;
    END

    BEGIN TRANSACTION;
    DECLARE @prev UNIQUEIDENTIFIER, @prevName NVARCHAR(255);
    DECLARE pf CURSOR LOCAL FAST_FORWARD FOR SELECT f.[EntityId], f.[FileName] FROM [document].[vFile] f WHERE f.[RevisionRowId] = @ConfigurationFileRevisionRowId AND f.[FileRole] = N'Native';
    OPEN pf; FETCH NEXT FROM pf INTO @prev, @prevName;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC [document].[File_SoftDelete] @EntityId = @prev, @ActorId = @ActorId;
        FETCH NEXT FROM pf INTO @prev, @prevName;
    END
    CLOSE pf; DEALLOCATE pf;
    DECLARE @fe UNIQUEIDENTIFIER, @fr UNIQUEIDENTIFIER;
    EXEC [document].[File_Write] @RevisionRowId = @ConfigurationFileRevisionRowId, @FileName = @FiledName, @MimeType = @MimeType, @Content = @Content, @FileRole = N'Native',
         @ActorId = @ActorId, @FileStreamId = @FileStreamId OUTPUT, @EntityId = @fe OUTPUT, @RowId = @fr OUTPUT;
    IF @kind = N'SettingsText' AND @TextContent IS NOT NULL
    BEGIN
        DECLARE @pm INT, @pu INT;
        EXEC [process].[ParseSettingsText] @ConfigurationFileRevisionRowId = @ConfigurationFileRevisionRowId, @Text = @TextContent, @ActorId = @ActorId, @Matched = @pm OUTPUT, @Unmatched = @pu OUTPUT;
    END
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"revision-refiled","file":"', STRING_ESCAPE(@FiledName, 'json'), N'","bytes":', DATALENGTH(@Content), N',"replaced":', CASE WHEN @prevName IS NULL THEN N'null' ELSE N'"' + STRING_ESCAPE(@prevName, 'json') + N'"' END, N'}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'document', @SubjectTable = N'ConfigurationFile', @SubjectEntityId = @device, @SubjectRowId = @ConfigurationFileRevisionRowId,
         @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now;
    COMMIT TRANSACTION;
END;
GO
