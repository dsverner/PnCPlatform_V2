-- SCHEMA-DESIGN §13.2 (172, decision 21). Class ValidTime. A run of consecutive spans on a line's
-- location.Route with one construction and conductor in force; a grouping over route steps, not a
-- location node. The design writes "ConductorAssetTypeCode / ConductorTemplate": modelled as a
-- reference to the conductor library (ref.ConductorType), recorded in STEPS.md.
CREATE TABLE [network].[LineSection] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_LineSection_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LineSection_Registry] REFERENCES [network].[LineSectionRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_LineSection_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LineSection_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LineSection_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_LineSection_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_LineSection_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_LineSection_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [LineAssetEntityId]                 UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_LineSection_LineAsset] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [FromRouteStepRowId]                UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_LineSection_FromRouteStep] REFERENCES [location].[RouteStep] ([RowId]),
    [ToRouteStepRowId]                  UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_LineSection_ToRouteStep]   REFERENCES [location].[RouteStep] ([RowId]),
    [StructureTypeDefinitionVersionRowId] UNIQUEIDENTIFIER NULL   CONSTRAINT [FK_LineSection_StructureType] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [ConductorTypeCode]                 NVARCHAR(40)     NULL     CONSTRAINT [FK_LineSection_ConductorType] REFERENCES [ref].[ConductorType] ([ConductorTypeCode]),
    [GroundWireCount]                   INT              NULL,
    [LengthKm]                          DECIMAL(18,4)    NULL,
    CONSTRAINT [PK_LineSection] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_LineSection_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [network].[LineSection_History]));
GO
CREATE INDEX [IX_LineSection_Entity] ON [network].[LineSection] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_LineSection_Line] ON [network].[LineSection] ([LineAssetEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'network', @level1type = N'TABLE', @level1name = N'LineSection';
GO
