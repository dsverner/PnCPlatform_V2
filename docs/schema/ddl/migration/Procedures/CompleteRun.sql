-- SCHEMA-DESIGN §1.2. The one permitted change to a migration.Run row after it is appended.
CREATE PROCEDURE [migration].[CompleteRun]
    @RunId UNIQUEIDENTIFIER,
    @Notes NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE [migration].[Run]
       SET [CompletedAt] = SYSDATETIMEOFFSET(),
           [Notes] = CASE WHEN @Notes IS NULL THEN [Notes] ELSE @Notes END
     WHERE [RunId] = @RunId AND [CompletedAt] IS NULL;
    IF @@ROWCOUNT = 0 THROW 50011, N'migration.Run: no open run with @RunId.', 1;
END;
GO
