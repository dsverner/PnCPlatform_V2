-- Decision #227 (2026-09-22). A change request brought over from the old program, withdrawn. The old program's
-- "Cancel/Delete Work Request" (prog_frmRelaySettingChangeStatus.cpp:57-132) deleted the outstanding record, its tracks and
-- its document outright; here nothing is deleted: the outstanding draft is marked Withdrawn (it leaves the Outstanding list
-- and stays on the device's History), the landed procedure is cancelled with the reason, and the request is cancelled
-- through the workflow's own Cancel, whose role rule and reason rule still apply. The in-service settings are untouched,
-- as they were in the old program.
--   50310 not a request from the old program   50311 already finished or withdrawn   50332 a reason is needed
CREATE PROCEDURE [work].[WithdrawLegacyRequest]
    @WorkRequestEntityId UNIQUEIDENTIFIER,
    @Reason NVARCHAR(400),
    @ActorId UNIQUEIDENTIFIER = NULL,
    @Outcome NVARCHAR(40) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    SET @Reason = NULLIF(LTRIM(RTRIM(@Reason)), N'');
    IF @Reason IS NULL THROW 50332, N'work.WithdrawLegacyRequest: say why the request is withdrawn.', 1;

    IF NOT EXISTS (SELECT 1 FROM [work].[WorkRequest] WHERE [EntityId] = @WorkRequestEntityId AND [ValidTo] IS NULL AND [IsDeleted] = 0 AND [MigrationRunId] IS NOT NULL)
        THROW 50310, N'work.WithdrawLegacyRequest: only a change request brought over from the old program is withdrawn this way.', 1;
    DECLARE @wf UNIQUEIDENTIFIER, @wfDone DATETIMEOFFSET(7);
    SELECT TOP (1) @wf = [EntityId], @wfDone = [CompletedAt] FROM [process].[WorkflowInstance]
     WHERE [SubjectKind] = N'WorkRequest' AND [SubjectEntityId] = @WorkRequestEntityId AND [IsDeleted] = 0 ORDER BY [RowSeq] DESC;
    IF @wf IS NULL OR @wfDone IS NOT NULL THROW 50311, N'work.WithdrawLegacyRequest: the request is already finished or withdrawn.', 1;

    DECLARE @draft UNIQUEIDENTIFIER;
    SELECT TOP (1) @draft = r.[RowId]
      FROM [record].[Record] x
      JOIN [document].[Revision] r ON r.[RowId] = x.[SecondSubjectEntityId] AND r.[IsDeleted] = 0 AND r.[Status] = N'Draft'
      JOIN [document].[ConfigurationFile] cf ON cf.[RevisionRowId] = r.[RowId] AND cf.[IsDeleted] = 0 AND cf.[InServiceFrom] IS NULL
     WHERE x.[WorkRequestEntityId] = @WorkRequestEntityId AND x.[ValidTo] IS NULL AND x.[IsDeleted] = 0 AND x.[SecondSubjectKind] = N'ConfigurationFileRevision'
     ORDER BY x.[OccurredAt] DESC;
    DECLARE @pi UNIQUEIDENTIFIER = (SELECT TOP (1) [EntityId] FROM [process].[ProcedureInstance]
                                     WHERE [WorkflowInstanceEntityId] = @wf AND [ParentInstanceEntityId] IS NULL AND [IsDeleted] = 0 ORDER BY [RowSeq] DESC);
    DECLARE @why NVARCHAR(400) = LEFT(N'withdrawn: ' + @Reason, 400);

    BEGIN TRANSACTION;
    IF @draft IS NOT NULL
        UPDATE [document].[Revision] SET [Status] = N'Withdrawn', [ModifiedBy] = @ActorId, [ModifiedAt] = @now
         WHERE [RowId] = @draft AND [IsDeleted] = 0 AND [Status] = N'Draft';
    IF @pi IS NOT NULL
    BEGIN
        DECLARE @child UNIQUEIDENTIFIER;
        DECLARE kids CURSOR LOCAL FAST_FORWARD FOR
            SELECT [EntityId] FROM [process].[ProcedureInstance] WHERE [ParentInstanceEntityId] = @pi AND [IsDeleted] = 0 AND [State] NOT IN (N'Completed', N'Cancelled');
        OPEN kids; FETCH NEXT FROM kids INTO @child;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC [process].[CompleteInstance] @ProcedureInstanceEntityId = @child, @State = N'Cancelled', @Reason = @why, @At = @now, @ActorId = @ActorId;
            FETCH NEXT FROM kids INTO @child;
        END
        CLOSE kids; DEALLOCATE kids;
        IF EXISTS (SELECT 1 FROM [process].[ProcedureInstance] WHERE [EntityId] = @pi AND [IsDeleted] = 0 AND [State] NOT IN (N'Completed', N'Cancelled'))
            EXEC [process].[CompleteInstance] @ProcedureInstanceEntityId = @pi, @State = N'Cancelled', @Reason = @why, @At = @now, @ActorId = @ActorId;
    END
    DECLARE @to NVARCHAR(40), @tid BIGINT;
    EXEC [process].[Transition] @WorkflowInstanceEntityId = @wf, @TransitionName = N'Cancel', @Reason = @Reason,
         @At = @now, @ActorId = @ActorId, @ToState = @to OUTPUT, @TransitionId = @tid OUTPUT;
    SET @Outcome = N'Withdrawn';
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"legacy-request-withdrawn","reason":"', STRING_ESCAPE(@Reason, 'json'),
        N'","outstanding":', CASE WHEN @draft IS NULL THEN N'null' ELSE N'"' + CONVERT(NVARCHAR(36), @draft) + N'"' END, N'}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'work', @SubjectTable = N'WorkRequest',
         @SubjectEntityId = @WorkRequestEntityId, @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now;
    COMMIT TRANSACTION;
END;
GO
GRANT EXECUTE ON [work].[WithdrawLegacyRequest] TO [app_execute];
GO
