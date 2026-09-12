-- PROCEDURE-ENGINE §4, §6 (#41). Class Versioned. The ruling on one running instance when a new version of its
-- procedure (or a callee) is approved: Keep, Migrate or Cancel, with the reason and the step mapping used.
CREATE TABLE [process].[InstanceMigration] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_InstanceMigration_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_InstanceMigration_Registry] REFERENCES [process].[InstanceMigrationRegistry] ([EntityId]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_InstanceMigration_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_InstanceMigration_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_InstanceMigration_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_InstanceMigration_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_InstanceMigration_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ProcedureInstanceEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_InstanceMigration_Instance] REFERENCES [process].[ProcedureInstanceRegistry] ([EntityId]),
    [FromDefinitionVersionRowId] UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_InstanceMigration_FromVersion] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [ToDefinitionVersionRowId] UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_InstanceMigration_ToVersion] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [Decision]          NVARCHAR(20)      NOT NULL CONSTRAINT [CK_InstanceMigration_Decision] CHECK ([Decision] IN (N'Keep', N'Migrate', N'Cancel')),
    [Reason]            NVARCHAR(400)     NOT NULL,
    [DecidedByActorId] UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_InstanceMigration_DecidedByActor] REFERENCES [personnel].[Actor] ([ActorId]),
    [DecidedAt]         DATETIMEOFFSET(7) NOT NULL,
    [StepMapping] NVARCHAR(MAX) NULL CONSTRAINT [CK_InstanceMigration_StepMappingJson] CHECK ([StepMapping] IS NULL OR ISJSON([StepMapping]) = 1),
    CONSTRAINT [PK_InstanceMigration] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_InstanceMigration_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [process].[InstanceMigration_History]));
GO
CREATE INDEX [IX_InstanceMigration_Entity] ON [process].[InstanceMigration] ([EntityId]);
GO
CREATE INDEX [IX_InstanceMigration_Instance] ON [process].[InstanceMigration] ([ProcedureInstanceEntityId]) WHERE [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'process', @level1type = N'TABLE', @level1name = N'InstanceMigration';
GO
