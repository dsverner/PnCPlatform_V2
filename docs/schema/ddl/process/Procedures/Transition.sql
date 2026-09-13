-- PROCEDURE-ENGINE §2 (W4, decision #106). Fires a named transition on a workflow instance: from the current state,
-- roles (the transition's, else the from-state's; not applied when a procedure step fires it — the step's role
-- applied), guards (a `procedure` guard is answered here from the procedure instances started by this workflow
-- instance; a `when` guard's verdict comes from the interpreter in @GuardEvaluation, index-aligned with requires[]),
-- requiresReason, and signoff segregation against the instance's prior attested transitions. Appends the transition
-- with why it was allowed, moves the state, completes or cancels the instance on a terminal state, and runs the target
-- state's onEnter effects (startProcedure). THROWs: 50170 no such transition from this state; 50171 role not held;
-- 50172 the procedure guard is not satisfied; 50173 a when-guard is false or Unknown (facts named); 50155 reason needed.
CREATE PROCEDURE [process].[Transition]
    @WorkflowInstanceEntityId UNIQUEIDENTIFIER,
    @TransitionName NVARCHAR(100),
    @Reason NVARCHAR(400) = NULL,
    @GuardEvaluation NVARCHAR(MAX) = NULL,
    @FiredByStepInstanceEntityId UNIQUEIDENTIFIER = NULL,
    @OverrideReason NVARCHAR(400) = NULL,
    @OverrideApprovedByActorId UNIQUEIDENTIFIER = NULL,
    @At DATETIMEOFFSET(7) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,   -- W7 (#141): the importer's transition — no person's role to check; the run stamped on the transition row
    @ToState NVARCHAR(40) = NULL OUTPUT,
    @TransitionId BIGINT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = ISNULL(@At, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @row UNIQUEIDENTIFIER, @version UNIQUEIDENTIFIER, @doc NVARCHAR(MAX), @from NVARCHAR(40), @subjectKind NVARCHAR(40), @subject UNIQUEIDENTIFIER,
            @startedAt DATETIMEOFFSET(7), @startedBy UNIQUEIDENTIFIER, @completedAt DATETIMEOFFSET(7), @key NVARCHAR(100);
    SELECT @row = w.[RowId], @version = w.[WorkflowDefinitionVersionRowId], @doc = dv.[PayloadText], @from = w.[CurrentState], @subjectKind = w.[SubjectKind], @subject = w.[SubjectEntityId],
           @startedAt = w.[StartedAt], @startedBy = w.[StartedByActorId], @completedAt = w.[CompletedAt], @key = d.[DefinitionKey]
    FROM [process].[WorkflowInstance] w JOIN [config].[DefinitionVersion] dv ON dv.[RowId] = w.[WorkflowDefinitionVersionRowId] JOIN [config].[Definition] d ON d.[EntityId] = dv.[DefinitionEntityId]
    WHERE w.[EntityId] = @WorkflowInstanceEntityId AND w.[IsDeleted] = 0;
    IF @row IS NULL THROW 50143, N'process.Transition: no live workflow instance with that id.', 1;
    IF @completedAt IS NOT NULL THROW 50174, N'process.Transition: the workflow instance has completed.', 1;

    DECLARE @t NVARCHAR(MAX);
    SELECT TOP (1) @t = t.[value] FROM OPENJSON(@doc, '$.transitions') t
    WHERE JSON_VALUE(t.[value], '$.from') = @from AND JSON_VALUE(t.[value], '$.name') = @TransitionName;
    IF @t IS NULL
    BEGIN
        -- decision #117: a transition whose target state the instance already holds is a no-op (a foreach member's step
        -- advancing a package-level lifecycle fires it once per member); anything else is an unknown transition
        IF @FiredByStepInstanceEntityId IS NOT NULL AND EXISTS (SELECT 1 FROM OPENJSON(@doc, '$.transitions') t2 WHERE JSON_VALUE(t2.[value], '$.name') = @TransitionName AND JSON_VALUE(t2.[value], '$.to') = @from)
        BEGIN SET @ToState = @from; RETURN; END
        DECLARE @m0 NVARCHAR(400) = N'process.Transition: no transition ' + @TransitionName + N' from state ' + @from + N'.'; THROW 50170, @m0, 1;
    END
    SET @ToState = JSON_VALUE(@t, '$.to');
    DECLARE @toJson NVARCHAR(MAX) = (SELECT TOP (1) s.[value] FROM OPENJSON(@doc, '$.states') s WHERE JSON_VALUE(s.[value], '$.code') = @ToState);
    DECLARE @fromJson NVARCHAR(MAX) = (SELECT TOP (1) s.[value] FROM OPENJSON(@doc, '$.states') s WHERE JSON_VALUE(s.[value], '$.code') = @from);

    -- reason
    IF JSON_VALUE(@t, '$.requiresReason') = 'true' AND NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL THROW 50155, N'process.Transition: this transition requires a reason.', 1;

    -- roles (a person's transition): the transition's roles, else the from-state's; none listed → anyone signed in
    IF @FiredByStepInstanceEntityId IS NULL AND @MigrationRunId IS NULL
    BEGIN
        DECLARE @roles NVARCHAR(MAX) = ISNULL(JSON_QUERY(@t, '$.roles'), JSON_QUERY(@fromJson, '$.roles'));
        IF @roles IS NOT NULL AND (SELECT COUNT(*) FROM OPENJSON(@roles)) > 0
        BEGIN
            DECLARE @person UNIQUEIDENTIFIER = (SELECT [PersonEntityId] FROM [personnel].[Actor] WHERE [ActorId] = @ActorId);
            IF NOT EXISTS (SELECT 1 FROM [security].[fGrantAsOf](@now, SYSUTCDATETIME()) g JOIN [security].[vUser] u ON u.[EntityId] = g.[GranteeEntityId]
                           WHERE g.[GranteeKind] = N'User' AND u.[PersonEntityId] = @person AND g.[RevokedByActorId] IS NULL AND g.[IsDeleted] = 0
                             AND (g.[RoleCode] = N'Administrator' OR g.[RoleCode] IN (SELECT [value] FROM OPENJSON(@roles))))
            BEGIN DECLARE @m1 NVARCHAR(400) = N'process.Transition: ' + @TransitionName + N' needs one of the roles ' + (SELECT STRING_AGG([value], N', ') FROM OPENJSON(@roles)) + N'.'; THROW 50171, @m1, 1; END
        END
    END

    -- guards, in order; the evaluation record travels with the transition
    DECLARE @guards NVARCHAR(MAX) = N'[';
    DECLARE @gi INT = 0, @g NVARCHAR(MAX);
    DECLARE gc CURSOR LOCAL FAST_FORWARD FOR SELECT r.[value] FROM OPENJSON(@t, '$.requires') r ORDER BY CAST(r.[key] AS INT);
    OPEN gc; FETCH NEXT FROM gc INTO @g;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF JSON_VALUE(@g, '$.procedure') IS NOT NULL
        BEGIN
            DECLARE @pk NVARCHAR(100) = JSON_VALUE(@g, '$.procedure'), @po NVARCHAR(40) = ISNULL(JSON_VALUE(@g, '$.outcome'), N'Completed');
            IF NOT EXISTS (SELECT 1 FROM [process].[ProcedureInstance] pi JOIN [config].[DefinitionVersion] dv ON dv.[RowId] = pi.[DefinitionVersionRowId] JOIN [config].[Definition] d ON d.[EntityId] = dv.[DefinitionEntityId]
                           WHERE pi.[WorkflowInstanceEntityId] = @WorkflowInstanceEntityId AND pi.[IsDeleted] = 0 AND d.[DefinitionKey] = @pk AND pi.[State] = N'Completed' AND pi.[Outcome] = @po)
            BEGIN DECLARE @m2 NVARCHAR(400) = N'process.Transition: ' + @TransitionName + N' requires procedure ' + @pk + N' to have completed with outcome ' + @po + N'.'; THROW 50172, @m2, 1; END
            SET @guards += CASE WHEN @gi > 0 THEN N',' ELSE N'' END + CONCAT(N'{"procedure":"', STRING_ESCAPE(@pk, 'json'), N'","outcome":"', STRING_ESCAPE(@po, 'json'), N'","ok":true}');
        END
        ELSE
        BEGIN
            DECLARE @verdict NVARCHAR(MAX) = JSON_QUERY(@GuardEvaluation, CONCAT(N'$[', @gi, N']'));
            IF @verdict IS NULL OR JSON_VALUE(@verdict, '$.ok') <> 'true'
            BEGIN
                DECLARE @why NVARCHAR(400) = ISNULL((SELECT STRING_AGG(u.[value], N', ') FROM OPENJSON(@verdict, '$.unknown') u), N'');
                DECLARE @m3 NVARCHAR(400) = N'process.Transition: ' + @TransitionName + N' is blocked by its condition' + CASE WHEN @why = N'' THEN N' (false).' ELSE N'; unknown facts: ' + @why END;
                THROW 50173, @m3, 1;
            END
            SET @guards += CASE WHEN @gi > 0 THEN N',' ELSE N'' END + @verdict;
        END
        SET @gi += 1;
        FETCH NEXT FROM gc INTO @g;
    END
    CLOSE gc; DEALLOCATE gc;
    SET @guards += N']';

    -- signoff segregation on the workflow instance: this transition's action against every prior attested transition's actor
    DECLARE @signoff NVARCHAR(100) = JSON_VALUE(@t, '$.signoff');
    IF @signoff IS NOT NULL
    BEGIN
        DECLARE @pa NVARCHAR(100), @pactor UNIQUEIDENTIFIER;
        DECLARE sc CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT JSON_VALUE(pt.[value], '$.signoff'), tr.[ActorId]
            FROM [process].[WorkflowTransition] tr
            JOIN OPENJSON(@doc, '$.transitions') pt ON JSON_VALUE(pt.[value], '$.from') = tr.[FromState] AND JSON_VALUE(pt.[value], '$.name') = tr.[TransitionName]
            WHERE tr.[WorkflowInstanceEntityId] = @WorkflowInstanceEntityId AND JSON_VALUE(pt.[value], '$.signoff') IS NOT NULL;
        OPEN sc; FETCH NEXT FROM sc INTO @pa, @pactor;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC [security].[CheckSegregation] @ActionA = @pa, @ActionB = @signoff, @SubjectKind = N'WorkflowInstance', @SubjectEntityId = @WorkflowInstanceEntityId,
                 @ActorA = @pactor, @ActorB = @ActorId, @OverrideReason = @OverrideReason, @OverrideApprovedByActorId = @OverrideApprovedByActorId, @OccurredAt = @now;
            FETCH NEXT FROM sc INTO @pa, @pactor;
        END
        CLOSE sc; DEALLOCATE sc;
    END

    BEGIN TRANSACTION;
    DECLARE @logId BIGINT;
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"transition","workflow":"', STRING_ESCAPE(@key, 'json'), N'","name":"', STRING_ESCAPE(@TransitionName, 'json'), N'","from":"', @from, N'","to":"', @ToState, N'"}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'process', @SubjectTable = N'WorkflowInstance', @SubjectEntityId = @WorkflowInstanceEntityId,
         @DefinitionVersionRowId = @version, @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now, @ActionLogId = @logId OUTPUT;
    EXEC [process].[WorkflowTransition_Append] @WorkflowInstanceEntityId = @WorkflowInstanceEntityId, @OccurredAt = @now, @FromState = @from, @ToState = @ToState,
         @TransitionName = @TransitionName, @ActorId = @ActorId, @Reason = @Reason, @FiredByStepInstanceEntityId = @FiredByStepInstanceEntityId,
         @GuardEvaluation = @guards, @ActionLogId = @logId, @MigrationRunId = @MigrationRunId, @TransitionId = @TransitionId OUTPUT;
    DECLARE @terminal BIT = CASE WHEN JSON_VALUE(@toJson, '$.terminal') = 'true' THEN 1 ELSE 0 END, @cancel BIT = CASE WHEN JSON_VALUE(@toJson, '$.cancellation') = 'true' THEN 1 ELSE 0 END;
    DECLARE @doneAt DATETIMEOFFSET(7) = CASE WHEN @terminal = 1 THEN @now ELSE NULL END;
    EXEC [process].[WorkflowInstance_Update] @RowId = @row, @WorkflowDefinitionVersionRowId = @version, @SubjectKind = @subjectKind, @SubjectEntityId = @subject,
         @CurrentState = @ToState, @StartedAt = @startedAt, @StartedByActorId = @startedBy, @CompletedAt = @doneAt, @IsCancelled = @cancel, @ActorId = @ActorId;
    -- onEnter effects of the target state
    DECLARE @proc NVARCHAR(100), @pi UNIQUEIDENTIFIER;
    DECLARE ef CURSOR LOCAL FAST_FORWARD FOR SELECT JSON_VALUE(e.[value], '$.startProcedure') FROM OPENJSON(@toJson, '$.onEnter') e WHERE JSON_VALUE(e.[value], '$.startProcedure') IS NOT NULL;
    OPEN ef; FETCH NEXT FROM ef INTO @proc;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC [process].[StartProcedure] @ProcedureKey = @proc, @SubjectKind = @subjectKind, @SubjectEntityId = @subject,
             @WorkflowInstanceEntityId = @WorkflowInstanceEntityId, @InvokedAtState = @ToState, @ActorId = @ActorId, @EntityId = @pi OUTPUT, @MigrationRunId = @MigrationRunId;
        FETCH NEXT FROM ef INTO @proc;
    END
    CLOSE ef; DEALLOCATE ef;
    COMMIT TRANSACTION;
END;
GO
