-- PROCEDURE-ENGINE §3, §8 (W3). Stores a canonical procedure document as a Draft Program.Procedure version, creating the
-- definition on first use. The API has already validated the JSON Schema, parsed and type-checked every expression and
-- produced the canonical text (decision #100); this procedure applies the structural rules and the fact-name check
-- (through config.AddDefinitionVersion → compliance.ValidateProgramFacts) and stores. Idempotent on content: when the
-- definition's current Effective version carries the same PayloadHash, nothing is added and that version is returned
-- with @Existing = 1 (decision #102: the example documents are loaded through the API and kept).
CREATE PROCEDURE [process].[AddProcedureVersion]
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
    EXEC [process].[ValidateProcedureDocument] @Canonical;

    DECLARE @key NVARCHAR(100) = JSON_VALUE(@Canonical, '$.key'),
            @name NVARCHAR(200) = ISNULL(JSON_VALUE(@Canonical, '$.name'), JSON_VALUE(@Canonical, '$.key')),
            @description NVARCHAR(MAX) = JSON_VALUE(@Canonical, '$.description'),
            @hash BINARY(32) = HASHBYTES('SHA2_256', @Canonical);
    SET @Existing = 0;

    SELECT @DefinitionEntityId = [EntityId] FROM [config].[Definition]
    WHERE [DefinitionKind] = N'Program.Procedure' AND [DefinitionKey] = @key AND [IsDeleted] = 0;

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
        EXEC [config].[AddDefinition] @DefinitionKind = N'Program.Procedure', @DefinitionKey = @key, @Name = @name,
             @Description = @description, @ActorId = @ActorId, @EntityId = @DefinitionEntityId OUTPUT;
    EXEC [config].[AddDefinitionVersion] @DefinitionKey = @key, @DefinitionKind = N'Program.Procedure', @ChangeNote = @ChangeNote,
         @PayloadText = @Canonical, @ActorId = @ActorId, @VersionRowId = @VersionRowId OUTPUT, @VersionNumber = @VersionNumber OUTPUT;
    COMMIT TRANSACTION;
END;
GO
