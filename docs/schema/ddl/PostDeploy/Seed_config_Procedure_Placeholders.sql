-- W3 (plan Q1, decision #102): the SETTINGS_CHANGE example calls DRAWING_REVISION, which is authored in W5 (the first
-- procedure written in the tool). process.ValidateProcedureDocument requires a call's key to exist as a Program.Procedure
-- definition (any version; W4's pinning will require an Effective one), so the definition exists from here with no
-- version. Idempotent; W5 adds its first version through the API.
IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @author UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
IF NOT EXISTS (SELECT 1 FROM [config].[Definition] WHERE [DefinitionKind] = N'Program.Procedure' AND [DefinitionKey] = N'DRAWING_REVISION' AND [IsDeleted] = 0)
BEGIN
    DECLARE @e UNIQUEIDENTIFIER;
    EXEC [config].[AddDefinition] @DefinitionKind = N'Program.Procedure', @DefinitionKey = N'DRAWING_REVISION',
         @Name = N'Drawing revision', @Description = N'Placeholder definition (W3): the procedure is authored in W5; SETTINGS_CHANGE calls it.',
         @ActorId = @author, @EntityId = @e OUTPUT;
END
GO
