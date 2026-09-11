-- SCHEMA-DESIGN §8.1 (124, 125); MIGRATION-PLAN.md Q14 (owner decision 2026-09-04). Writes bytes into the
-- document.FileStore FileTable and records them as a document.File of a revision, in one transaction, so
-- every file the platform keeps has a stream and not only a hash.
--
-- Layout in the FileTable: one directory per revision under the root, named by the revision's RowId, and the
-- file inside it under its own name — two revisions may therefore carry files of the same name, while the
-- FileTable's own (directory, name) uniqueness still holds within a revision (THROW 50133).
-- The SHA-256 is computed here from the bytes; when the caller supplies @Sha256 it must match (THROW 50131):
-- a file is never recorded under a hash it does not have. SizeBytes = DATALENGTH(@Content).
-- Verb-first name (CONVENTIONS.md): File_Write is hand-written; File_Add is generated and is what it calls.
CREATE PROCEDURE [document].[File_Write]
    @RevisionRowId UNIQUEIDENTIFIER,
    @FileName NVARCHAR(255),
    @MimeType NVARCHAR(100),
    @Content VARBINARY(MAX),
    @FileRole NVARCHAR(20),
    @Sha256 BINARY(32) = NULL,
    @RedactionStatus NVARCHAR(20) = N'None',
    @IsCapturedFromDevice BIT = 0,
    @ValidFrom DATETIMEOFFSET(7) = NULL,
    @ValidFromQuality TINYINT = 0,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,
    @FileStreamId UNIQUEIDENTIFIER = NULL OUTPUT,
    @EntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @RowId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @Content IS NULL
        THROW 50130, N'document.File_Write: @Content is required (an empty file is 0x, not NULL).', 1;
    IF @FileName IS NULL OR LEN(@FileName) = 0 OR @FileName IN (N'.', N'..') OR @FileName LIKE N'%[\/:*?"<>|]%'
        THROW 50130, N'document.File_Write: @FileName must be a plain file name (no path separators or reserved characters).', 1;
    DECLARE @hash BINARY(32) = HASHBYTES('SHA2_256', @Content);
    IF @Sha256 IS NOT NULL AND @Sha256 <> @hash
        THROW 50131, N'document.File_Write: @Sha256 does not match the SHA-256 of @Content.', 1;
    IF NOT EXISTS (SELECT 1 FROM [document].[Revision] WHERE [RowId] = @RevisionRowId AND [IsDeleted] = 0)
        THROW 50132, N'document.File_Write: @RevisionRowId is not a live revision.', 1;
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;

    BEGIN TRANSACTION;
    -- the revision's directory (created on first use)
    DECLARE @dirName NVARCHAR(255) = LOWER(CONVERT(NVARCHAR(36), @RevisionRowId));
    DECLARE @dirPath HIERARCHYID;
    SELECT @dirPath = [path_locator]
    FROM [document].[FileStore]
    WHERE [parent_path_locator] IS NULL AND [is_directory] = 1 AND [name] = @dirName;
    IF @dirPath IS NULL
    BEGIN
        SET @dirPath = [document].[fChildPathLocator](hierarchyid::GetRoot(), NEWID());
        INSERT [document].[FileStore] ([name], [path_locator], [is_directory])
        VALUES (@dirName, @dirPath, 1);
    END;
    IF EXISTS (SELECT 1 FROM [document].[FileStore] WHERE [parent_path_locator] = @dirPath AND [name] = @FileName)
        THROW 50133, N'document.File_Write: the revision already holds a file of that name.', 1;

    -- the bytes
    DECLARE @filePath HIERARCHYID = [document].[fChildPathLocator](@dirPath, NEWID());
    DECLARE @ids TABLE ([stream_id] UNIQUEIDENTIFIER);
    INSERT [document].[FileStore] ([name], [path_locator], [is_directory], [file_stream])
    OUTPUT inserted.[stream_id] INTO @ids
    VALUES (@FileName, @filePath, 0, @Content);
    SELECT @FileStreamId = [stream_id] FROM @ids;

    -- the record of the file (generated base procedure)
    DECLARE @size BIGINT = DATALENGTH(@Content);
    EXEC [document].[File_Add]
        @RevisionRowId = @RevisionRowId, @FileName = @FileName, @MimeType = @MimeType, @SizeBytes = @size,
        @Sha256 = @hash, @FileStreamId = @FileStreamId, @FileRole = @FileRole, @RedactionStatus = @RedactionStatus,
        @IsCapturedFromDevice = @IsCapturedFromDevice, @ValidFrom = @ValidFrom, @ValidFromQuality = @ValidFromQuality,
        @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @EntityId OUTPUT, @RowId = @RowId OUTPUT;
    COMMIT TRANSACTION;
END;
GO
