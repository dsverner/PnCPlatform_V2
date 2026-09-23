-- #228 (2026-09-22): a repair, not a migration rule. Until #228 cancelling a workflow left the procedure runs it had started
-- Running and what they produced (the settings package's lifecycle) where it was; process.Transition now cancels them as
-- the workflow enters its cancellation state. This carries the same cascade to workflows cancelled before that, so no run
-- outlives the request that started it: open runs cancelled deepest child first, then every still-open workflow on what
-- they produced taken to its own cancellation state, following the original cancel. A produced workflow with no way to its
-- cancellation state from where it stands is left as it is and reported. Idempotent: once repaired, nothing is found.
-- On DEV on 2026-09-22 this was five browser proofs of #187, #191 and #192.
IF OBJECT_ID(N'[process].[CompleteInstance]') IS NULL RETURN;   -- bootstrap (tables-only) publish
DECLARE @a UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001', @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
DECLARE @work TABLE ([RunEntityId] UNIQUEIDENTIFIER PRIMARY KEY, [Depth] INT, [Reason] NVARCHAR(400), [CancelTransitionId] BIGINT, [Produced] NVARCHAR(MAX));
;WITH cancelled AS (
    SELECT w.[EntityId], (SELECT TOP (1) t.[TransitionId] FROM [process].[WorkflowTransition] t WHERE t.[WorkflowInstanceEntityId] = w.[EntityId] ORDER BY t.[OccurredAt] DESC, t.[TransitionId] DESC) AS [TransitionId],
           (SELECT TOP (1) t.[Reason] FROM [process].[WorkflowTransition] t WHERE t.[WorkflowInstanceEntityId] = w.[EntityId] ORDER BY t.[OccurredAt] DESC, t.[TransitionId] DESC) AS [Reason]
    FROM [process].[WorkflowInstance] w WHERE w.[IsDeleted] = 0 AND w.[IsCancelled] = 1),
tree AS (
    SELECT p.[EntityId], 0 AS [Depth], c.[Reason], c.[TransitionId] FROM [process].[ProcedureInstance] p JOIN cancelled c ON c.[EntityId] = p.[WorkflowInstanceEntityId]
     WHERE p.[ParentInstanceEntityId] IS NULL AND p.[IsDeleted] = 0
    UNION ALL
    SELECT ch.[EntityId], tree.[Depth] + 1, tree.[Reason], tree.[TransitionId] FROM [process].[ProcedureInstance] ch JOIN tree ON ch.[ParentInstanceEntityId] = tree.[EntityId] WHERE ch.[IsDeleted] = 0)
INSERT @work ([RunEntityId], [Depth], [Reason], [CancelTransitionId], [Produced])
SELECT tree.[EntityId], tree.[Depth], tree.[Reason], tree.[TransitionId], p.[Produced]
  FROM tree JOIN [process].[ProcedureInstance] p ON p.[EntityId] = tree.[EntityId];

-- the runs still open, deepest first
DECLARE @run UNIQUEIDENTIFIER, @why NVARCHAR(400), @n INT = 0;
DECLARE rc CURSOR LOCAL FAST_FORWARD FOR
    SELECT w.[RunEntityId], ISNULL(NULLIF(LTRIM(RTRIM(w.[Reason])), N''), N'the request it belonged to was cancelled')
      FROM @work w JOIN [process].[ProcedureInstance] p ON p.[EntityId] = w.[RunEntityId] AND p.[State] NOT IN (N'Completed', N'Cancelled')
     ORDER BY w.[Depth] DESC;
OPEN rc; FETCH NEXT FROM rc INTO @run, @why;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF EXISTS (SELECT 1 FROM [process].[ProcedureInstance] WHERE [EntityId] = @run AND [IsDeleted] = 0 AND [State] NOT IN (N'Completed', N'Cancelled'))
    BEGIN
        EXEC [process].[CompleteInstance] @ProcedureInstanceEntityId = @run, @State = N'Cancelled', @Reason = @why, @At = @now, @ActorId = @a;
        SET @n += 1;
    END
    FETCH NEXT FROM rc INTO @run, @why;
END
CLOSE rc; DEALLOCATE rc;

-- what they produced that is still open, taken to its own cancellation state where its definition allows it
DECLARE @dw UNIQUEIDENTIFIER, @dname NVARCHAR(100), @dstate NVARCHAR(40), @cause BIGINT, @dto NVARCHAR(40), @did BIGINT, @m INT = 0;
DECLARE dc CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT dw.[EntityId],
           (SELECT TOP (1) JSON_VALUE(tr.[value], '$.name') FROM OPENJSON(dv.[PayloadText], '$.transitions') tr
              JOIN OPENJSON(dv.[PayloadText], '$.states') st ON JSON_VALUE(st.[value], '$.code') = JSON_VALUE(tr.[value], '$.to')
             WHERE JSON_VALUE(tr.[value], '$.from') = dw.[CurrentState] AND JSON_VALUE(st.[value], '$.cancellation') = 'true'),
           dw.[CurrentState], w.[CancelTransitionId], ISNULL(NULLIF(LTRIM(RTRIM(w.[Reason])), N''), N'the request it belonged to was cancelled')
      FROM @work w CROSS APPLY OPENJSON(w.[Produced]) pr
      JOIN [process].[WorkflowInstance] dw ON dw.[SubjectEntityId] = TRY_CONVERT(UNIQUEIDENTIFIER, pr.[value]) AND dw.[IsDeleted] = 0 AND dw.[CompletedAt] IS NULL
      JOIN [config].[DefinitionVersion] dv ON dv.[RowId] = dw.[WorkflowDefinitionVersionRowId]
     WHERE w.[Produced] IS NOT NULL AND ISJSON(w.[Produced]) = 1 AND TRY_CONVERT(UNIQUEIDENTIFIER, pr.[value]) IS NOT NULL;
OPEN dc; FETCH NEXT FROM dc INTO @dw, @dname, @dstate, @cause, @why;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF @dname IS NULL
        PRINT CONCAT(N'#228 repair: workflow ', @dw, N' is ', @dstate, N' and has no way to be withdrawn; left as it is.');
    ELSE
    BEGIN
        EXEC [process].[Transition] @WorkflowInstanceEntityId = @dw, @TransitionName = @dname, @Reason = @why, @At = @now, @ActorId = @a,
             @CascadeFromTransitionId = @cause, @ToState = @dto OUTPUT, @TransitionId = @did OUTPUT;
        SET @m += 1;
    END
    FETCH NEXT FROM dc INTO @dw, @dname, @dstate, @cause, @why;
END
CLOSE dc; DEALLOCATE dc;
IF @n + @m > 0 PRINT CONCAT(N'#228 repair: ', @n, N' run(s) cancelled, ', @m, N' produced workflow(s) withdrawn, under requests cancelled before #228.');
GO
