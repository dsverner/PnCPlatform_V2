-- PROCEDURE-ENGINE §4 "Definitions — projected on approval" (W3). Derives process.ProcedureStep, ProcedureStepRole,
-- ProcedureFactUse and ProcedureCall from a Program.Procedure version's canonical document. The document is
-- authoritative; these rows are rebuilt whenever this runs: the version's live projection rows are soft-deleted and
-- written again (set-based inserts into registry and table, the same rows the generated _Add would write).
-- Called by process.ApproveProcedureVersion in the approval transaction; callable alone to re-project.
CREATE PROCEDURE [process].[ProjectProcedureVersion]
    @VersionRowId UNIQUEIDENTIFIER,
    @ActorId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;

    DECLARE @doc NVARCHAR(MAX), @kind NVARCHAR(40);
    SELECT @doc = dv.[PayloadText], @kind = d.[DefinitionKind]
    FROM [config].[DefinitionVersion] dv JOIN [config].[Definition] d ON d.[EntityId] = dv.[DefinitionEntityId]
    WHERE dv.[RowId] = @VersionRowId AND dv.[IsDeleted] = 0;
    IF @doc IS NULL THROW 50030, N'Unknown definition version.', 1;
    IF @kind <> N'Program.Procedure' THROW 50134, N'Only a Program.Procedure version is projected.', 1;

    SELECT BlockJson, Kind, BlockId, BlockPath, ScopePath, SortKey, ROW_NUMBER() OVER (ORDER BY SortKey) AS Ordinal
    INTO #b FROM [process].[fProcedureBlocks](@doc);

    BEGIN TRANSACTION;
    -- retire the previous projection of this version (soft)
    UPDATE [process].[ProcedureStepRole] SET [IsDeleted] = 1, [DeletedBy] = @ActorId, [DeletedAt] = @now, [ModifiedBy] = @ActorId, [ModifiedAt] = @now
    WHERE [IsDeleted] = 0 AND [ProcedureStepRowId] IN (SELECT [RowId] FROM [process].[ProcedureStep] WHERE [DefinitionVersionRowId] = @VersionRowId AND [IsDeleted] = 0);
    UPDATE [process].[ProcedureStep]    SET [IsDeleted] = 1, [DeletedBy] = @ActorId, [DeletedAt] = @now, [ModifiedBy] = @ActorId, [ModifiedAt] = @now WHERE [DefinitionVersionRowId] = @VersionRowId AND [IsDeleted] = 0;
    UPDATE [process].[ProcedureFactUse] SET [IsDeleted] = 1, [DeletedBy] = @ActorId, [DeletedAt] = @now, [ModifiedBy] = @ActorId, [ModifiedAt] = @now WHERE [DefinitionVersionRowId] = @VersionRowId AND [IsDeleted] = 0;
    UPDATE [process].[ProcedureCall]    SET [IsDeleted] = 1, [DeletedBy] = @ActorId, [DeletedAt] = @now, [ModifiedBy] = @ActorId, [ModifiedAt] = @now WHERE [DefinitionVersionRowId] = @VersionRowId AND [IsDeleted] = 0;

    -- steps
    SELECT NEWID() AS EntityId, NEWID() AS RoleEntityId, s.Ordinal, s.BlockId, s.BlockPath, s.BlockJson,
           JSON_VALUE(s.BlockJson, '$.role') AS RoleAlias,
           JSON_VALUE(r.[value], '$.role') AS RoleCode,
           JSON_QUERY(r.[value], '$.requires') AS RequiresAst
    INTO #steps
    FROM #b s
    LEFT JOIN OPENJSON(@doc, '$.roles') r ON r.[key] COLLATE DATABASE_DEFAULT = JSON_VALUE(s.BlockJson, '$.role')
    WHERE s.Kind = N'step';

    INSERT [process].[ProcedureStepRegistry] ([EntityId]) SELECT EntityId FROM #steps;
    DECLARE @stepRows TABLE ([RowId] UNIQUEIDENTIFIER, [EntityId] UNIQUEIDENTIFIER);
    INSERT [process].[ProcedureStep] ([EntityId], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt],
        [DefinitionVersionRowId], [StepId], [BlockPath], [Ordinal], [Title], [RoleAlias], [RoleCode], [RecordKindCode], [SignoffAction],
        [RequiresWitness], [HasPrecondition], [HasDue], [AllowsDeviation], [AdvancesWorkflowKey], [AdvancesTransition], [ProducesName], [ProducesKind])
    OUTPUT inserted.[RowId], inserted.[EntityId] INTO @stepRows
    SELECT EntityId, @ActorId, @now, @ActorId, @now,
        @VersionRowId, BlockId, BlockPath, Ordinal, LEFT(JSON_VALUE(BlockJson, '$.title'), 200), RoleAlias, RoleCode, JSON_VALUE(BlockJson, '$.record.kind'),
        JSON_VALUE(BlockJson, '$.signoff.action'),
        CASE WHEN JSON_VALUE(BlockJson, '$.signoff.witness') = 'true' THEN 1 ELSE 0 END,
        CASE WHEN JSON_QUERY(BlockJson, '$.precondition') IS NOT NULL THEN 1 ELSE 0 END,
        CASE WHEN JSON_QUERY(BlockJson, '$.due') IS NOT NULL THEN 1 ELSE 0 END,
        CASE WHEN JSON_QUERY(BlockJson, '$.deviation') IS NOT NULL THEN 1 ELSE 0 END,
        JSON_VALUE(BlockJson, '$.advances.workflow'), JSON_VALUE(BlockJson, '$.advances.transition'),
        JSON_VALUE(BlockJson, '$.produces.as'), JSON_VALUE(BlockJson, '$.produces.kind')
    FROM #steps;

    -- step roles (one row per step: the alias's role code and its competency expression, if any)
    INSERT [process].[ProcedureStepRoleRegistry] ([EntityId]) SELECT RoleEntityId FROM #steps;
    INSERT [process].[ProcedureStepRole] ([EntityId], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt], [ProcedureStepRowId], [RoleCode], [RequiresAst])
    SELECT s.RoleEntityId, @ActorId, @now, @ActorId, @now, sr.[RowId], s.RoleCode, s.RequiresAst
    FROM #steps s JOIN @stepRows sr ON sr.[EntityId] = s.EntityId;

    -- fact uses: every expression site of every block, plus each role alias's competency expression
    SELECT NEWID() AS EntityId, u.BlockPath, u.FactName
    INTO #facts
    FROM (
        SELECT DISTINCT b.BlockPath, f.[FactName]
        FROM #b b CROSS APPLY [process].[fExpressionSites](b.BlockJson) e CROSS APPLY [compliance].[fPayloadFactNames](e.Expr) f
        UNION
        SELECT DISTINCT N'roles/' + r.[key] COLLATE DATABASE_DEFAULT, f.[FactName]
        FROM OPENJSON(@doc, '$.roles') r CROSS APPLY [compliance].[fPayloadFactNames](JSON_QUERY(r.[value], '$.requires')) f
        WHERE JSON_QUERY(r.[value], '$.requires') IS NOT NULL
    ) u;
    INSERT [process].[ProcedureFactUseRegistry] ([EntityId]) SELECT EntityId FROM #facts;
    INSERT [process].[ProcedureFactUse] ([EntityId], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt], [DefinitionVersionRowId], [BlockPath], [FactName])
    SELECT EntityId, @ActorId, @now, @ActorId, @now, @VersionRowId, BlockPath, FactName FROM #facts;

    -- calls
    SELECT NEWID() AS EntityId, BlockPath, JSON_VALUE(BlockJson, '$.procedure') AS CalleeKey INTO #calls FROM #b WHERE Kind = N'call';
    INSERT [process].[ProcedureCallRegistry] ([EntityId]) SELECT EntityId FROM #calls;
    INSERT [process].[ProcedureCall] ([EntityId], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt], [DefinitionVersionRowId], [BlockPath], [CalleeKey])
    SELECT EntityId, @ActorId, @now, @ActorId, @now, @VersionRowId, BlockPath, CalleeKey FROM #calls;

    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'process', @SubjectTable = N'ProcedureStep',
         @SubjectRowId = @VersionRowId, @DefinitionVersionRowId = @VersionRowId, @ActorId = @ActorId,
         @Detail = N'{"action":"projected"}';
    COMMIT TRANSACTION;
END;
GO
