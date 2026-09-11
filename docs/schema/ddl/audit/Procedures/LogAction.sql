-- SCHEMA-DESIGN §1.1. The only write path into audit.ActionLog.
CREATE PROCEDURE [audit].[LogAction]
    @ActionKindCode NVARCHAR(50),
    @SubjectSchema SYSNAME = NULL,
    @SubjectTable SYSNAME = NULL,
    @SubjectEntityId UNIQUEIDENTIFIER = NULL,
    @SubjectRowId UNIQUEIDENTIFIER = NULL,
    @DefinitionVersionRowId UNIQUEIDENTIFIER = NULL,
    @Detail NVARCHAR(MAX) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @OccurredAt DATETIMEOFFSET(7) = NULL,
    @ActionLogId BIGINT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    INSERT [audit].[ActionLog] ([OccurredAt], [ActorId], [ActionKindCode], [SubjectSchema], [SubjectTable], [SubjectEntityId], [SubjectRowId], [DefinitionVersionRowId], [Detail])
    VALUES (ISNULL(@OccurredAt, SYSDATETIMEOFFSET()), @ActorId, @ActionKindCode, @SubjectSchema, @SubjectTable, @SubjectEntityId, @SubjectRowId, @DefinitionVersionRowId, @Detail);
    SET @ActionLogId = SCOPE_IDENTITY();
END;
GO
