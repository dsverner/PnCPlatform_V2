-- SCHEMA-DESIGN §15.2 (183). Class AppendOnly. A restore rehearsal of a backup run.
-- Outcome has no value list stated for this table: no CHECK (recorded).
CREATE TABLE [audit].[RestoreTest] (
    [RestoreTestId]         BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_RestoreTest] PRIMARY KEY CLUSTERED,
    [BackupRunId]           BIGINT            NOT NULL CONSTRAINT [FK_RestoreTest_BackupRun] REFERENCES [audit].[BackupRun] ([BackupRunId]),
    [RestoredToServer]      NVARCHAR(200)     NOT NULL,
    [StartedAt]             DATETIMEOFFSET(7) NOT NULL,
    [CompletedAt]           DATETIMEOFFSET(7) NULL,
    [IntegrityCheckPassed]  BIT               NULL,
    [RowCountsMatched]      BIT               NULL,
    [AchievedRtoMinutes]    INT               NULL,
    [ActorId]               UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_RestoreTest_Actor] REFERENCES [personnel].[Actor] ([ActorId]),
    [Outcome]               NVARCHAR(20)      NOT NULL,
    [Notes]                 NVARCHAR(MAX)     NULL
);
GO
CREATE INDEX [IX_RestoreTest_Run] ON [audit].[RestoreTest] ([BackupRunId], [CompletedAt]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'audit', @level1type = N'TABLE', @level1name = N'RestoreTest';
GO
