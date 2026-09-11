-- SCHEMA-DESIGN §3.3 (81). A Segment is a node of type Segment (parent = the linear node) with two
-- extra columns; modelled as an extension sharing the node's EntityId. From/To are maintained by the
-- adjacency procedure (PROCEDURES.md #4).
CREATE TABLE [location].[Segment] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Segment_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Segment_Registry] REFERENCES [location].[NodeRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Segment_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Segment_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Segment_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Segment_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Segment_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Segment_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [FromAdjacencyRowId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Segment_FromAdjacency] REFERENCES [location].[Adjacency] ([RowId]),
    [ToAdjacencyRowId]   UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Segment_ToAdjacency]   REFERENCES [location].[Adjacency] ([RowId]),
    [Length]             DECIMAL(12,3)    NULL,
    CONSTRAINT [PK_Segment] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Segment_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [location].[Segment_History]));
GO
CREATE INDEX [IX_Segment_Entity] ON [location].[Segment] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'location', @level1type = N'TABLE', @level1name = N'Segment';
GO
