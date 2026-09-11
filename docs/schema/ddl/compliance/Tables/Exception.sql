-- SCHEMA-DESIGN §12.8 (168). ClockDueAt is derived at opening from the event instant and the rule version and
-- stored; re-derived if the rule version changes (PROCEDURES.md #23). Misoperation → opened by the
-- operation procedure (PROCEDURES.md #13).
CREATE TABLE [compliance].[Exception] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Exception_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Exception_Registry] REFERENCES [compliance].[ExceptionRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Exception_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Exception_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Exception_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Exception_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Exception_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Exception_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [SubjectKind]        NVARCHAR(40)     NOT NULL CONSTRAINT [CK_Exception_SubjectKind] CHECK ([SubjectKind] IN (N'Station', N'Scheme', N'Device', N'Asset', N'Connection', N'Person', N'Entity', N'Document', N'Definition', N'Platform')),
    [SubjectEntityId]    UNIQUEIDENTIFIER NULL,
    [RuleDefinitionVersionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Exception_Rule] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [ObligationInstanceRowId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Exception_Instance] REFERENCES [compliance].[ObligationInstance] ([RowId]),
    [ExceptionKind]      NVARCHAR(30)     NOT NULL CONSTRAINT [CK_Exception_Kind] CHECK ([ExceptionKind] IN (N'SelfReport', N'Misoperation', N'MissedCadence', N'TechnicalFeasibility', N'AuditFinding')),
    [OpenedAt]           DATETIMEOFFSET(7) NOT NULL,
    [OpenedByActorId]    UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Exception_OpenedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ClockDueAt]         DATETIMEOFFSET(7) NULL,
    [MitigationPlanDocumentEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Exception_MitigationPlan] REFERENCES [document].[DocumentRegistry] ([EntityId]),
    [ReportedAt]         DATETIMEOFFSET(7) NULL,
    [ReportedToEntityEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Exception_ReportedTo] REFERENCES [party].[EntityRegistry] ([EntityId]),
    [ReportReference]    NVARCHAR(100)    NULL,
    [ClosedAt]           DATETIMEOFFSET(7) NULL,
    [ClosedByActorId]    UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Exception_ClosedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ClosureBasis]       NVARCHAR(400)    NULL,
    CONSTRAINT [PK_Exception] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Exception_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_Exception_Subject] CHECK ([SubjectKind] = N'Platform' OR [SubjectEntityId] IS NOT NULL)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [compliance].[Exception_History]));
GO
CREATE INDEX [IX_Exception_Entity] ON [compliance].[Exception] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_Exception_Subject] ON [compliance].[Exception] ([SubjectKind], [SubjectEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'compliance', @level1type = N'TABLE', @level1name = N'Exception';
GO
