-- PROCEDURE-ENGINE §4 (instances). Class AppendOnly. Every transition of a workflow instance, with why it was
-- allowed (GuardEvaluation, JSON) and, when a procedure step fired it (§2, step.advances), which step instance.
-- No update or delete procedure exists; the generated process.WorkflowTransition_Append is the only write path.
CREATE TABLE [process].[WorkflowTransition] (
    [TransitionId]      BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_WorkflowTransition] PRIMARY KEY CLUSTERED,
    [WorkflowInstanceEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_WorkflowTransition_Instance] REFERENCES [process].[WorkflowInstanceRegistry] ([EntityId]),
    [OccurredAt]        DATETIMEOFFSET(7) NOT NULL,
    [FromState]         NVARCHAR(40)      NOT NULL,
    [ToState]           NVARCHAR(40)      NOT NULL,
    [TransitionName]    NVARCHAR(100)     NOT NULL,
    [ActorId]           UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_WorkflowTransition_Actor] REFERENCES [personnel].[Actor] ([ActorId]),
    [Reason]            NVARCHAR(400)     NULL,
    [FiredByStepInstanceEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_WorkflowTransition_FiredByStep] REFERENCES [process].[StepInstanceRegistry] ([EntityId]),
    [GuardEvaluation]   NVARCHAR(MAX)     NULL CONSTRAINT [CK_WorkflowTransition_GuardJson] CHECK ([GuardEvaluation] IS NULL OR ISJSON([GuardEvaluation]) = 1),
    [ActionLogId]       BIGINT            NULL CONSTRAINT [FK_WorkflowTransition_ActionLog] REFERENCES [audit].[ActionLog] ([ActionLogId]),
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL CONSTRAINT [FK_WorkflowTransition_MigrationRun] REFERENCES [migration].[Run] ([RunId])
);
GO
CREATE INDEX [IX_WorkflowTransition_Instance] ON [process].[WorkflowTransition] ([WorkflowInstanceEntityId], [OccurredAt]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'process', @level1type = N'TABLE', @level1name = N'WorkflowTransition';
GO
