-- PROCEDURE-ENGINE §4 (instances). Class Versioned. One activation of one block: a foreach member or a repeat pass is
-- its own row (IterationKey, Pass). Outcome carries branch outcomes such as Superseded and NotApplicable (#51).
CREATE TABLE [process].[BlockInstance] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_BlockInstance_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_BlockInstance_Registry] REFERENCES [process].[BlockInstanceRegistry] ([EntityId]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_BlockInstance_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_BlockInstance_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_BlockInstance_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_BlockInstance_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_BlockInstance_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ProcedureInstanceEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_BlockInstance_Instance] REFERENCES [process].[ProcedureInstanceRegistry] ([EntityId]),
    [ParentBlockInstanceEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_BlockInstance_Parent] REFERENCES [process].[BlockInstanceRegistry] ([EntityId]),
    [BlockPath]         NVARCHAR(400)     NOT NULL,
    [BlockKind]         NVARCHAR(20)      NOT NULL CONSTRAINT [CK_BlockInstance_Kind] CHECK ([BlockKind] IN (N'step', N'sequence', N'parallel', N'branch', N'choice', N'foreach', N'repeat', N'call', N'hold')),
    [IterationKey]      NVARCHAR(100)     NULL,
    [Pass]              INT               NOT NULL CONSTRAINT [DF_BlockInstance_Pass] DEFAULT 1,
    [MemberSubjectKind] NVARCHAR(40)      NULL     CONSTRAINT [FK_BlockInstance_MemberKind] REFERENCES [ref].[SubjectKind] ([SubjectKindCode]),
    [MemberSubjectEntityId] UNIQUEIDENTIFIER NULL,
    [State]             NVARCHAR(40)      NOT NULL CONSTRAINT [CK_BlockInstance_State] CHECK ([State] IN (N'Pending', N'Running', N'Held', N'Completed', N'Skipped', N'Cancelled')),
    [Outcome]           NVARCHAR(40)      NULL,
    [StartedAt]         DATETIMEOFFSET(7) NULL,
    [CompletedAt]       DATETIMEOFFSET(7) NULL,
    CONSTRAINT [PK_BlockInstance] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_BlockInstance_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [process].[BlockInstance_History]));
GO
CREATE INDEX [IX_BlockInstance_Entity] ON [process].[BlockInstance] ([EntityId]);
GO
CREATE INDEX [IX_BlockInstance_Instance] ON [process].[BlockInstance] ([ProcedureInstanceEntityId], [BlockPath]) WHERE [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'process', @level1type = N'TABLE', @level1name = N'BlockInstance';
GO
