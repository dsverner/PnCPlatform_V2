-- SCHEMA-DESIGN §10.9 (151). Record subclass: SCD versus registry, one Finding per unmatched IED (PROCEDURES.md #21).
CREATE TABLE [record].[ConsistencyCheck] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_ConsistencyCheck_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ConsistencyCheck_Registry] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_ConsistencyCheck_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ConsistencyCheck_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ConsistencyCheck_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_ConsistencyCheck_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ConsistencyCheck_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ConsistencyCheck_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ScdConfigurationFileRevisionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_ConsistencyCheck_Scd] REFERENCES [document].[ConfigurationFile] ([RevisionRowId]),
    [IedsInScl]          INT              NOT NULL,
    [IedsInRegistry]     INT              NOT NULL,
    [Matched]            INT              NOT NULL,
    [UnmatchedScl]       INT              NOT NULL,
    [UnmatchedRegistry]  INT              NOT NULL,
    CONSTRAINT [PK_ConsistencyCheck] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_ConsistencyCheck_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [record].[ConsistencyCheck_History]));
GO
CREATE INDEX [IX_ConsistencyCheck_Entity] ON [record].[ConsistencyCheck] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'record', @level1type = N'TABLE', @level1name = N'ConsistencyCheck';
GO
