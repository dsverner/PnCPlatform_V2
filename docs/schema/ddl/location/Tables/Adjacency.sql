-- SCHEMA-DESIGN §3.3 (81). What a linear node (raceway, right of way) touches, in order along it.
CREATE TABLE [location].[Adjacency] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Adjacency_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Adjacency_Registry] REFERENCES [location].[AdjacencyRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Adjacency_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Adjacency_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Adjacency_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Adjacency_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Adjacency_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Adjacency_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [LinearNodeEntityId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Adjacency_LinearNode]  REFERENCES [location].[NodeRegistry] ([EntityId]),
    [TouchedNodeEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Adjacency_TouchedNode] REFERENCES [location].[NodeRegistry] ([EntityId]),
    [Sequence]            INT              NOT NULL,
    [Chainage]            DECIMAL(12,3)    NULL,
    CONSTRAINT [PK_Adjacency] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Adjacency_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [location].[Adjacency_History]));
GO
CREATE INDEX [IX_Adjacency_Entity] ON [location].[Adjacency] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'location', @level1type = N'TABLE', @level1name = N'Adjacency';
GO
