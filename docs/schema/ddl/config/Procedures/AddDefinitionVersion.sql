-- SCHEMA-DESIGN §2.2 (74, 78). Adds a Draft version. Programs require PayloadText; schemas
-- and transforms refuse it. PayloadHash = SHA-256 of the payload.
-- A program payload is validated against compliance.vFactCatalogue (§12.3) before it is stored.
CREATE PROCEDURE [config].[AddDefinitionVersion]
    @DefinitionKey NVARCHAR(100),
    @DefinitionKind NVARCHAR(40) = NULL,          -- disambiguates when the same key exists under several kinds
    @ChangeNote NVARCHAR(MAX) = NULL,
    @PayloadText NVARCHAR(MAX) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,
    @VersionRowId UNIQUEIDENTIFIER = NULL OUTPUT,
    @VersionNumber INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @defEntity UNIQUEIDENTIFIER, @kind NVARCHAR(40), @hasPayload BIT;
    SELECT @defEntity = d.[EntityId], @kind = d.[DefinitionKind], @hasPayload = k.[HasPayloadText]
    FROM [config].[Definition] d JOIN [ref].[DefinitionKind] k ON k.[DefinitionKind] = d.[DefinitionKind]
    WHERE d.[DefinitionKey] = @DefinitionKey AND d.[IsDeleted] = 0
      AND (@DefinitionKind IS NULL OR d.[DefinitionKind] = @DefinitionKind);
    IF @defEntity IS NULL THROW 50022, N'Unknown definition key.', 1;
    IF @@ROWCOUNT > 1 THROW 50023, N'Definition key is ambiguous across kinds; pass @DefinitionKind.', 1;

    IF @hasPayload = 1 AND @PayloadText IS NULL THROW 50024, N'Program definitions require a payload.', 1;
    IF @hasPayload = 0 AND @PayloadText IS NOT NULL THROW 50025, N'Only program definitions carry PayloadText (decision 78).', 1;
    IF @hasPayload = 1 EXEC [compliance].[ValidateProgramFacts] @PayloadText, @kind;

    SELECT @VersionNumber = ISNULL(MAX([VersionNumber]), 0) + 1 FROM [config].[DefinitionVersion] WHERE [DefinitionEntityId] = @defEntity AND [IsDeleted] = 0;
    DECLARE @hash BINARY(32) = CASE WHEN @PayloadText IS NULL THEN NULL ELSE HASHBYTES('SHA2_256', @PayloadText) END;
    EXEC [config].[DefinitionVersion_Add]
        @DefinitionEntityId = @defEntity, @VersionNumber = @VersionNumber, @Status = N'Draft',
        @ChangeNote = @ChangeNote, @PayloadText = @PayloadText, @PayloadHash = @hash,
        @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @RowId = @VersionRowId OUTPUT;
END;
GO
