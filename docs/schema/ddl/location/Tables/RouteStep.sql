-- SCHEMA-DESIGN §3.4 (82). One step of a route: the node passed, what is occupied there, and for a
-- channel the medium asset at this step.
CREATE TABLE [location].[RouteStep] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_RouteStep_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_RouteStep_Registry] REFERENCES [location].[RouteStepRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_RouteStep_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_RouteStep_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_RouteStep_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_RouteStep_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_RouteStep_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_RouteStep_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [RouteEntityId]        UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_RouteStep_Route] REFERENCES [location].[RouteRegistry] ([EntityId]),
    [Sequence]             INT              NOT NULL,
    [NodeEntityId]         UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_RouteStep_Node] REFERENCES [location].[NodeRegistry] ([EntityId]),
    [OccupiedNodeEntityId] UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_RouteStep_OccupiedNode] REFERENCES [location].[NodeRegistry] ([EntityId]),
    [OccupiedAssetEntityId] UNIQUEIDENTIFIER NULL    CONSTRAINT [FK_RouteStep_OccupiedAsset] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    CONSTRAINT [PK_RouteStep] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_RouteStep_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [location].[RouteStep_History]));
GO
CREATE INDEX [IX_RouteStep_Entity] ON [location].[RouteStep] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_RouteStep_Node] ON [location].[RouteStep] ([NodeEntityId]) WHERE [IsDeleted] = 0 AND [ValidTo] IS NULL;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'location', @level1type = N'TABLE', @level1name = N'RouteStep';
GO
