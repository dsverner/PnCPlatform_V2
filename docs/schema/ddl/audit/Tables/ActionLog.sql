-- SCHEMA-DESIGN §1.1. Class AppendOnly. No update or delete procedure exists; INSERT through
-- audit.LogAction only. Read logging (decision 65) writes here with ActionKind = 'Read'.
CREATE TABLE [audit].[ActionLog] (
    [ActionLogId]             BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_ActionLog] PRIMARY KEY CLUSTERED,
    [OccurredAt]              DATETIMEOFFSET(7) NOT NULL,
    [ActorId]                 UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ActionLog_Actor] REFERENCES [personnel].[Actor] ([ActorId]),
    [ActionKindCode]          NVARCHAR(50)      NOT NULL CONSTRAINT [FK_ActionLog_ActionKind] REFERENCES [ref].[ActionKind] ([ActionKindCode]),
    [SubjectSchema]           SYSNAME           NULL,
    [SubjectTable]            SYSNAME           NULL,
    [SubjectEntityId]         UNIQUEIDENTIFIER  NULL,
    [SubjectRowId]            UNIQUEIDENTIFIER  NULL,   -- when the act was against a specific fact version
    [DefinitionVersionRowId]  UNIQUEIDENTIFIER  NULL CONSTRAINT [FK_ActionLog_DefinitionVersion] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [Detail]                  NVARCHAR(MAX)     NULL CONSTRAINT [CK_ActionLog_DetailJson] CHECK ([Detail] IS NULL OR ISJSON([Detail]) = 1)
);
GO
CREATE INDEX [IX_ActionLog_Subject] ON [audit].[ActionLog] ([SubjectEntityId], [OccurredAt]);
GO
CREATE INDEX [IX_ActionLog_Actor] ON [audit].[ActionLog] ([ActorId], [OccurredAt]);
GO
CREATE INDEX [IX_ActionLog_OccurredAt] ON [audit].[ActionLog] ([OccurredAt]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'audit', @level1type = N'TABLE', @level1name = N'ActionLog';
GO
