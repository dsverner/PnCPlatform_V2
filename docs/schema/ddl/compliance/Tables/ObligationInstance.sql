-- SCHEMA-DESIGN §12.5 (165). Derived by an Effective run; SubjectEntityId null only for kind Platform.
CREATE TABLE [compliance].[ObligationInstance] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_ObligationInstance_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ObligationInstance_Registry] REFERENCES [compliance].[ObligationInstanceRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_ObligationInstance_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ObligationInstance_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ObligationInstance_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_ObligationInstance_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ObligationInstance_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ObligationInstance_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [SubjectKind]        NVARCHAR(40)     NOT NULL CONSTRAINT [CK_ObligationInstance_SubjectKind] CHECK ([SubjectKind] IN (N'Station', N'Node', N'Line', N'ProtectionFunction', N'Scheme', N'Device', N'Asset', N'Connection', N'Person', N'Entity', N'Document', N'Definition', N'Platform')),
    [SubjectEntityId]    UNIQUEIDENTIFIER NULL,
    [RuleDefinitionVersionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_ObligationInstance_Rule] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [RequirementEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_ObligationInstance_Requirement] REFERENCES [compliance].[RequirementRegistry] ([EntityId]),
    [ElectedStandardVersionRowId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_ObligationInstance_ElectedVersion] REFERENCES [compliance].[StandardVersion] ([RowId]),
    [PeriodStartAt]      DATETIMEOFFSET(7) NOT NULL,
    [PeriodEndAt]        DATETIMEOFFSET(7) NULL,
    [Status]             NVARCHAR(20)     NOT NULL CONSTRAINT [CK_ObligationInstance_Status] CHECK ([Status] IN (N'Open', N'Satisfied', N'Exception', N'NotApplicable', N'Superseded')),
    [RaisedWorkRequestEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_ObligationInstance_WorkRequest] REFERENCES [work].[WorkRequestRegistry] ([EntityId]),
    [EvaluationRunId]    UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_ObligationInstance_Run] REFERENCES [compliance].[RuleEvaluationRun] ([RunId]),
    CONSTRAINT [PK_ObligationInstance] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_ObligationInstance_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_ObligationInstance_Subject] CHECK ([SubjectKind] = N'Platform' OR [SubjectEntityId] IS NOT NULL)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [compliance].[ObligationInstance_History]));
GO
CREATE INDEX [IX_ObligationInstance_Entity] ON [compliance].[ObligationInstance] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_ObligationInstance_Subject] ON [compliance].[ObligationInstance] ([SubjectKind], [SubjectEntityId], [Status]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'compliance', @level1type = N'TABLE', @level1name = N'ObligationInstance';
GO
