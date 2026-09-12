-- PROCEDURE-ENGINE §2 (W3). The workflow counterpart of process.AddProcedureVersion: a canonical workflow document
-- (workflow.schema.json) becomes a Draft Program.Workflow version; idempotent on content (@Existing = 1 when the
-- same hash is already stored). Structural rules: process.ValidateWorkflowDocument; fact names: config.AddDefinitionVersion.
CREATE PROCEDURE [process].[AddWorkflowVersion]
    @Canonical NVARCHAR(MAX),
    @ChangeNote NVARCHAR(MAX) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @DefinitionEntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @VersionRowId UNIQUEIDENTIFIER = NULL OUTPUT,
    @VersionNumber INT = NULL OUTPUT,
    @Existing BIT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    EXEC [process].[ValidateWorkflowDocument] @Canonical;

    DECLARE @key NVARCHAR(100) = JSON_VALUE(@Canonical, '$.key'),
            @name NVARCHAR(200) = ISNULL(JSON_VALUE(@Canonical, '$.name'), JSON_VALUE(@Canonical, '$.key')),
            @description NVARCHAR(MAX) = JSON_VALUE(@Canonical, '$.description'),
            @hash BINARY(32) = HASHBYTES('SHA2_256', @Canonical);
    SET @Existing = 0;

    SELECT @DefinitionEntityId = [EntityId] FROM [config].[Definition]
    WHERE [DefinitionKind] = N'Program.Workflow' AND [DefinitionKey] = @key AND [IsDeleted] = 0;

    IF @DefinitionEntityId IS NOT NULL
    BEGIN
        SELECT @VersionRowId = [RowId], @VersionNumber = [VersionNumber], @Existing = 1
        FROM [config].[DefinitionVersion]
        WHERE [DefinitionEntityId] = @DefinitionEntityId AND [IsDeleted] = 0 AND [PayloadHash] = @hash
          AND [Status] IN (N'Draft', N'Approved', N'Effective');
        IF @Existing = 1 RETURN;
    END

    BEGIN TRANSACTION;
    IF @DefinitionEntityId IS NULL
        EXEC [config].[AddDefinition] @DefinitionKind = N'Program.Workflow', @DefinitionKey = @key, @Name = @name,
             @Description = @description, @ActorId = @ActorId, @EntityId = @DefinitionEntityId OUTPUT;
    EXEC [config].[AddDefinitionVersion] @DefinitionKey = @key, @DefinitionKind = N'Program.Workflow', @ChangeNote = @ChangeNote,
         @PayloadText = @Canonical, @ActorId = @ActorId, @VersionRowId = @VersionRowId OUTPUT, @VersionNumber = @VersionNumber OUTPUT;
    COMMIT TRANSACTION;
END;
GO
