-- SCHEMA-DESIGN §6.7 (113). Shape now; lifted from comms.DNP3PointList. ObjectGroup / Variation / PointIndex
-- are INT (protocol object numbers); ScaleFactor / Offset DECIMAL(28,10) as §2.4 numerics.
CREATE TABLE [connection].[PointMap] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_PointMap_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_PointMap_Registry] REFERENCES [connection].[PointMapRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_PointMap_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_PointMap_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_PointMap_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_PointMap_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_PointMap_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_PointMap_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ProtocolEndpointEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_PointMap_Endpoint] REFERENCES [connection].[ProtocolEndpointRegistry] ([EntityId]),
    [ObjectGroup]        INT              NULL,
    [Variation]          INT              NULL,
    [PointIndex]         INT              NOT NULL,
    [PointName]          NVARCHAR(100)    NULL,
    [Description]        NVARCHAR(MAX)    NULL,
    [AssetEntityId]      UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_PointMap_Asset] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [UnitCode]           NVARCHAR(20)     NULL     CONSTRAINT [FK_PointMap_Unit] REFERENCES [ref].[Unit] ([UnitCode]),
    [ScaleFactor]        DECIMAL(28,10)   NULL,
    [Offset]             DECIMAL(28,10)   NULL,
    CONSTRAINT [PK_PointMap] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_PointMap_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [connection].[PointMap_History]));
GO
CREATE INDEX [IX_PointMap_Entity] ON [connection].[PointMap] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'connection', @level1type = N'TABLE', @level1name = N'PointMap';
GO
