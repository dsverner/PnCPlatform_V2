-- SCHEMA-DESIGN §4.4 (92). Where an asset is: a node or a custody location, never both. This is the
-- device ↔ location assignment of decision 32. Device-vs-position and routed-asset checks are the
-- placement procedure's (PROCEDURES.md #5). WorkRequestEntityId FK → work.WorkRequestRegistry in step 9.
CREATE TABLE [asset].[Placement] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Placement_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Placement_Registry] REFERENCES [asset].[PlacementRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Placement_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Placement_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Placement_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Placement_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Placement_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Placement_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [AssetEntityId]      UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Placement_Asset] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [NodeEntityId]       UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Placement_Node] REFERENCES [location].[NodeRegistry] ([EntityId]),
    [CustodyLocationEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Placement_Custody] REFERENCES [location].[CustodyLocationRegistry] ([EntityId]),
    [PlacementKind]      NVARCHAR(20)     NOT NULL CONSTRAINT [CK_Placement_Kind] CHECK ([PlacementKind] IN (N'Attached', N'Installed', N'Stored', N'AtVendor', N'Retained')),
    [InstalledByActorId] UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Placement_InstalledBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [RemovedByActorId]   UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Placement_RemovedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [WorkRequestEntityId] UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Placement_WorkRequest] REFERENCES [work].[WorkRequestRegistry] ([EntityId]),
    CONSTRAINT [PK_Placement] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Placement_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_Placement_OneLocation] CHECK (([NodeEntityId] IS NOT NULL AND [CustodyLocationEntityId] IS NULL) OR ([NodeEntityId] IS NULL AND [CustodyLocationEntityId] IS NOT NULL))
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [asset].[Placement_History]));
GO
CREATE INDEX [IX_Placement_Entity] ON [asset].[Placement] ([EntityId], [ValidFrom]);
GO
-- a device position holds at most one installed device at an instant
CREATE UNIQUE INDEX [UX_Placement_InstalledAtNode] ON [asset].[Placement] ([NodeEntityId]) WHERE [PlacementKind] = N'Installed' AND [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
CREATE INDEX [IX_Placement_Asset] ON [asset].[Placement] ([AssetEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'asset', @level1type = N'TABLE', @level1name = N'Placement';
GO
