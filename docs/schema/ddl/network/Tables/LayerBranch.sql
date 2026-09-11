-- SCHEMA-DESIGN §13.1 (188). Class ValidTime. A branch of a layer between two of its nodes, with the
-- sequence parameters the external system holds (per unit on its base). Its physical path is DERIVED
-- (network.vLayerBranchPath): the route steps of LineAssetEntityId between the two nodes' primary
-- endpoints on that line — null while either endpoint is unresolved. Never stored (Phase57 tombstone).
CREATE TABLE [network].[LayerBranch] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_LayerBranch_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LayerBranch_Registry] REFERENCES [network].[LayerBranchRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_LayerBranch_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LayerBranch_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LayerBranch_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_LayerBranch_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_LayerBranch_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_LayerBranch_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [LayerEntityId]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LayerBranch_Layer] REFERENCES [network].[LayerRegistry] ([EntityId]),
    [BranchKind]            NVARCHAR(40)      NOT NULL CONSTRAINT [CK_LayerBranch_Kind] CHECK ([BranchKind] IN (N'LineSection', N'TransformerWinding', N'SeriesElement', N'Switch')),
    [FromNodeEntityId]      UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LayerBranch_FromNode] REFERENCES [network].[LayerNodeRegistry] ([EntityId]),
    [ToNodeEntityId]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LayerBranch_ToNode]   REFERENCES [network].[LayerNodeRegistry] ([EntityId]),
    [CircuitId]             NVARCHAR(40)      NULL,
    [LineAssetEntityId]     UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_LayerBranch_Line] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [R1]                    DECIMAL(18,8)     NULL,
    [X1]                    DECIMAL(18,8)     NULL,
    [B1]                    DECIMAL(18,8)     NULL,
    [R0]                    DECIMAL(18,8)     NULL,
    [X0]                    DECIMAL(18,8)     NULL,
    [B0]                    DECIMAL(18,8)     NULL,
    [LengthKm]              DECIMAL(18,4)     NULL,
    [Notes]                 NVARCHAR(MAX)     NULL,
    CONSTRAINT [CK_LayerBranch_NotSelf] CHECK ([FromNodeEntityId] <> [ToNodeEntityId]),
    CONSTRAINT [PK_LayerBranch] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_LayerBranch_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [network].[LayerBranch_History]));
GO
CREATE INDEX [IX_LayerBranch_Entity] ON [network].[LayerBranch] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_LayerBranch_Layer] ON [network].[LayerBranch] ([LayerEntityId], [FromNodeEntityId], [ToNodeEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'network', @level1type = N'TABLE', @level1name = N'LayerBranch';
GO
