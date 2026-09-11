-- SCHEMA-DESIGN §12.4 (164). A Preview run writes only this row and its document; an Effective run writes instances.
CREATE TABLE [compliance].[RuleEvaluationRun] (
    [RunId]              UNIQUEIDENTIFIER NOT NULL CONSTRAINT [PK_RuleEvaluationRun] PRIMARY KEY CLUSTERED,
    [RuleDefinitionVersionRowId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_RuleEvaluationRun_Rule] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [Mode]               NVARCHAR(20)     NOT NULL CONSTRAINT [CK_RuleEvaluationRun_Mode] CHECK ([Mode] IN (N'Preview', N'Effective')),
    [Trigger]            NVARCHAR(20)     NOT NULL CONSTRAINT [CK_RuleEvaluationRun_Trigger] CHECK ([Trigger] IN (N'Scheduled', N'FactChanged', N'RuleApproved', N'Manual')),
    [StartedAt]          DATETIMEOFFSET(7) NOT NULL,
    [CompletedAt]        DATETIMEOFFSET(7) NULL,
    [ActorId]            UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_RuleEvaluationRun_Actor] REFERENCES [personnel].[Actor] ([ActorId]),
    [SubjectsScoped]     INT              NULL,
    [InstancesOpened]    INT              NULL,
    [InstancesClosed]    INT              NULL,
    [InstancesUnchanged] INT              NULL,
    [ResultDocumentEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_RuleEvaluationRun_ResultDocument] REFERENCES [document].[DocumentRegistry] ([EntityId])
);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'compliance', @level1type = N'TABLE', @level1name = N'RuleEvaluationRun';
GO
