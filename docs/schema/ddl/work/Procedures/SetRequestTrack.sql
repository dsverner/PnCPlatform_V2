-- Decision #227 (2026-09-22). One track of a change request brought over from the old program, set by hand — the old
-- program's own way (prog_frmRelaySettingChangeStatus.dfm: a status of "Change In Progress", "Complete" or "NA", a date
-- and notes per track), kept as a direct save with audit (#163). A request raised in the platform keeps its tracks as the
-- steps of its procedure and is refused here.
--   50310 not a request from the old program   50311 the request is closed or withdrawn   50312 no such track   50313 no such status
CREATE PROCEDURE [work].[SetRequestTrack]
    @WorkRequestEntityId UNIQUEIDENTIFIER,
    @TrackCode NVARCHAR(20),
    @Status NVARCHAR(20),
    @TrackDate DATETIMEOFFSET(7) = NULL,
    @Note NVARCHAR(MAX) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @EntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @Outcome NVARCHAR(20) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    SET @TrackCode = LTRIM(RTRIM(@TrackCode));
    SET @Status = LTRIM(RTRIM(@Status));
    SET @Note = NULLIF(LTRIM(RTRIM(@Note)), N'');

    IF NOT EXISTS (SELECT 1 FROM [work].[WorkRequest] WHERE [EntityId] = @WorkRequestEntityId AND [ValidTo] IS NULL AND [IsDeleted] = 0 AND [MigrationRunId] IS NOT NULL)
        THROW 50310, N'work.SetRequestTrack: only a change request brought over from the old program keeps its tracks by hand.', 1;
    IF EXISTS (SELECT 1 FROM [process].[WorkflowInstance] WHERE [SubjectKind] = N'WorkRequest' AND [SubjectEntityId] = @WorkRequestEntityId
                                                          AND [IsDeleted] = 0 AND [CompletedAt] IS NOT NULL)
        THROW 50311, N'work.SetRequestTrack: the request is already finished or withdrawn.', 1;
    IF @TrackCode NOT IN (N'Documentation', N'Database') THROW 50312, N'work.SetRequestTrack: the track is Documentation or Database.', 1;
    IF @Status NOT IN (N'InProgress', N'Complete', N'NotNeeded') THROW 50313, N'work.SetRequestTrack: the status is InProgress, Complete or NotNeeded.', 1;

    -- The API binds an OUTPUT parameter from the request body: cleared so a caller cannot name another request's track (#226).
    SET @EntityId = NULL;
    DECLARE @was NVARCHAR(20), @wasDate DATETIMEOFFSET(7), @wasNote NVARCHAR(MAX);
    SELECT TOP (1) @EntityId = [EntityId], @was = [Status], @wasDate = [TrackDate], @wasNote = [Note]
      FROM [work].[RequestTrack]
     WHERE [WorkRequestEntityId] = @WorkRequestEntityId AND [TrackCode] = @TrackCode AND [ValidTo] IS NULL AND [IsDeleted] = 0
     ORDER BY [RowSeq] DESC;
    IF @was = @Status AND ISNULL(@wasDate, '0001-01-01') = ISNULL(@TrackDate, '0001-01-01') AND ISNULL(@wasNote, N'') = ISNULL(@Note, N'')
    BEGIN SET @Outcome = N'Unchanged'; RETURN; END

    BEGIN TRANSACTION;
    IF @EntityId IS NULL
    BEGIN
        EXEC [work].[RequestTrack_Add] @WorkRequestEntityId = @WorkRequestEntityId, @TrackCode = @TrackCode, @Status = @Status,
             @TrackDate = @TrackDate, @Note = @Note, @ValidFrom = @now, @ActorId = @ActorId, @EntityId = @EntityId OUTPUT;
        SET @Outcome = N'Set';
    END
    ELSE
    BEGIN
        EXEC [work].[RequestTrack_Revise] @EntityId = @EntityId, @WorkRequestEntityId = @WorkRequestEntityId, @TrackCode = @TrackCode, @Status = @Status,
             @TrackDate = @TrackDate, @Note = @Note, @ValidFrom = @now, @ActorId = @ActorId;
        SET @Outcome = N'Changed';
    END
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"request-track-set","track":"', STRING_ESCAPE(@TrackCode, 'json'),
        N'","from":', CASE WHEN @was IS NULL THEN N'null' ELSE N'"' + STRING_ESCAPE(@was, 'json') + N'"' END,
        N',"to":"', STRING_ESCAPE(@Status, 'json'), N'","date":',
        CASE WHEN @TrackDate IS NULL THEN N'null' ELSE N'"' + CONVERT(NVARCHAR(40), @TrackDate, 127) + N'"' END, N'}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'work', @SubjectTable = N'WorkRequest',
         @SubjectEntityId = @WorkRequestEntityId, @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now;
    COMMIT TRANSACTION;
END;
GO
GRANT EXECUTE ON [work].[SetRequestTrack] TO [app_execute];
GO
