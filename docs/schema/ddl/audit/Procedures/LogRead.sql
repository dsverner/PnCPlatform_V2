-- SCHEMA-DESIGN §1.3 (decision 65). Read logging for object classes switched on in
-- config.ReadLoggedClass. The application calls this when it serves a row of a logged class;
-- it is a no-op for classes not switched on, so callers need not check first.
CREATE PROCEDURE [audit].[LogRead]
    @SubjectSchema SYSNAME,
    @SubjectTable SYSNAME,
    @SubjectEntityId UNIQUEIDENTIFIER = NULL,
    @SubjectRowId UNIQUEIDENTIFIER = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [config].[ReadLoggedClass]
                   WHERE [SchemaName] = @SubjectSchema AND [TableName] = @SubjectTable AND [IsLogged] = 1 AND [IsActive] = 1)
        RETURN;
    EXEC [audit].[LogAction] @ActionKindCode = N'Read', @SubjectSchema = @SubjectSchema, @SubjectTable = @SubjectTable,
                             @SubjectEntityId = @SubjectEntityId, @SubjectRowId = @SubjectRowId, @ActorId = @ActorId;
END;
GO
