-- SCHEMA-DESIGN §7.5 (120, 121). Operational state in force: active settings group, blocked function, open
-- test switch, out of service, armed / disarmed … RevertObligationInstanceEntityId FK → compliance (step 12);
-- NotificationRecordEntityId FK → record (step 10); WorkRequestEntityId FK → work (step 9).
CREATE TABLE [scheme].[ProtectionCondition] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_ProtectionCondition_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProtectionCondition_Registry] REFERENCES [scheme].[ProtectionConditionRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_ProtectionCondition_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProtectionCondition_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProtectionCondition_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_ProtectionCondition_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ProtectionCondition_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ProtectionCondition_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [SubjectKind]        NVARCHAR(40)     NOT NULL CONSTRAINT [CK_ProtectionCondition_SubjectKind] CHECK ([SubjectKind] IN (N'ProtectionFunction', N'Scheme', N'Connection', N'Device')),
    [SubjectEntityId]    UNIQUEIDENTIFIER NOT NULL,
    [ConditionKindCode]  NVARCHAR(40)     NOT NULL CONSTRAINT [FK_ProtectionCondition_Kind] REFERENCES [ref].[ConditionKind] ([ConditionKindCode]),
    [ConditionValue]     NVARCHAR(200)    NULL,
    [Reason]             NVARCHAR(400)    NULL,
    [OpenedByActorId]    UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_ProtectionCondition_OpenedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ClosedByActorId]    UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_ProtectionCondition_ClosedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [AuthorisedByActorId] UNIQUEIDENTIFIER NULL    CONSTRAINT [FK_ProtectionCondition_AuthorisedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [RevertObligationInstanceEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_ProtectionCondition_RevertObligation] REFERENCES [compliance].[ObligationInstanceRegistry] ([EntityId]),
    [NotificationRecordEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_ProtectionCondition_NotificationRecord] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [WorkRequestEntityId] UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_ProtectionCondition_WorkRequest] REFERENCES [work].[WorkRequestRegistry] ([EntityId]),
    CONSTRAINT [PK_ProtectionCondition] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_ProtectionCondition_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [scheme].[ProtectionCondition_History]));
GO
CREATE INDEX [IX_ProtectionCondition_Entity] ON [scheme].[ProtectionCondition] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_ProtectionCondition_Subject] ON [scheme].[ProtectionCondition] ([SubjectKind], [SubjectEntityId], [ConditionKindCode]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'scheme', @level1type = N'TABLE', @level1name = N'ProtectionCondition';
GO
