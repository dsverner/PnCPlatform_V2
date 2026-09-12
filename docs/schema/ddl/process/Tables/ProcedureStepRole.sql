-- PROCEDURE-ENGINE §4 (projection). Class Versioned. Who may perform a projected step: the resolved role code and the
-- alias's competency expression as canonical AST (null when the alias declares none).
CREATE TABLE [process].[ProcedureStepRole] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_ProcedureStepRole_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProcedureStepRole_Registry] REFERENCES [process].[ProcedureStepRoleRegistry] ([EntityId]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProcedureStepRole_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProcedureStepRole_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_ProcedureStepRole_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ProcedureStepRole_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ProcedureStepRole_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ProcedureStepRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_ProcedureStepRole_Step] REFERENCES [process].[ProcedureStep] ([RowId]),
    [RoleCode]          NVARCHAR(40)      NOT NULL CONSTRAINT [FK_ProcedureStepRole_Role] REFERENCES [security].[Role] ([RoleCode]),
    [RequiresAst] NVARCHAR(MAX) NULL CONSTRAINT [CK_ProcedureStepRole_RequiresAstJson] CHECK ([RequiresAst] IS NULL OR ISJSON([RequiresAst]) = 1),
    CONSTRAINT [PK_ProcedureStepRole] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_ProcedureStepRole_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [process].[ProcedureStepRole_History]));
GO
CREATE INDEX [IX_ProcedureStepRole_Entity] ON [process].[ProcedureStepRole] ([EntityId]);
GO
CREATE INDEX [IX_ProcedureStepRole_Step] ON [process].[ProcedureStepRole] ([ProcedureStepRowId]) WHERE [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'process', @level1type = N'TABLE', @level1name = N'ProcedureStepRole';
GO
