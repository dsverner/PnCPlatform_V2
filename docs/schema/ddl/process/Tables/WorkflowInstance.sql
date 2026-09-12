-- PROCEDURE-ENGINE §4 (instances). Class Versioned. One lifecycle of one thing under a Program.Workflow version.
-- Re-designed in W3 with the shape the predecessor's work.WorkflowInstance had (decision #100); the predecessor's
-- rows were never imported. SubjectKind/SubjectEntityId is a polymorphic reference (ref.SubjectKind), not an FK.
CREATE TABLE [process].[WorkflowInstance] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_WorkflowInstance_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_WorkflowInstance_Registry] REFERENCES [process].[WorkflowInstanceRegistry] ([EntityId]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_WorkflowInstance_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_WorkflowInstance_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_WorkflowInstance_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_WorkflowInstance_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_WorkflowInstance_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [WorkflowDefinitionVersionRowId] UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_WorkflowInstance_WorkflowVersion] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [SubjectKind]       NVARCHAR(40)      NOT NULL CONSTRAINT [FK_WorkflowInstance_SubjectKind] REFERENCES [ref].[SubjectKind] ([SubjectKindCode]),
    [SubjectEntityId]   UNIQUEIDENTIFIER  NOT NULL,
    [CurrentState]      NVARCHAR(40)      NOT NULL,
    [StartedAt]         DATETIMEOFFSET(7) NOT NULL,
    [StartedByActorId] UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_WorkflowInstance_StartedByActor] REFERENCES [personnel].[Actor] ([ActorId]),
    [CompletedAt]       DATETIMEOFFSET(7) NULL,
    [IsCancelled]       BIT               NOT NULL CONSTRAINT [DF_WorkflowInstance_IsCancelled] DEFAULT 0,
    CONSTRAINT [PK_WorkflowInstance] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_WorkflowInstance_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [process].[WorkflowInstance_History]));
GO
CREATE INDEX [IX_WorkflowInstance_Entity] ON [process].[WorkflowInstance] ([EntityId]);
GO
CREATE INDEX [IX_WorkflowInstance_Subject] ON [process].[WorkflowInstance] ([SubjectKind], [SubjectEntityId]) WHERE [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'process', @level1type = N'TABLE', @level1name = N'WorkflowInstance';
GO
