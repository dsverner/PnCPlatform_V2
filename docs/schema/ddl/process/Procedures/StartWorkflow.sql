-- PROCEDURE-ENGINE §2 (W4, decision #106). Starts a Program.Workflow instance over a subject at the workflow's initial
-- state and runs that state's onEnter effects: startProcedure starts the named procedure over the same subject,
-- pinned (StartProcedure). Transitions are process.Transition. 50146 no Effective workflow; 50147 no initial state.
CREATE PROCEDURE [process].[StartWorkflow]
    @WorkflowKey NVARCHAR(100),
    @SubjectKind NVARCHAR(40),
    @SubjectEntityId UNIQUEIDENTIFIER,
    @WorkRequestEntityId UNIQUEIDENTIFIER = NULL,
    @Inputs NVARCHAR(MAX) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,   -- W7 (#138): a migrated instance carries its run
    @EntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @ProcedureInstanceEntityId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    IF [meta].[fEntityExists](@SubjectKind, @SubjectEntityId) = 0 THROW 50142, N'process.StartWorkflow: no subject of that kind with that id.', 1;
    IF @WorkRequestEntityId IS NULL AND @SubjectKind = N'WorkRequest' SET @WorkRequestEntityId = @SubjectEntityId;

    DECLARE @version UNIQUEIDENTIFIER, @doc NVARCHAR(MAX);
    SELECT TOP (1) @version = dv.[RowId], @doc = dv.[PayloadText]
    FROM [config].[Definition] d JOIN [config].[DefinitionVersion] dv ON dv.[DefinitionEntityId] = d.[EntityId] AND dv.[IsDeleted] = 0
    WHERE d.[IsDeleted] = 0 AND d.[DefinitionKind] = N'Program.Workflow' AND d.[DefinitionKey] = @WorkflowKey
      AND dv.[Status] = N'Effective' AND dv.[EffectiveFrom] <= @now AND (dv.[EffectiveTo] IS NULL OR dv.[EffectiveTo] > @now)
    ORDER BY dv.[VersionNumber] DESC;
    IF @version IS NULL BEGIN DECLARE @m0 NVARCHAR(400) = N'process.StartWorkflow: ' + @WorkflowKey + N' has no Effective version.'; THROW 50146, @m0, 1; END
    IF JSON_VALUE(@doc, '$.subjectKind') IS NOT NULL AND JSON_VALUE(@doc, '$.subjectKind') <> @SubjectKind
    BEGIN DECLARE @m2 NVARCHAR(400) = N'process.StartWorkflow: ' + @WorkflowKey + N' governs a ' + JSON_VALUE(@doc, '$.subjectKind') + N', not a ' + @SubjectKind + N'.'; THROW 50142, @m2, 1; END

    DECLARE @initial NVARCHAR(40), @initialJson NVARCHAR(MAX);
    SELECT TOP (1) @initial = JSON_VALUE(s.[value], '$.code'), @initialJson = s.[value] FROM OPENJSON(@doc, '$.states') s WHERE JSON_VALUE(s.[value], '$.initial') = 'true';
    IF @initial IS NULL THROW 50147, N'process.StartWorkflow: the workflow declares no initial state.', 1;

    BEGIN TRANSACTION;
    EXEC [process].[WorkflowInstance_Add] @WorkflowDefinitionVersionRowId = @version, @SubjectKind = @SubjectKind, @SubjectEntityId = @SubjectEntityId,
         @CurrentState = @initial, @StartedAt = @now, @StartedByActorId = @ActorId, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @EntityId OUTPUT;
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"workflow-started","key":"', STRING_ESCAPE(@WorkflowKey, 'json'), N'","state":"', STRING_ESCAPE(@initial, 'json'), N'"}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'process', @SubjectTable = N'WorkflowInstance',
         @SubjectEntityId = @EntityId, @DefinitionVersionRowId = @version, @ActorId = @ActorId, @Detail = @detail;
    -- onEnter effects of the initial state
    DECLARE @proc NVARCHAR(100);
    DECLARE ef CURSOR LOCAL FAST_FORWARD FOR SELECT JSON_VALUE(e.[value], '$.startProcedure') FROM OPENJSON(@initialJson, '$.onEnter') e WHERE JSON_VALUE(e.[value], '$.startProcedure') IS NOT NULL;
    OPEN ef; FETCH NEXT FROM ef INTO @proc;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC [process].[StartProcedure] @ProcedureKey = @proc, @SubjectKind = @SubjectKind, @SubjectEntityId = @SubjectEntityId,
             @WorkflowInstanceEntityId = @EntityId, @InvokedAtState = @initial, @WorkRequestEntityId = @WorkRequestEntityId, @Inputs = @Inputs,
             @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @ProcedureInstanceEntityId OUTPUT;
        FETCH NEXT FROM ef INTO @proc;
    END
    CLOSE ef; DEALLOCATE ef;
    COMMIT TRANSACTION;
END;
GO
