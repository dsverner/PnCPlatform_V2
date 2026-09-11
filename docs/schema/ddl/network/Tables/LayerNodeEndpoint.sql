-- SCHEMA-DESIGN §13.1 (187). Class ValidTime. A physical endpoint of a layer node: the node is anchored
-- at a Structure node, a RouteStep (a span on a line's route) or another location node (a station or
-- equipment position), optionally scoped to one line asset so a node on a shared tower is unambiguous.
-- Many per node; one primary per (node, line). Written only through network.AddLayerNodeEndpoint, which
-- checks the anchor lies on the scoped line's route. Never cached on the node (Phase57/58 tombstones).
CREATE TABLE [network].[LayerNodeEndpoint] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_LayerNodeEndpoint_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LayerNodeEndpoint_Registry] REFERENCES [network].[LayerNodeEndpointRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_LayerNodeEndpoint_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LayerNodeEndpoint_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LayerNodeEndpoint_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_LayerNodeEndpoint_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_LayerNodeEndpoint_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_LayerNodeEndpoint_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [LayerNodeEntityId]     UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LayerNodeEndpoint_Node] REFERENCES [network].[LayerNodeRegistry] ([EntityId]),
    [AnchorKind]            NVARCHAR(40)      NOT NULL CONSTRAINT [CK_LayerNodeEndpoint_AnchorKind] CHECK ([AnchorKind] IN (N'Structure', N'RouteStep', N'Node')),
    [AnchorEntityId]        UNIQUEIDENTIFIER  NOT NULL,
    [LineAssetEntityId]     UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_LayerNodeEndpoint_Line] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [IsPrimary]             BIT               NOT NULL CONSTRAINT [DF_LayerNodeEndpoint_IsPrimary] DEFAULT 0,
    [SnapMethod]            NVARCHAR(20)      NOT NULL CONSTRAINT [CK_LayerNodeEndpoint_SnapMethod] CHECK ([SnapMethod] IN (N'Manual', N'Reconciled', N'Imported')),
    [Location]              GEOGRAPHY         NULL,
    [Notes]                 NVARCHAR(MAX)     NULL,
    CONSTRAINT [PK_LayerNodeEndpoint] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_LayerNodeEndpoint_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [network].[LayerNodeEndpoint_History]));
GO
CREATE INDEX [IX_LayerNodeEndpoint_Entity] ON [network].[LayerNodeEndpoint] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_LayerNodeEndpoint_Node] ON [network].[LayerNodeEndpoint] ([LayerNodeEntityId], [LineAssetEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
CREATE UNIQUE INDEX [UX_LayerNodeEndpoint_Primary] ON [network].[LayerNodeEndpoint] ([LayerNodeEntityId], [LineAssetEntityId]) WHERE [IsPrimary] = 1 AND [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'network', @level1type = N'TABLE', @level1name = N'LayerNodeEndpoint';
GO
