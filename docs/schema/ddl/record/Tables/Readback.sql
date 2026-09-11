-- SCHEMA-DESIGN §10.8 (150). Record subclass. A Differs result raises an AsFoundDrift finding (PROCEDURES.md #19).
CREATE TABLE [record].[Readback] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Readback_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Readback_Registry] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Readback_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Readback_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Readback_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Readback_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Readback_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Readback_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ProducedConfigurationFileRevisionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Readback_Produced] REFERENCES [document].[ConfigurationFile] ([RevisionRowId]),
    [ComparedToConfigurationFileRevisionRowId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Readback_ComparedTo] REFERENCES [document].[ConfigurationFile] ([RevisionRowId]),
    [ComparisonResult]   NVARCHAR(20)     NOT NULL CONSTRAINT [CK_Readback_Result] CHECK ([ComparisonResult] IN (N'Identical', N'Differs', N'NotComparable')),
    [DifferenceCount]    INT              NULL,
    [DifferenceDetailRecordEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Readback_DifferenceDetail] REFERENCES [record].[RecordRegistry] ([EntityId]),
    CONSTRAINT [PK_Readback] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Readback_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [record].[Readback_History]));
GO
CREATE INDEX [IX_Readback_Entity] ON [record].[Readback] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'record', @level1type = N'TABLE', @level1name = N'Readback';
GO
