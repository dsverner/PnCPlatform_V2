-- PROCEDURE-ENGINE §4 (projection). Class Versioned. The call graph of a version: every call block and the procedure
-- key it names, for version pinning (§6) and impact.
CREATE TABLE [process].[ProcedureCall] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_ProcedureCall_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProcedureCall_Registry] REFERENCES [process].[ProcedureCallRegistry] ([EntityId]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProcedureCall_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProcedureCall_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_ProcedureCall_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ProcedureCall_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ProcedureCall_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [DefinitionVersionRowId] UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProcedureCall_DefinitionVersion] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [BlockPath]         NVARCHAR(400)     NOT NULL,
    [CalleeKey]         NVARCHAR(100)     NOT NULL,
    CONSTRAINT [PK_ProcedureCall] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_ProcedureCall_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [process].[ProcedureCall_History]));
GO
CREATE INDEX [IX_ProcedureCall_Entity] ON [process].[ProcedureCall] ([EntityId]);
GO
CREATE INDEX [IX_ProcedureCall_Callee] ON [process].[ProcedureCall] ([CalleeKey]) WHERE [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'process', @level1type = N'TABLE', @level1name = N'ProcedureCall';
GO
