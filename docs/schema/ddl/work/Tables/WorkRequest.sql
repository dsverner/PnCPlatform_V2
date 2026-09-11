-- SCHEMA-DESIGN §9.1 (134). Class ValidTime. Status is the workflow instance's state, assignee is a
-- security.Grant (ScopeKind WorkRequest), due is derived from the obligation — none are stored (design).
-- WorkRequestNumber and LegacyChangeRequestNumber are work.AlternateKey rows. PriorityCode is nullable
-- because ref.Priority has no seeded values (STEPS.md).
CREATE TABLE [work].[WorkRequest] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_WorkRequest_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_WorkRequest_Registry] REFERENCES [work].[WorkRequestRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_WorkRequest_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_WorkRequest_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_WorkRequest_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_WorkRequest_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_WorkRequest_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_WorkRequest_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ParentWorkRequestEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_WorkRequest_Parent] REFERENCES [work].[WorkRequestRegistry] ([EntityId]),
    [WorkTypeDefinitionVersionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_WorkRequest_WorkType] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [Title]              NVARCHAR(200)    NOT NULL,
    [Description]        NVARCHAR(MAX)    NULL,
    [SpecialInstructions] NVARCHAR(MAX)   NULL,
    [PriorityCode]       NVARCHAR(40)     NULL     CONSTRAINT [FK_WorkRequest_Priority] REFERENCES [ref].[Priority] ([PriorityCode]),
    [ScopeKind]          NVARCHAR(40)     NOT NULL CONSTRAINT [CK_WorkRequest_ScopeKind] CHECK ([ScopeKind] IN (N'Node', N'Asset', N'Scheme', N'Connection', N'Channel', N'ObligationInstance', N'ProtectionOperation')),
    [ScopeEntityId]      UNIQUEIDENTIFIER NOT NULL,
    [PlannedStartAt]     DATETIMEOFFSET(7) NULL,
    [PlannedEndAt]       DATETIMEOFFSET(7) NULL,
    [ActualStartAt]      DATETIMEOFFSET(7) NULL,
    [ActualEndAt]        DATETIMEOFFSET(7) NULL,
    [EstimatedHours]     DECIMAL(8,2)     NULL,
    [OutageRequired]     BIT              NOT NULL CONSTRAINT [DF_WorkRequest_OutageRequired] DEFAULT 0,
    [OutageWindowStartAt] DATETIMEOFFSET(7) NULL,
    [OutageWindowEndAt]  DATETIMEOFFSET(7) NULL,
    [OutageApprovalReference] NVARCHAR(100) NULL,
    [RaisedByObligationInstanceEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_WorkRequest_RaisedByObligation] REFERENCES [compliance].[ObligationInstanceRegistry] ([EntityId]),
    [RaisedByRecordEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_WorkRequest_RaisedByRecord] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [Notes]              NVARCHAR(MAX)    NULL,
    CONSTRAINT [PK_WorkRequest] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_WorkRequest_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_WorkRequest_NotOwnParent] CHECK ([ParentWorkRequestEntityId] IS NULL OR [ParentWorkRequestEntityId] <> [EntityId]),
    CONSTRAINT [CK_WorkRequest_Outage] CHECK ([OutageWindowStartAt] IS NULL OR [OutageWindowEndAt] IS NULL OR [OutageWindowEndAt] >= [OutageWindowStartAt])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [work].[WorkRequest_History]));
GO
CREATE INDEX [IX_WorkRequest_Entity] ON [work].[WorkRequest] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_WorkRequest_Scope] ON [work].[WorkRequest] ([ScopeKind], [ScopeEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
CREATE INDEX [IX_WorkRequest_Parent] ON [work].[WorkRequest] ([ParentWorkRequestEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'work', @level1type = N'TABLE', @level1name = N'WorkRequest';
GO
