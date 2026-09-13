-- SCHEMA-DESIGN §10.1 (143). Class ValidTime. The middle of the evidence chain: produced by work, cited by
-- evidence links by RowId, never a bare file. Files are documents linked About the record (step 8).
CREATE TABLE [record].[Record] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Record_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Record_Registry] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Record_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Record_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Record_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Record_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Record_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Record_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [RecordKindCode]     NVARCHAR(40)     NOT NULL CONSTRAINT [FK_Record_Kind] REFERENCES [ref].[RecordKind] ([RecordKindCode]),
    [SubjectKind]        NVARCHAR(40)     NOT NULL CONSTRAINT [CK_Record_SubjectKind] CHECK ([SubjectKind] IN (N'Layer', N'LayerNode', N'Node', N'Asset', N'Device', N'Scheme', N'Connection', N'Channel', N'ConfigurationFileRevision', N'DrawingRevision', N'Instrument', N'Person', N'Record', N'Audit', N'SecurityPerimeter', N'Platform', N'WorkRequest', N'SettingsIssuePackage', N'ProcedureInstance')),   -- the last three: PROCEDURE-ENGINE §5 (W4, decision #108)
    [SubjectEntityId]    UNIQUEIDENTIFIER NULL,
    [SecondSubjectKind]  NVARCHAR(40)     NULL     CONSTRAINT [CK_Record_SecondSubjectKind] CHECK ([SecondSubjectKind] IS NULL OR [SecondSubjectKind] IN (N'Layer', N'LayerNode', N'RouteStep', N'Document', N'Node', N'Asset', N'Device', N'Scheme', N'Connection', N'Channel', N'ConfigurationFileRevision', N'DrawingRevision', N'Instrument', N'Person', N'Record', N'TrainingModule', N'WorkRequest', N'SettingsIssuePackage', N'ProcedureInstance')),
    [SecondSubjectEntityId] UNIQUEIDENTIFIER NULL,
    [WorkRequestEntityId] UNIQUEIDENTIFIER NULL    CONSTRAINT [FK_Record_WorkRequest] REFERENCES [work].[WorkRequestRegistry] ([EntityId]),
    [OccurredAt]         DATETIMEOFFSET(7) NOT NULL,
    [TimeSourceQuality]  TINYINT          NOT NULL CONSTRAINT [DF_Record_TimeSourceQuality] DEFAULT 3 CONSTRAINT [CK_Record_TimeSourceQuality] CHECK ([TimeSourceQuality] BETWEEN 0 AND 4),
    [PerformedByActorId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Record_PerformedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [WitnessedByActorId] UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Record_WitnessedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [OverallResult]      NVARCHAR(20)     NULL     CONSTRAINT [CK_Record_OverallResult] CHECK ([OverallResult] IS NULL OR [OverallResult] IN (N'Pass', N'Fail', N'Conditional', N'Informational')),
    [Summary]            NVARCHAR(1000)   NULL,
    [TemplateDefinitionVersionRowId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Record_Template] REFERENCES [config].[DefinitionVersion] ([RowId]),
    CONSTRAINT [PK_Record] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Record_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_Record_Subject] CHECK ([SubjectKind] = N'Platform' OR [SubjectEntityId] IS NOT NULL),   -- PLATFORM-ARCHITECTURE §8.1: the platform is a subject with no entity id
    CONSTRAINT [CK_Record_SecondSubject] CHECK (([SecondSubjectKind] IS NULL AND [SecondSubjectEntityId] IS NULL) OR ([SecondSubjectKind] IS NOT NULL AND [SecondSubjectEntityId] IS NOT NULL))
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [record].[Record_History]));
GO
CREATE INDEX [IX_Record_Entity] ON [record].[Record] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_Record_Subject] ON [record].[Record] ([SubjectKind], [SubjectEntityId], [RecordKindCode], [OccurredAt]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'record', @level1type = N'TABLE', @level1name = N'Record';
GO
-- W7: the settings grid finds a revision's record by its second subject (vSettingsRecord); 11 000 migrated revisions made the lookup a scan (30 s a page)
CREATE INDEX [IX_Record_SecondSubject] ON [record].[Record] ([SecondSubjectKind], [SecondSubjectEntityId], [OccurredAt]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
