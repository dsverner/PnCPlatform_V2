-- SCHEMA-DESIGN §13.1 (187). Class ValidTime. A node of a layer (an ASPEN bus, …): an ELECTRICAL identity
-- — external number, name, voltage — and nothing physical. Where it sits is zero-to-many
-- network.LayerNodeEndpoint rows (the TLM predecessor's lesson: a bus is not a place). ExternalNumber is
-- unique within the layer and is also the LayerNodeNumber alternate key (scoped to the layer).
CREATE TABLE [network].[LayerNode] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_LayerNode_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LayerNode_Registry] REFERENCES [network].[LayerNodeRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_LayerNode_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LayerNode_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LayerNode_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_LayerNode_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_LayerNode_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_LayerNode_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [LayerEntityId]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LayerNode_Layer] REFERENCES [network].[LayerRegistry] ([EntityId]),
    [ExternalNumber]        NVARCHAR(100)     NOT NULL,
    [Name]                  NVARCHAR(200)     NOT NULL,
    [VoltageClassCode]      NVARCHAR(20)      NULL     CONSTRAINT [FK_LayerNode_VoltageClass] REFERENCES [ref].[VoltageClass] ([VoltageClassCode]),
    [FirstCaseEntityId]     UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_LayerNode_FirstCase] REFERENCES [network].[CaseRegistry] ([EntityId]),
    [Notes]                 NVARCHAR(MAX)     NULL,
    CONSTRAINT [PK_LayerNode] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_LayerNode_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [network].[LayerNode_History]));
GO
CREATE INDEX [IX_LayerNode_Entity] ON [network].[LayerNode] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_LayerNode_Number] ON [network].[LayerNode] ([LayerEntityId], [ExternalNumber]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'network', @level1type = N'TABLE', @level1name = N'LayerNode';
GO
