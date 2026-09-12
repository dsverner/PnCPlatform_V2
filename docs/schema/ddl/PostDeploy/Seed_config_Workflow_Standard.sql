-- PLATFORM-ARCHITECTURE §3.4 (decision 247). One effective Program.Workflow and one Program.WorkType so a fresh
-- deploy has a workflow the surface can render and a work type a request can be raised under. The payload is in
-- the shape work.StartWorkflow / work.Transition read ($.states, $.initial, $.final, $.transitions[name, from, to,
-- requiresReason, guard]). The migrated predecessor workflows stay Draft (MIGRATION-PLAN M-rules). Idempotent.
IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @author   UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';
IF NOT EXISTS (SELECT 1 FROM [personnel].[Actor] WHERE [ActorId] = @approver)
    INSERT [personnel].[Actor] ([ActorId], [ActorKind], [SystemName]) VALUES (@approver, N'System', N'Platform.SeedApprover');

-- W3 (decision #103): Program.Workflow documents now follow docs/design/workflow.schema.json and are loaded through the
-- API (process.AddWorkflowVersion); this pre-W3 payload shape is retired. On a database that carries the seed, its
-- Effective version is set Retired (soft; the rows stay); on a fresh database the workflow is no longer seeded.
UPDATE dv SET dv.[Status] = N'Retired', dv.[EffectiveTo] = SYSDATETIMEOFFSET(), dv.[ModifiedBy] = @author, dv.[ModifiedAt] = SYSDATETIMEOFFSET()
FROM [config].[DefinitionVersion] dv JOIN [config].[Definition] d ON d.[EntityId] = dv.[DefinitionEntityId]
WHERE d.[DefinitionKind] = N'Program.Workflow' AND d.[DefinitionKey] = N'Standard' AND d.[IsDeleted] = 0 AND dv.[IsDeleted] = 0 AND dv.[Status] = N'Effective';

IF 1 = 0 AND NOT EXISTS (SELECT 1 FROM [config].[Definition] WHERE [DefinitionKind] = N'Program.Workflow' AND [DefinitionKey] = N'Standard' AND [IsDeleted] = 0)
BEGIN
    DECLARE @defEntity UNIQUEIDENTIFIER, @verRowId UNIQUEIDENTIFIER, @verNo INT;
    EXEC [config].[AddDefinition] @DefinitionKind = N'Program.Workflow', @DefinitionKey = N'Standard',
         @Name = N'Standard work request workflow (PLATFORM-ARCHITECTURE §3.4)', @ActorId = @author, @EntityId = @defEntity OUTPUT;
    EXEC [config].[AddDefinitionVersion] @DefinitionKey = N'Standard', @DefinitionKind = N'Program.Workflow', @ChangeNote = N'seed',
         @PayloadText = N'{"states":["Draft","Assigned","InProgress","Review","Closed","Cancelled"],"initial":"Draft","final":["Closed","Cancelled"],
"transitions":[
 {"name":"Assign","from":"Draft","to":"Assigned","requiresReason":false},
 {"name":"Start","from":"Assigned","to":"InProgress","requiresReason":false},
 {"name":"Submit for review","from":"InProgress","to":"Review","requiresReason":false},
 {"name":"Return","from":"Review","to":"InProgress","requiresReason":true},
 {"name":"Close","from":"Review","to":"Closed","requiresReason":false},
 {"name":"Cancel","from":"Draft","to":"Cancelled","requiresReason":true},
 {"name":"Cancel","from":"Assigned","to":"Cancelled","requiresReason":true},
 {"name":"Cancel","from":"InProgress","to":"Cancelled","requiresReason":true}]}',
         @ActorId = @author, @VersionRowId = @verRowId OUTPUT, @VersionNumber = @verNo OUTPUT;
    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @verRowId, @ActorId = @approver;
END

IF NOT EXISTS (SELECT 1 FROM [config].[Definition] WHERE [DefinitionKind] = N'Program.WorkType' AND [DefinitionKey] = N'Standard' AND [IsDeleted] = 0)
BEGIN
    DECLARE @wtEntity UNIQUEIDENTIFIER, @wtRowId UNIQUEIDENTIFIER, @wtNo INT;
    EXEC [config].[AddDefinition] @DefinitionKind = N'Program.WorkType', @DefinitionKey = N'Standard',
         @Name = N'Standard work (runs the Standard workflow)', @ActorId = @author, @EntityId = @wtEntity OUTPUT;
    EXEC [config].[AddDefinitionVersion] @DefinitionKey = N'Standard', @DefinitionKind = N'Program.WorkType', @ChangeNote = N'seed',
         @PayloadText = N'{"workflow":"Standard","requiredRecordKinds":[],"defaultTestPlan":null}',
         @ActorId = @author, @VersionRowId = @wtRowId OUTPUT, @VersionNumber = @wtNo OUTPUT;
    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @wtRowId, @ActorId = @approver;
END
GO
