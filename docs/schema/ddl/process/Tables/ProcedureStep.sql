-- PROCEDURE-ENGINE §4 (projection). Class Versioned. One row per step of a Program.Procedure version, derived from
-- the canonical document by process.ProjectProcedureVersion on approval and rebuilt if it is projected again. The
-- document is authoritative; these rows are what screens list and impact queries join. BlockPath = block ids from
-- the root joined by '/'. RoleCode is the alias resolved through the document's roles map.
CREATE TABLE [process].[ProcedureStep] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_ProcedureStep_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProcedureStep_Registry] REFERENCES [process].[ProcedureStepRegistry] ([EntityId]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProcedureStep_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProcedureStep_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_ProcedureStep_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ProcedureStep_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ProcedureStep_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [DefinitionVersionRowId] UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProcedureStep_DefinitionVersion] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [StepId]            NVARCHAR(64)      NOT NULL,
    [BlockPath]         NVARCHAR(400)     NOT NULL,
    [Ordinal]           INT               NOT NULL,
    [Title]             NVARCHAR(200)     NOT NULL,
    [RoleAlias]         NVARCHAR(40)      NOT NULL,
    [RoleCode]          NVARCHAR(40)      NOT NULL CONSTRAINT [FK_ProcedureStep_Role] REFERENCES [security].[Role] ([RoleCode]),
    [RecordKindCode]    NVARCHAR(40)      NOT NULL CONSTRAINT [FK_ProcedureStep_RecordKind] REFERENCES [ref].[RecordKind] ([RecordKindCode]),
    [SignoffAction]     NVARCHAR(100)     NULL,
    [RequiresWitness]   BIT               NOT NULL CONSTRAINT [DF_ProcedureStep_RequiresWitness] DEFAULT 0,
    [HasPrecondition]   BIT               NOT NULL CONSTRAINT [DF_ProcedureStep_HasPrecondition] DEFAULT 0,
    [HasDue]            BIT               NOT NULL CONSTRAINT [DF_ProcedureStep_HasDue] DEFAULT 0,
    [AllowsDeviation]   BIT               NOT NULL CONSTRAINT [DF_ProcedureStep_AllowsDeviation] DEFAULT 0,
    [AdvancesWorkflowKey] NVARCHAR(100)   NULL,
    [AdvancesTransition]  NVARCHAR(100)   NULL,
    [ProducesName]      NVARCHAR(40)      NULL,
    [ProducesKind]      NVARCHAR(40)      NULL,
    CONSTRAINT [PK_ProcedureStep] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_ProcedureStep_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [process].[ProcedureStep_History]));
GO
CREATE INDEX [IX_ProcedureStep_Entity] ON [process].[ProcedureStep] ([EntityId]);
GO
CREATE UNIQUE INDEX [UX_ProcedureStep_VersionStep] ON [process].[ProcedureStep] ([DefinitionVersionRowId], [StepId]) WHERE [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'process', @level1type = N'TABLE', @level1name = N'ProcedureStep';
GO
