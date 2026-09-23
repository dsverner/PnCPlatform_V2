-- Decision #227 (2026-09-22). A change request brought over from the old program, finished as the old program finished it
-- ("Complete Request", prog_frmRelaySettingChangeStatus.cpp:194-384):
--   refused while a track is still in progress (the old program: any track "Change In Progress", :227-235; here a track
--   not yet set is refused too, so nothing is finished by omission);
--   a Delete Order (work type SETTINGS_DELETE): the device's in-service settings are taken out of service with nothing
--   in their place (document.SetOutOfService) and the outstanding draft is withdrawn (:236-295 — the old program deleted it);
--   any other type: the outstanding settings go in service and the ones they replace are archived (document.SetInService,
--   which closes the prior period — :296-379).
-- The procedure the migration landed for the request (#56) was never followed; its open steps are closed as finished by
-- hand, the run completed, and the request closed through the workflow's own Close, whose role rule still applies.
--   50310 not a request from the old program   50311 already finished or withdrawn   50330 a track is not finished
--   50331 no outstanding settings on the request   50333 no landed procedure on the request
CREATE PROCEDURE [work].[CompleteLegacyRequest]
    @WorkRequestEntityId UNIQUEIDENTIFIER,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @Outcome NVARCHAR(40) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();

    DECLARE @typeVersion UNIQUEIDENTIFIER, @scopeAsset UNIQUEIDENTIFIER;
    SELECT TOP (1) @typeVersion = [WorkTypeDefinitionVersionRowId], @scopeAsset = CASE WHEN [ScopeKind] = N'Asset' THEN [ScopeEntityId] END
      FROM [work].[WorkRequest] WHERE [EntityId] = @WorkRequestEntityId AND [ValidTo] IS NULL AND [IsDeleted] = 0 AND [MigrationRunId] IS NOT NULL
     ORDER BY [RowSeq] DESC;
    IF @typeVersion IS NULL THROW 50310, N'work.CompleteLegacyRequest: only a change request brought over from the old program is finished this way.', 1;

    DECLARE @wf UNIQUEIDENTIFIER, @wfDone DATETIMEOFFSET(7);
    SELECT TOP (1) @wf = [EntityId], @wfDone = [CompletedAt] FROM [process].[WorkflowInstance]
     WHERE [SubjectKind] = N'WorkRequest' AND [SubjectEntityId] = @WorkRequestEntityId AND [IsDeleted] = 0 ORDER BY [RowSeq] DESC;
    IF @wf IS NULL THROW 50333, N'work.CompleteLegacyRequest: the request has no workflow to close.', 1;
    IF @wfDone IS NOT NULL THROW 50311, N'work.CompleteLegacyRequest: the request is already finished or withdrawn.', 1;

    IF (SELECT COUNT(*) FROM [work].[RequestTrack]
         WHERE [WorkRequestEntityId] = @WorkRequestEntityId AND [ValidTo] IS NULL AND [IsDeleted] = 0
           AND [TrackCode] IN (N'Documentation', N'Database') AND [Status] IN (N'Complete', N'NotNeeded')) < 2
        THROW 50330, N'work.CompleteLegacyRequest: the documentation and settings database tracks must both be Complete or Not needed first.', 1;

    DECLARE @typeKey NVARCHAR(100) = (SELECT d.[DefinitionKey] FROM [config].[DefinitionVersion] v JOIN [config].[Definition] d ON d.[EntityId] = v.[DefinitionEntityId]
                                       WHERE v.[RowId] = @typeVersion);

    -- the outstanding settings: the draft the request's record points at, never in service
    DECLARE @draft UNIQUEIDENTIFIER, @device UNIQUEIDENTIFIER;
    SELECT TOP (1) @draft = r.[RowId], @device = cf.[DeviceEntityId]
      FROM [record].[Record] x
      JOIN [document].[Revision] r ON r.[RowId] = x.[SecondSubjectEntityId] AND r.[IsDeleted] = 0 AND r.[Status] = N'Draft'
      JOIN [document].[ConfigurationFile] cf ON cf.[RevisionRowId] = r.[RowId] AND cf.[IsDeleted] = 0 AND cf.[InServiceFrom] IS NULL
     WHERE x.[WorkRequestEntityId] = @WorkRequestEntityId AND x.[ValidTo] IS NULL AND x.[IsDeleted] = 0 AND x.[SecondSubjectKind] = N'ConfigurationFileRevision'
     ORDER BY x.[OccurredAt] DESC;
    SET @device = ISNULL(@device, @scopeAsset);
    IF @draft IS NULL AND ISNULL(@typeKey, N'') <> N'SETTINGS_DELETE'
        THROW 50331, N'work.CompleteLegacyRequest: the request carries no outstanding settings to put in service.', 1;

    DECLARE @inService UNIQUEIDENTIFIER = (SELECT TOP (1) [RevisionRowId] FROM [document].[vConfigurationFile]
                                            WHERE [DeviceEntityId] = @device AND [FileKind] IN (N'NativeSettings', N'SettingsText')
                                              AND [InServiceFrom] IS NOT NULL AND [InServiceTo] IS NULL);
    DECLARE @pi UNIQUEIDENTIFIER = (SELECT TOP (1) [EntityId] FROM [process].[ProcedureInstance]
                                     WHERE [WorkflowInstanceEntityId] = @wf AND [ParentInstanceEntityId] IS NULL AND [IsDeleted] = 0 ORDER BY [RowSeq] DESC);

    BEGIN TRANSACTION;
    IF @typeKey = N'SETTINGS_DELETE'
    BEGIN
        IF @inService IS NOT NULL
            EXEC [document].[SetOutOfService] @RevisionRowId = @inService, @OutOfServiceAt = @now, @WorkRequestEntityId = @WorkRequestEntityId, @ActorId = @ActorId;
        IF @draft IS NOT NULL
            UPDATE [document].[Revision] SET [Status] = N'Withdrawn', [ModifiedBy] = @ActorId, [ModifiedAt] = @now
             WHERE [RowId] = @draft AND [IsDeleted] = 0 AND [Status] = N'Draft';
        SET @Outcome = N'Retired';
    END
    ELSE
    BEGIN
        EXEC [document].[SetInService] @RevisionRowId = @draft, @InServiceFrom = @now, @ActorId = @ActorId;
        SET @Outcome = N'InService';
    END

    -- the landed procedure: never followed, so its open parts are closed as finished by hand, then the run completes
    IF @pi IS NOT NULL
    BEGIN
        DECLARE @child UNIQUEIDENTIFIER;
        DECLARE kids CURSOR LOCAL FAST_FORWARD FOR
            SELECT [EntityId] FROM [process].[ProcedureInstance] WHERE [ParentInstanceEntityId] = @pi AND [IsDeleted] = 0 AND [State] NOT IN (N'Completed', N'Cancelled');
        OPEN kids; FETCH NEXT FROM kids INTO @child;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC [process].[CompleteInstance] @ProcedureInstanceEntityId = @child, @State = N'Cancelled', @Reason = N'finished by hand, as the old program finished it', @At = @now, @ActorId = @ActorId;
            FETCH NEXT FROM kids INTO @child;
        END
        CLOSE kids; DEALLOCATE kids;
        UPDATE s SET s.[State] = N'Skipped', s.[Outcome] = N'FinishedByHand', s.[ModifiedBy] = @ActorId, s.[ModifiedAt] = @now
          FROM [process].[StepInstance] s JOIN [process].[BlockInstance] b ON b.[EntityId] = s.[BlockInstanceEntityId]
         WHERE b.[ProcedureInstanceEntityId] = @pi AND s.[IsDeleted] = 0 AND s.[State] NOT IN (N'Committed', N'Skipped', N'Varied');
        UPDATE [process].[BlockInstance] SET [State] = N'Completed', [Outcome] = N'FinishedByHand', [CompletedAt] = @now, [ModifiedBy] = @ActorId, [ModifiedAt] = @now
         WHERE [ProcedureInstanceEntityId] = @pi AND [IsDeleted] = 0 AND [State] NOT IN (N'Completed', N'Skipped', N'Cancelled');
        IF EXISTS (SELECT 1 FROM [process].[ProcedureInstance] WHERE [EntityId] = @pi AND [IsDeleted] = 0 AND [State] NOT IN (N'Completed', N'Cancelled'))
            EXEC [process].[CompleteInstance] @ProcedureInstanceEntityId = @pi, @State = N'Completed', @Outcome = N'Completed', @At = @now, @ActorId = @ActorId;
    END

    DECLARE @to NVARCHAR(40), @tid BIGINT;
    EXEC [process].[Transition] @WorkflowInstanceEntityId = @wf, @TransitionName = N'Close', @Reason = N'finished by hand, as the old program finished it',
         @At = @now, @ActorId = @ActorId, @ToState = @to OUTPUT, @TransitionId = @tid OUTPUT;

    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"legacy-request-completed","type":', CASE WHEN @typeKey IS NULL THEN N'null' ELSE N'"' + STRING_ESCAPE(@typeKey, 'json') + N'"' END,
        N',"outcome":"', @Outcome, N'","device":', CASE WHEN @device IS NULL THEN N'null' ELSE N'"' + CONVERT(NVARCHAR(36), @device) + N'"' END,
        N',"outstanding":', CASE WHEN @draft IS NULL THEN N'null' ELSE N'"' + CONVERT(NVARCHAR(36), @draft) + N'"' END,
        N',"replaced":', CASE WHEN @inService IS NULL THEN N'null' ELSE N'"' + CONVERT(NVARCHAR(36), @inService) + N'"' END, N'}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'work', @SubjectTable = N'WorkRequest',
         @SubjectEntityId = @WorkRequestEntityId, @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now;
    COMMIT TRANSACTION;
END;
GO
GRANT EXECUTE ON [work].[CompleteLegacyRequest] TO [app_execute];
GO
