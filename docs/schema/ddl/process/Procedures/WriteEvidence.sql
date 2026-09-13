-- PROCEDURE-ENGINE §5 action 7 (W4, decision #109). The files attached at a committed step: one Evidence document per
-- commit, one revision, one document.File per attachment, and a RevisionLink EvidenceFor the step's record.
-- @Evidence is a JSON array of {"name","mimeType","kind","contentBase64"}; kind is the document's evidence vocabulary
-- (SettingsFile, ReadbackFile, Study, TestSheet…) and is kept in the file name's role only — the link is what the
-- record's evidence chain reads.
CREATE PROCEDURE [process].[WriteEvidence]
    @RecordEntityId UNIQUEIDENTIFIER,
    @StepId NVARCHAR(64),
    @Evidence NVARCHAR(MAX),
    @PreparedByActorId UNIQUEIDENTIFIER = NULL,
    @At DATETIMEOFFSET(7) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,   -- W7 (#138)
    @RevisionRowId UNIQUEIDENTIFIER = NULL OUTPUT,
    @Files INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = ISNULL(@At, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    SET @Files = 0;
    IF @Evidence IS NULL OR ISJSON(@Evidence) <> 1 OR NOT EXISTS (SELECT 1 FROM OPENJSON(@Evidence)) RETURN;
    DECLARE @class UNIQUEIDENTIFIER = (SELECT [EntityId] FROM [config].[Definition] WHERE [DefinitionKind] = N'CharacteristicSchema.DocumentClass' AND [DefinitionKey] = N'Evidence' AND [IsDeleted] = 0);
    IF @class IS NULL THROW 50198, N'process.WriteEvidence: the Evidence document class is not seeded.', 1;
    BEGIN TRANSACTION;
    DECLARE @docEntity UNIQUEIDENTIFIER;
    DECLARE @title NVARCHAR(200) = LEFT(N'Evidence — ' + @StepId + N' — ' + LOWER(CONVERT(NVARCHAR(36), @RecordEntityId)), 200);
    EXEC [document].[Document_Add] @DocumentClassDefinitionEntityId = @class, @Title = @title, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @docEntity OUTPUT;
    EXEC [document].[Revision_Add] @DocumentEntityId = @docEntity, @RevisionLabel = N'1', @Status = N'Issued', @PreparedByActorId = @PreparedByActorId, @PreparedAt = @now, @IssuedAt = @now, @ActorId = @ActorId, @RowId = @RevisionRowId OUTPUT;
    DECLARE @name NVARCHAR(255), @mime NVARCHAR(100), @b64 NVARCHAR(MAX), @bin VARBINARY(MAX), @fsid UNIQUEIDENTIFIER, @fe UNIQUEIDENTIFIER, @fr UNIQUEIDENTIFIER;
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT JSON_VALUE(e.[value], '$.name'), ISNULL(JSON_VALUE(e.[value], '$.mimeType'), N'application/octet-stream'), JSON_VALUE(e.[value], '$.contentBase64') FROM OPENJSON(@Evidence) e;
    OPEN c; FETCH NEXT FROM c INTO @name, @mime, @b64;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @bin = CAST(N'' AS XML).value('xs:base64Binary(sql:variable("@b64"))', 'VARBINARY(MAX)');
        IF @bin IS NULL OR @name IS NULL THROW 50199, N'process.WriteEvidence: every evidence item needs a name and base64 content.', 1;
        EXEC [document].[File_Write] @RevisionRowId = @RevisionRowId, @FileName = @name, @MimeType = @mime, @Content = @bin, @FileRole = N'Attachment', @ActorId = @ActorId,
             @FileStreamId = @fsid OUTPUT, @EntityId = @fe OUTPUT, @RowId = @fr OUTPUT;
        SET @Files += 1;
        FETCH NEXT FROM c INTO @name, @mime, @b64;
    END
    CLOSE c; DEALLOCATE c;
    DECLARE @le UNIQUEIDENTIFIER, @lr UNIQUEIDENTIFIER;
    EXEC [document].[RevisionLink_Add] @RevisionRowId = @RevisionRowId, @LinkKind = N'EvidenceFor', @SubjectKind = N'Record', @SubjectEntityId = @RecordEntityId, @ActorId = @ActorId, @EntityId = @le OUTPUT, @RowId = @lr OUTPUT;
    COMMIT TRANSACTION;
END;
GO
