-- SCHEMA-DESIGN §8.7 (131). Revision subclass: a study. NetworkModelCaseEntityId FK → network.CaseRegistry
-- (FK added in step 13). IsStale is set by rule (PROCEDURES.md #28), stored for the catalogue fact study.is_stale.
-- Standards cited and performing/approving actors are on RevisionLink and Revision (design).
CREATE TABLE [document].[Study] (
    [RevisionRowId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Study_Parent] REFERENCES [document].[Revision] ([RowId]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Study_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Study_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Study_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Study_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Study_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [StudyKind]          NVARCHAR(20)     NOT NULL CONSTRAINT [CK_Study_Kind] CHECK ([StudyKind] IN (N'Coordination', N'FaultLevel', N'Stability', N'ArcFlash', N'LineConstants', N'LoadFlow', N'Other')),
    [Software]           NVARCHAR(100)    NULL,
    [SoftwareVersion]    NVARCHAR(40)     NULL,
    [SystemModelAt]      DATETIMEOFFSET(7) NULL,
    [NetworkModelCaseEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Study_NetworkModelCase] REFERENCES [network].[CaseRegistry] ([EntityId]),
    [FaultLevelAssumptions] NVARCHAR(MAX) NULL,
    [TopologyReference]  NVARCHAR(400)    NULL,
    [ValidWhile]         NVARCHAR(400)    NULL,
    [IsStale]            BIT              NOT NULL CONSTRAINT [DF_Study_IsStale] DEFAULT 0,
    CONSTRAINT [PK_Study] PRIMARY KEY CLUSTERED ([RevisionRowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [document].[Study_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Subclass',
    @level0type = N'SCHEMA', @level0name = N'document', @level1type = N'TABLE', @level1name = N'Study';
GO
