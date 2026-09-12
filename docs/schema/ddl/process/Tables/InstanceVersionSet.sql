-- PROCEDURE-ENGINE §4, §6 (#40). Class Versioned. Every callee version resolved when the root instance started:
-- 'which procedure did this request follow' has exactly one answer.
CREATE TABLE [process].[InstanceVersionSet] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_InstanceVersionSet_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_InstanceVersionSet_Registry] REFERENCES [process].[InstanceVersionSetRegistry] ([EntityId]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_InstanceVersionSet_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_InstanceVersionSet_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_InstanceVersionSet_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_InstanceVersionSet_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_InstanceVersionSet_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ProcedureInstanceEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_InstanceVersionSet_Instance] REFERENCES [process].[ProcedureInstanceRegistry] ([EntityId]),
    [CalleeKey]         NVARCHAR(100)     NOT NULL,
    [DefinitionVersionRowId] UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_InstanceVersionSet_DefinitionVersion] REFERENCES [config].[DefinitionVersion] ([RowId]),
    CONSTRAINT [PK_InstanceVersionSet] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_InstanceVersionSet_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [process].[InstanceVersionSet_History]));
GO
CREATE INDEX [IX_InstanceVersionSet_Entity] ON [process].[InstanceVersionSet] ([EntityId]);
GO
CREATE UNIQUE INDEX [UX_InstanceVersionSet_Callee] ON [process].[InstanceVersionSet] ([ProcedureInstanceEntityId], [CalleeKey]) WHERE [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'process', @level1type = N'TABLE', @level1name = N'InstanceVersionSet';
GO
