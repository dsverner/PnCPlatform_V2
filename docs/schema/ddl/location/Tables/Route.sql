-- SCHEMA-DESIGN §3.4 (82). The location of a routed asset (cable, line, channel, panel wire).
CREATE TABLE [location].[Route] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Route_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Route_Registry] REFERENCES [location].[RouteRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Route_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Route_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Route_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Route_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Route_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Route_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [OwnerAssetEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Route_OwnerAsset] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [RouteKind]          NVARCHAR(20)     NOT NULL CONSTRAINT [CK_Route_Kind] CHECK ([RouteKind] IN (N'Cable', N'Line', N'Channel', N'PanelWire')),
    [FromNodeEntityId]   UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Route_FromNode] REFERENCES [location].[NodeRegistry] ([EntityId]),
    [ToNodeEntityId]     UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Route_ToNode]   REFERENCES [location].[NodeRegistry] ([EntityId]),
    CONSTRAINT [PK_Route] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Route_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [location].[Route_History]));
GO
CREATE INDEX [IX_Route_Entity] ON [location].[Route] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'location', @level1type = N'TABLE', @level1name = N'Route';
GO
