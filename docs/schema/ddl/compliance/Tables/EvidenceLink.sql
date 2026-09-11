-- SCHEMA-DESIGN §12.6 (166), decision 47: cites a record's fact version, never a file. Many-to-many.
CREATE TABLE [compliance].[EvidenceLink] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_EvidenceLink_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_EvidenceLink_Registry] REFERENCES [compliance].[EvidenceLinkRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_EvidenceLink_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_EvidenceLink_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_EvidenceLink_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_EvidenceLink_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_EvidenceLink_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_EvidenceLink_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ObligationInstanceRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_EvidenceLink_Instance] REFERENCES [compliance].[ObligationInstance] ([RowId]),
    [RecordRowId]        UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_EvidenceLink_Record] REFERENCES [record].[Record] ([RowId]),
    [JudgedByActorId]    UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_EvidenceLink_JudgedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [JudgedAt]           DATETIMEOFFSET(7) NOT NULL,
    [Sufficiency]        NVARCHAR(20)     NOT NULL CONSTRAINT [CK_EvidenceLink_Sufficiency] CHECK ([Sufficiency] IN (N'Sufficient', N'Partial', N'Insufficient')),
    [EvidenceDefinitionVersionRowId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_EvidenceLink_EvidenceDefinition] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [Notes]              NVARCHAR(MAX)    NULL,
    CONSTRAINT [PK_EvidenceLink] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_EvidenceLink_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [compliance].[EvidenceLink_History]));
GO
CREATE INDEX [IX_EvidenceLink_Entity] ON [compliance].[EvidenceLink] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_EvidenceLink_Instance] ON [compliance].[EvidenceLink] ([ObligationInstanceRowId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
CREATE INDEX [IX_EvidenceLink_Record] ON [compliance].[EvidenceLink] ([RecordRowId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'compliance', @level1type = N'TABLE', @level1name = N'EvidenceLink';
GO
