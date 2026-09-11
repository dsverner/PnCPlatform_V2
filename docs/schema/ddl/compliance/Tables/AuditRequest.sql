-- SCHEMA-DESIGN §12.8 (168).
CREATE TABLE [compliance].[AuditRequest] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_AuditRequest_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AuditRequest_Registry] REFERENCES [compliance].[AuditRequestRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_AuditRequest_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AuditRequest_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AuditRequest_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_AuditRequest_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AuditRequest_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AuditRequest_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [AuditEntityId]      UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_AuditRequest_Audit] REFERENCES [compliance].[AuditRegistry] ([EntityId]),
    [RequestReference]   NVARCHAR(100)    NOT NULL,
    [RequirementEntityId] UNIQUEIDENTIFIER NULL    CONSTRAINT [FK_AuditRequest_Requirement] REFERENCES [compliance].[RequirementRegistry] ([EntityId]),
    [SubjectKind]        NVARCHAR(40)     NULL     CONSTRAINT [FK_AuditRequest_SubjectKind] REFERENCES [ref].[SubjectKind] ([SubjectKindCode]),
    [SubjectEntityId]    UNIQUEIDENTIFIER NULL,
    [RequestedAt]        DATETIMEOFFSET(7) NOT NULL,
    [DueAt]              DATETIMEOFFSET(7) NULL,
    [Description]        NVARCHAR(MAX)    NULL,
    [AnsweredByPackageEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_AuditRequest_Package] REFERENCES [compliance].[EvidencePackageRegistry] ([EntityId]),
    CONSTRAINT [PK_AuditRequest] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_AuditRequest_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [compliance].[AuditRequest_History]));
GO
CREATE INDEX [IX_AuditRequest_Entity] ON [compliance].[AuditRequest] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_AuditRequest_Audit] ON [compliance].[AuditRequest] ([AuditEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'compliance', @level1type = N'TABLE', @level1name = N'AuditRequest';
GO
