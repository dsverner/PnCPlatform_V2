-- SCHEMA-DESIGN §2.1. Creates a definition (registry + first row). Lifted from the gate toy.
CREATE PROCEDURE [config].[AddDefinition]
    @DefinitionKind NVARCHAR(40),
    @DefinitionKey NVARCHAR(100),
    @Name NVARCHAR(200),
    @Description NVARCHAR(MAX) = NULL,
    @OwningRoleCode NVARCHAR(40) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,
    @EntityId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [ref].[DefinitionKind] WHERE [DefinitionKind] = @DefinitionKind AND [IsActive] = 1)
        THROW 50020, N'Unknown or inactive definition kind.', 1;
    IF EXISTS (SELECT 1 FROM [config].[Definition] WHERE [DefinitionKind] = @DefinitionKind AND [DefinitionKey] = @DefinitionKey AND [IsDeleted] = 0)
        THROW 50021, N'A definition with that kind and key already exists.', 1;
    EXEC [config].[Definition_Add]
        @DefinitionKind = @DefinitionKind, @DefinitionKey = @DefinitionKey, @Name = @Name, @Description = @Description,
        @OwningRoleCode = @OwningRoleCode, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @EntityId OUTPUT;
END;
GO
