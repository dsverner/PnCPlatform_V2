-- SCHEMA-DESIGN §2.4 (76). Adds a characteristic to a Draft characteristic-schema version.
CREATE PROCEDURE [config].[AddCharacteristic]
    @DefinitionVersionRowId UNIQUEIDENTIFIER,
    @CharacteristicKey NVARCHAR(100),
    @Name NVARCHAR(200),
    @DataType NVARCHAR(20),
    @Description NVARCHAR(MAX) = NULL,
    @UnitCode NVARCHAR(20) = NULL,
    @Base NVARCHAR(20) = NULL,
    @IsRequired BIT = 0,
    @AllowedValuesDefinitionRowId UNIQUEIDENTIFIER = NULL,
    @ReferenceTargetKind NVARCHAR(40) = NULL,
    @ValidationExpression NVARCHAR(MAX) = NULL,
    @DisplayOrder INT = 0,
    @DisplayGroup NVARCHAR(100) = NULL,
    @IsCatalogueFact BIT = 0,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,
    @RowId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @status NVARCHAR(20), @kind NVARCHAR(40);
    SELECT @status = v.[Status], @kind = d.[DefinitionKind]
    FROM [config].[DefinitionVersion] v JOIN [config].[Definition] d ON d.[EntityId] = v.[DefinitionEntityId] AND d.[IsDeleted] = 0
    WHERE v.[RowId] = @DefinitionVersionRowId AND v.[IsDeleted] = 0;
    IF @status IS NULL THROW 50026, N'Unknown definition version.', 1;
    IF @kind NOT LIKE N'CharacteristicSchema.%' THROW 50027, N'Characteristics belong to CharacteristicSchema definitions only.', 1;
    IF @status <> N'Draft' THROW 50028, N'Characteristics may be added to Draft versions only.', 1;
    IF @AllowedValuesDefinitionRowId IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM [config].[DefinitionVersion] v JOIN [config].[Definition] d ON d.[EntityId] = v.[DefinitionEntityId]
        WHERE v.[RowId] = @AllowedValuesDefinitionRowId AND d.[DefinitionKind] = N'CharacteristicSchema.Enumeration')
        THROW 50029, N'AllowedValuesDefinitionRowId must be an Enumeration definition version.', 1;

    EXEC [config].[CharacteristicDefinition_Add]
        @DefinitionVersionRowId = @DefinitionVersionRowId, @CharacteristicKey = @CharacteristicKey, @Name = @Name, @Description = @Description,
        @DataType = @DataType, @UnitCode = @UnitCode, @Base = @Base, @IsRequired = @IsRequired,
        @AllowedValuesDefinitionRowId = @AllowedValuesDefinitionRowId, @ReferenceTargetKind = @ReferenceTargetKind,
        @ValidationExpression = @ValidationExpression, @DisplayOrder = @DisplayOrder, @DisplayGroup = @DisplayGroup,
        @IsCatalogueFact = @IsCatalogueFact, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @RowId = @RowId OUTPUT;
END;
GO
