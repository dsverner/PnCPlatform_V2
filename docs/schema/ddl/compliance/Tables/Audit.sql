-- SCHEMA-DESIGN §12.8 (168). Findings are record.Finding rows of category AuditFinding with the audit as subject.
CREATE TABLE [compliance].[Audit] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Audit_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Audit_Registry] REFERENCES [compliance].[AuditRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Audit_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Audit_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Audit_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Audit_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Audit_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Audit_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [AuditingEntityEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Audit_AuditingEntity] REFERENCES [party].[EntityRegistry] ([EntityId]),
    [AuditKind]          NVARCHAR(20)     NOT NULL CONSTRAINT [CK_Audit_Kind] CHECK ([AuditKind] IN (N'Regulatory', N'Internal', N'SpotCheck', N'SelfCertification')),
    [ScopeDescription]   NVARCHAR(MAX)    NULL,
    [PeriodStartAt]      DATETIMEOFFSET(7) NULL,
    [PeriodEndAt]        DATETIMEOFFSET(7) NULL,
    [NoticeReceivedAt]   DATETIMEOFFSET(7) NULL,
    [FieldworkStartAt]   DATETIMEOFFSET(7) NULL,
    [ClosedAt]           DATETIMEOFFSET(7) NULL,
    [LeadActorId]        UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Audit_Lead] REFERENCES [personnel].[Actor] ([ActorId]),
    CONSTRAINT [PK_Audit] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Audit_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [compliance].[Audit_History]));
GO
CREATE INDEX [IX_Audit_Entity] ON [compliance].[Audit] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'compliance', @level1type = N'TABLE', @level1name = N'Audit';
GO
