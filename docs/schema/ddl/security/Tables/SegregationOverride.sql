-- SCHEMA-DESIGN §11.7 (158). Every override is an action-log entry with authority. SubjectKind is open (no list stated).
CREATE TABLE [security].[SegregationOverride] (
    [OverrideId]         BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_SegregationOverride] PRIMARY KEY CLUSTERED,
    [RuleDefinitionVersionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_SegregationOverride_Rule] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [SubjectKind]        NVARCHAR(40)     NOT NULL CONSTRAINT [FK_SegregationOverride_SubjectKind] REFERENCES [ref].[SubjectKind] ([SubjectKindCode]),
    [SubjectEntityId]    UNIQUEIDENTIFIER NULL,
    [ActionTaken]        NVARCHAR(100)    NOT NULL,
    [ActorId]            UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_SegregationOverride_Actor] REFERENCES [personnel].[Actor] ([ActorId]),
    [Reason]             NVARCHAR(400)    NOT NULL,
    [ApprovedByActorId]  UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_SegregationOverride_ApprovedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [OccurredAt]         DATETIMEOFFSET(7) NOT NULL,
    [ActionLogId]        BIGINT           NOT NULL CONSTRAINT [FK_SegregationOverride_ActionLog] REFERENCES [audit].[ActionLog] ([ActionLogId])
);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'security', @level1type = N'TABLE', @level1name = N'SegregationOverride';
GO
