-- SCHEMA-DESIGN §15.2–15.3 (183, 184). The SQL Agent job (or an operator running a rehearsal)
-- records a restore test against a backup run. Granted to agent_backup. AchievedRtoMinutes is
-- taken from the start/completion instants when not supplied.
CREATE PROCEDURE [audit].[RecordRestoreTest]
    @BackupRunId BIGINT,
    @RestoredToServer NVARCHAR(200),
    @StartedAt DATETIMEOFFSET(7),
    @CompletedAt DATETIMEOFFSET(7) = NULL,
    @IntegrityCheckPassed BIT = NULL,
    @RowCountsMatched BIT = NULL,
    @AchievedRtoMinutes INT = NULL,
    @Outcome NVARCHAR(20),
    @Notes NVARCHAR(MAX) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @RestoreTestId BIGINT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [audit].[BackupRun] WHERE [BackupRunId] = @BackupRunId)
        THROW 50150, N'audit.RestoreTest: unknown @BackupRunId.', 1;
    IF @AchievedRtoMinutes IS NULL AND @CompletedAt IS NOT NULL
        SET @AchievedRtoMinutes = DATEDIFF(MINUTE, @StartedAt, @CompletedAt);
    EXEC [audit].[RestoreTest_Append]
        @BackupRunId = @BackupRunId, @RestoredToServer = @RestoredToServer, @StartedAt = @StartedAt, @CompletedAt = @CompletedAt,
        @IntegrityCheckPassed = @IntegrityCheckPassed, @RowCountsMatched = @RowCountsMatched, @AchievedRtoMinutes = @AchievedRtoMinutes,
        @ActorId = @ActorId, @Outcome = @Outcome, @Notes = @Notes, @RestoreTestId = @RestoreTestId OUTPUT;
END;
GO
GRANT EXECUTE ON [audit].[RecordRestoreTest] TO [agent_backup];
GO
