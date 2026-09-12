-- PROCEDURE-ENGINE §4 (instances). Class Versioned. One run of one Program.Procedure version over one subject. A
-- child run (a call block) carries its parent and the call's block path. Inputs and Produced are JSON (name → value,
-- name → EntityId). State and Outcome per §4; DueAt is never a column (#44).
CREATE TABLE [process].[ProcedureInstance] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_ProcedureInstance_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProcedureInstance_Registry] REFERENCES [process].[ProcedureInstanceRegistry] ([EntityId]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProcedureInstance_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProcedureInstance_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_ProcedureInstance_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ProcedureInstance_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ProcedureInstance_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [DefinitionVersionRowId] UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProcedureInstance_DefinitionVersion] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [ParentInstanceEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_ProcedureInstance_Parent] REFERENCES [process].[ProcedureInstanceRegistry] ([EntityId]),
    [CallBlockPath]     NVARCHAR(400)     NULL,
    [WorkflowInstanceEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_ProcedureInstance_WorkflowInstance] REFERENCES [process].[WorkflowInstanceRegistry] ([EntityId]),
    [InvokedAtState]    NVARCHAR(40)      NULL,
    [SubjectKind]       NVARCHAR(40)      NOT NULL CONSTRAINT [FK_ProcedureInstance_SubjectKind] REFERENCES [ref].[SubjectKind] ([SubjectKindCode]),
    [SubjectEntityId]   UNIQUEIDENTIFIER  NOT NULL,
    [WorkRequestEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_ProcedureInstance_WorkRequest] REFERENCES [work].[WorkRequestRegistry] ([EntityId]),
    [Inputs] NVARCHAR(MAX) NULL CONSTRAINT [CK_ProcedureInstance_InputsJson] CHECK ([Inputs] IS NULL OR ISJSON([Inputs]) = 1),
    [Produced] NVARCHAR(MAX) NULL CONSTRAINT [CK_ProcedureInstance_ProducedJson] CHECK ([Produced] IS NULL OR ISJSON([Produced]) = 1),
    [State]             NVARCHAR(40)      NOT NULL CONSTRAINT [CK_ProcedureInstance_State] CHECK ([State] IN (N'Running', N'Held', N'Completed', N'Cancelled')),
    [Outcome]           NVARCHAR(40)      NULL,
    [StartedAt]         DATETIMEOFFSET(7) NOT NULL,
    [StartedByActorId] UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProcedureInstance_StartedByActor] REFERENCES [personnel].[Actor] ([ActorId]),
    [CompletedAt]       DATETIMEOFFSET(7) NULL,
    CONSTRAINT [PK_ProcedureInstance] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_ProcedureInstance_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [process].[ProcedureInstance_History]));
GO
CREATE INDEX [IX_ProcedureInstance_Entity] ON [process].[ProcedureInstance] ([EntityId]);
GO
CREATE INDEX [IX_ProcedureInstance_Subject] ON [process].[ProcedureInstance] ([SubjectKind], [SubjectEntityId]) WHERE [IsDeleted] = 0;
GO
CREATE INDEX [IX_ProcedureInstance_Version] ON [process].[ProcedureInstance] ([DefinitionVersionRowId]) WHERE [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'process', @level1type = N'TABLE', @level1name = N'ProcedureInstance';
GO
