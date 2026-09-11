-- SCHEMA-DESIGN §12.7 (167). Immutable once ApprovedAt is set (PROCEDURES.md #24); a correction is a new package
-- citing the old. Class Versioned (system-versioned, no valid time); the design's PackageId is the EntityId.
CREATE TABLE [compliance].[EvidencePackage] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_EvidencePackage_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_EvidencePackage_Registry] REFERENCES [compliance].[EvidencePackageRegistry] ([EntityId]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_EvidencePackage_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_EvidencePackage_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_EvidencePackage_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_EvidencePackage_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_EvidencePackage_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [AuditRequestEntityId] UNIQUEIDENTIFIER NULL  CONSTRAINT [FK_EvidencePackage_AuditRequest] REFERENCES [compliance].[AuditRequestRegistry] ([EntityId]),
    [SubjectKind]        NVARCHAR(40)     NOT NULL CONSTRAINT [CK_EvidencePackage_SubjectKind] CHECK ([SubjectKind] IN (N'Station', N'Scheme', N'Device', N'Asset', N'Connection', N'Person', N'Entity', N'Document', N'Definition', N'Platform')),
    [SubjectEntityId]    UNIQUEIDENTIFIER NULL,
    [StandardVersionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_EvidencePackage_StandardVersion] REFERENCES [compliance].[StandardVersion] ([RowId]),
    [PeriodStartAt]      DATETIMEOFFSET(7) NOT NULL,
    [PeriodEndAt]        DATETIMEOFFSET(7) NOT NULL,
    [ValidAsOf]          DATETIMEOFFSET(7) NOT NULL,
    [BelievedAsOf]       DATETIMEOFFSET(7) NOT NULL,
    [PreparedByActorId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_EvidencePackage_PreparedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [PreparedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ReviewedByActorId]  UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_EvidencePackage_ReviewedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ReviewedAt]         DATETIMEOFFSET(7) NULL,
    [ApprovedByActorId]  UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_EvidencePackage_ApprovedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ApprovedAt]         DATETIMEOFFSET(7) NULL,
    [SubmittedAt]        DATETIMEOFFSET(7) NULL,
    [SubmittedToEntityEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_EvidencePackage_SubmittedTo] REFERENCES [party].[EntityRegistry] ([EntityId]),
    [PackageDocumentEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_EvidencePackage_Document] REFERENCES [document].[DocumentRegistry] ([EntityId]),
    [PackageHash]        BINARY(32)       NULL,
    CONSTRAINT [PK_EvidencePackage] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_EvidencePackage_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [compliance].[EvidencePackage_History]));
GO
CREATE INDEX [IX_EvidencePackage_Entity] ON [compliance].[EvidencePackage] ([EntityId]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'compliance', @level1type = N'TABLE', @level1name = N'EvidencePackage';
GO
