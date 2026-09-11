-- PLATFORM-ARCHITECTURE §1.4 (200), §8.1 (226); SCHEMA-DESIGN §15.6 (234). The record template for a
-- PlatformDeployment record (subject: the platform): the relocation / deployment checklist outcome as
-- characteristics, so a deployment run is evidence in the same shape as a test sheet. Idempotent: an
-- existing key is left alone; a change is a new version authored by the Administrator.
IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @author   UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';
IF NOT EXISTS (SELECT 1 FROM [personnel].[Actor] WHERE [ActorId] = @approver)
    INSERT [personnel].[Actor] ([ActorId], [ActorKind], [SystemName]) VALUES (@approver, N'System', N'Platform.SeedApprover');

IF NOT EXISTS (SELECT 1 FROM [config].[Definition] WHERE [DefinitionKind] = N'CharacteristicSchema.RecordTemplate' AND [DefinitionKey] = N'PlatformDeployment' AND [IsDeleted] = 0)
BEGIN
    DECLARE @defEntity UNIQUEIDENTIFIER, @verRowId UNIQUEIDENTIFIER, @verNo INT, @c UNIQUEIDENTIFIER;
    EXEC [config].[AddDefinition] @DefinitionKind = N'CharacteristicSchema.RecordTemplate', @DefinitionKey = N'PlatformDeployment',
         @Name = N'Platform deployment / relocation checklist (PLATFORM-ARCHITECTURE §1.4, §9)', @ActorId = @author, @EntityId = @defEntity OUTPUT;
    EXEC [config].[AddDefinitionVersion] @DefinitionKey = N'PlatformDeployment', @DefinitionKind = N'CharacteristicSchema.RecordTemplate',
         @ChangeNote = N'seed', @ActorId = @author, @VersionRowId = @verRowId OUTPUT, @VersionNumber = @verNo OUTPUT;
    EXEC [config].[AddCharacteristic] @DefinitionVersionRowId = @verRowId, @CharacteristicKey = N'environment', @Name = N'Environment', @DataType = N'Text', @IsRequired = 1, @DisplayOrder = 1, @ActorId = @author, @RowId = @c OUTPUT;
    EXEC [config].[AddCharacteristic] @DefinitionVersionRowId = @verRowId, @CharacteristicKey = N'release_version', @Name = N'Release version', @DataType = N'Text', @IsRequired = 1, @DisplayOrder = 2, @ActorId = @author, @RowId = @c OUTPUT;
    EXEC [config].[AddCharacteristic] @DefinitionVersionRowId = @verRowId, @CharacteristicKey = N'checklist_step', @Name = N'Checklist step reached (1-7, PLATFORM-ARCHITECTURE §1.4)', @DataType = N'Integer', @DisplayOrder = 3, @ActorId = @author, @RowId = @c OUTPUT;
    EXEC [config].[AddCharacteristic] @DefinitionVersionRowId = @verRowId, @CharacteristicKey = N'temporary_rule_closed', @Name = N'Temporary Business to OT rule closed', @DataType = N'Boolean', @DisplayOrder = 4, @ActorId = @author, @RowId = @c OUTPUT;
    EXEC [config].[AddCharacteristic] @DefinitionVersionRowId = @verRowId, @CharacteristicKey = N'feed_pull_ok', @Name = N'Satellite feed pull completed (F3)', @DataType = N'Boolean', @DisplayOrder = 5, @ActorId = @author, @RowId = @c OUTPUT;
    EXEC [config].[AddCharacteristic] @DefinitionVersionRowId = @verRowId, @CharacteristicKey = N'inbound_refused', @Name = N'Business to OT connection attempt refused', @DataType = N'Boolean', @DisplayOrder = 6, @ActorId = @author, @RowId = @c OUTPUT;
    EXEC [config].[AddCharacteristic] @DefinitionVersionRowId = @verRowId, @CharacteristicKey = N'notes', @Name = N'Notes', @DataType = N'Text', @DisplayOrder = 7, @ActorId = @author, @RowId = @c OUTPUT;
    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @verRowId, @ActorId = @approver;
END
-- the record kind names its template (ref.RecordKind is seeded before this definition exists)
UPDATE k SET k.[TemplateDefinitionEntityId] = d.[EntityId]
FROM [ref].[RecordKind] k JOIN [config].[Definition] d ON d.[DefinitionKind] = N'CharacteristicSchema.RecordTemplate' AND d.[DefinitionKey] = N'PlatformDeployment' AND d.[IsDeleted] = 0
WHERE k.[RecordKindCode] = N'PlatformDeployment' AND k.[TemplateDefinitionEntityId] IS NULL;
GO
