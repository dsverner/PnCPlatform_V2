-- #192 (2026-09-18): freeze the basis as it stands — the basis's parsed rows as basis.json (role Attachment) on the draft
-- that was taken from it. The newest basis-<n>.json on a revision is its frozen basis (process.fBasisDrift reads it); an
-- older one is history and stays. Without this file nothing could say whose change was whose once both drafts moved.
CREATE PROCEDURE [process].[WriteBasisSnapshot]
    @RevisionRowId UNIQUEIDENTIFIER,
    @BasisRevisionRowId UNIQUEIDENTIFIER,
    @ActorId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @json NVARCHAR(MAX) = ISNULL((SELECT [SettingCode] AS c, ISNULL([GroupNumber], 1) AS g, [RawValue] AS v
                                          FROM [document].[vParsedSettingNamed] WHERE [ConfigurationFileRevisionRowId] = @BasisRevisionRowId
                                          ORDER BY [SettingCode], [GroupNumber] FOR JSON PATH), N'[]');
    DECLARE @bytes VARBINARY(MAX) = CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX), @json));
    -- one name per snapshot: File_Write refuses a second file of the same name on a revision (50133); the readers take the newest basis-*.json
    DECLARE @n INT = 1 + (SELECT COUNT(*) FROM [document].[vFile] f WHERE f.[RevisionRowId] = @RevisionRowId AND f.[FileRole] = N'Attachment' AND f.[FileName] LIKE N'basis-%.json');
    DECLARE @fname NVARCHAR(255) = CONCAT(N'basis-', @n, N'.json');
    DECLARE @fsid UNIQUEIDENTIFIER, @fe UNIQUEIDENTIFIER, @fr UNIQUEIDENTIFIER;
    EXEC [document].[File_Write] @RevisionRowId = @RevisionRowId, @FileName = @fname, @MimeType = N'application/json', @Content = @bytes, @FileRole = N'Attachment',
         @ActorId = @ActorId, @FileStreamId = @fsid OUTPUT, @EntityId = @fe OUTPUT, @RowId = @fr OUTPUT;
END;
GO
