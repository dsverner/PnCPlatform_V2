-- SCHEMA-DESIGN §15.2 (183). Class AppendOnly. Written by the SQL Agent job under the agent_backup
-- role through audit.RecordBackupRun; evidence for the recovery-plan family via the fact catalogue.
CREATE TABLE [audit].[BackupRun] (
    [BackupRunId]               BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_BackupRun] PRIMARY KEY CLUSTERED,
    [PolicyDefinitionVersionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_BackupRun_Policy] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [BackupKind]                NVARCHAR(20)      NOT NULL CONSTRAINT [CK_BackupRun_Kind] CHECK ([BackupKind] IN (N'Full', N'Differential', N'Log', N'FilegroupFull')),
    [DatabaseName]              SYSNAME           NOT NULL,
    [StartedAt]                 DATETIMEOFFSET(7) NOT NULL,
    [CompletedAt]               DATETIMEOFFSET(7) NULL,
    [DestinationReference]      NVARCHAR(400)     NULL,
    [SizeBytes]                 BIGINT            NULL,
    [ChecksumVerified]          BIT               NOT NULL CONSTRAINT [DF_BackupRun_ChecksumVerified] DEFAULT 0,
    [VerifyOnlyPassed]          BIT               NULL,
    [Outcome]                   NVARCHAR(20)      NOT NULL CONSTRAINT [CK_BackupRun_Outcome] CHECK ([Outcome] IN (N'Succeeded', N'Failed', N'Skipped')),
    [ServerMessage]             NVARCHAR(MAX)     NULL,
    [AchievedRpoMinutes]        INT               NULL
);
GO
CREATE INDEX [IX_BackupRun_Kind] ON [audit].[BackupRun] ([BackupKind], [Outcome], [CompletedAt]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'audit', @level1type = N'TABLE', @level1name = N'BackupRun';
GO
