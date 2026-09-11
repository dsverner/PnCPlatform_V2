-- SCHEMA-DESIGN §9.4 (137). Class ValidTime. CascadeNumber is held as a column with a unique filtered index
-- (the design calls it an alternate key; work.AlternateKey names Work Requests, so the Cascade order carries
-- its own number — STEPS.md). Completion direction is the open change-order question (vision §11.2).
CREATE TABLE [work].[CascadeWorkOrder] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_CascadeWorkOrder_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_CascadeWorkOrder_Registry] REFERENCES [work].[CascadeWorkOrderRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_CascadeWorkOrder_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_CascadeWorkOrder_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_CascadeWorkOrder_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_CascadeWorkOrder_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_CascadeWorkOrder_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_CascadeWorkOrder_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [CascadeNumber]      NVARCHAR(100)    NOT NULL,
    [CascadeStatus]      NVARCHAR(40)     NULL,
    [MappedNodeEntityId] UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_CascadeWorkOrder_MappedNode] REFERENCES [location].[NodeRegistry] ([EntityId]),
    [CascadeWorkOrderType] NVARCHAR(40)   NULL,
    [LastSyncedAt]       DATETIMEOFFSET(7) NULL,
    [SyncDirection]      NVARCHAR(20)     NULL     CONSTRAINT [CK_CascadeWorkOrder_SyncDirection] CHECK ([SyncDirection] IS NULL OR [SyncDirection] IN (N'ToCascade', N'FromCascade', N'Manual')),
    [Notes]              NVARCHAR(MAX)    NULL,
    CONSTRAINT [PK_CascadeWorkOrder] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_CascadeWorkOrder_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [work].[CascadeWorkOrder_History]));
GO
CREATE INDEX [IX_CascadeWorkOrder_Entity] ON [work].[CascadeWorkOrder] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_CascadeWorkOrder_Number] ON [work].[CascadeWorkOrder] ([CascadeNumber]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'work', @level1type = N'TABLE', @level1name = N'CascadeWorkOrder';
GO
