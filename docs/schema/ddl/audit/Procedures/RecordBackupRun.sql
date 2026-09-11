-- SCHEMA-DESIGN §15.2–15.3 (183, 184). The SQL Agent job records a backup run here, naming the
-- policy version it ran under. Granted to agent_backup; the application never issues BACKUP.
-- AchievedRpoMinutes is computed from the last successful Log backup (or this run when none).
CREATE PROCEDURE [audit].[RecordBackupRun]
    @PolicyDefinitionVersionRowId UNIQUEIDENTIFIER,
    @BackupKind NVARCHAR(20),
    @DatabaseName SYSNAME,
    @StartedAt DATETIMEOFFSET(7),
    @CompletedAt DATETIMEOFFSET(7) = NULL,
    @DestinationReference NVARCHAR(400) = NULL,
    @SizeBytes BIGINT = NULL,
    @ChecksumVerified BIT = 0,
    @VerifyOnlyPassed BIT = NULL,
    @Outcome NVARCHAR(20),
    @ServerMessage NVARCHAR(MAX) = NULL,
    @BackupRunId BIGINT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @lastLog DATETIMEOFFSET(7) = (SELECT MAX([CompletedAt]) FROM [audit].[BackupRun]
                                          WHERE [DatabaseName] = @DatabaseName AND [BackupKind] = N'Log' AND [Outcome] = N'Succeeded');
    DECLARE @rpo INT = CASE WHEN @Outcome <> N'Succeeded' THEN NULL
                            WHEN @lastLog IS NULL THEN NULL
                            ELSE DATEDIFF(MINUTE, @lastLog, ISNULL(@CompletedAt, @StartedAt)) END;
    EXEC [audit].[BackupRun_Append]
        @PolicyDefinitionVersionRowId = @PolicyDefinitionVersionRowId, @BackupKind = @BackupKind, @DatabaseName = @DatabaseName,
        @StartedAt = @StartedAt, @CompletedAt = @CompletedAt, @DestinationReference = @DestinationReference, @SizeBytes = @SizeBytes,
        @ChecksumVerified = @ChecksumVerified, @VerifyOnlyPassed = @VerifyOnlyPassed, @Outcome = @Outcome,
        @ServerMessage = @ServerMessage, @AchievedRpoMinutes = @rpo, @BackupRunId = @BackupRunId OUTPUT;
END;
GO
GRANT EXECUTE ON [audit].[RecordBackupRun] TO [agent_backup];
GO
