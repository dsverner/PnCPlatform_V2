-- SCHEMA-DESIGN §11.7 (decision 158); vision §9.5. The three segregation rules the design states
-- literally, as one Program.SegregationRule definition, mode WarnAndLog (the design's default: the
-- same person may proceed with a stated reason, and the override is logged). The Administrator
-- adds rules or switches a rule to Block as a new version. Idempotent: an existing key is left alone.
-- Payload shape is the implementation choice recorded in STEPS.md step 11 (security.CheckSegregation).
IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @author   UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';
IF NOT EXISTS (SELECT 1 FROM [personnel].[Actor] WHERE [ActorId] = @approver)
    INSERT [personnel].[Actor] ([ActorId], [ActorKind], [SystemName]) VALUES (@approver, N'System', N'Platform.SeedApprover');

IF NOT EXISTS (SELECT 1 FROM [config].[Definition] WHERE [DefinitionKind] = N'Program.SegregationRule' AND [DefinitionKey] = N'DefaultSegregation' AND [IsDeleted] = 0)
BEGIN
    DECLARE @defEntity UNIQUEIDENTIFIER, @verRowId UNIQUEIDENTIFIER, @verNo INT;
    DECLARE @payload NVARCHAR(MAX) = N'{"rules":[' +
        N'{"actionA":"Prepare","actionB":"Approve","subjectKind":"ConfigurationFileRevision","mode":"WarnAndLog"},' +
        N'{"actionA":"Author","actionB":"Approve","subjectKind":"DefinitionVersion","mode":"WarnAndLog"},' +
        N'{"actionA":"Test","actionB":"Accept","subjectKind":"Record","mode":"WarnAndLog"}]}';
    EXEC [config].[AddDefinition] @DefinitionKind = N'Program.SegregationRule', @DefinitionKey = N'DefaultSegregation',
         @Name = N'Segregation of duties — design defaults (§11.7)', @ActorId = @author, @EntityId = @defEntity OUTPUT;
    EXEC [config].[AddDefinitionVersion] @DefinitionKey = N'DefaultSegregation', @DefinitionKind = N'Program.SegregationRule',
         @ChangeNote = N'seed', @PayloadText = @payload, @ActorId = @author, @VersionRowId = @verRowId OUTPUT, @VersionNumber = @verNo OUTPUT;
    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @verRowId, @ActorId = @approver;
END
GO
