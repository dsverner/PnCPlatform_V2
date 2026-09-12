-- PROCEDURE-ENGINE §4 (projection). Class Versioned. Every fact any expression of the version reads, by the block that
-- reads it — the impact index (which procedures does a catalogue change touch).
CREATE TABLE [process].[ProcedureFactUse] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_ProcedureFactUse_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProcedureFactUse_Registry] REFERENCES [process].[ProcedureFactUseRegistry] ([EntityId]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProcedureFactUse_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProcedureFactUse_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_ProcedureFactUse_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ProcedureFactUse_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ProcedureFactUse_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [DefinitionVersionRowId] UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProcedureFactUse_DefinitionVersion] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [BlockPath]         NVARCHAR(400)     NOT NULL,
    [FactName]          NVARCHAR(200)     NOT NULL,
    CONSTRAINT [PK_ProcedureFactUse] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_ProcedureFactUse_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [process].[ProcedureFactUse_History]));
GO
CREATE INDEX [IX_ProcedureFactUse_Entity] ON [process].[ProcedureFactUse] ([EntityId]);
GO
CREATE INDEX [IX_ProcedureFactUse_Fact] ON [process].[ProcedureFactUse] ([FactName]) WHERE [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'process', @level1type = N'TABLE', @level1name = N'ProcedureFactUse';
GO
