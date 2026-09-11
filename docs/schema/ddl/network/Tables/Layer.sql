-- SCHEMA-DESIGN §13.1 (186, 190). Class ValidTime. An overlay layer: a user-created model of an external
-- system (ASPEN OneLiner first; any other) mapped onto the physical model. Everything particular to the
-- system is the layer's content — its export template (a Transform.Export definition) and its import /
-- reconciliation rules (a Transform.Import definition). No column names a system; no code does either.
CREATE TABLE [network].[Layer] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Layer_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Layer_Registry] REFERENCES [network].[LayerRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Layer_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Layer_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Layer_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Layer_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Layer_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Layer_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [Name]                              NVARCHAR(200)     NOT NULL,
    [Description]                       NVARCHAR(MAX)     NULL,
    [ExportTransformDefinitionEntityId] UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Layer_ExportTransform] REFERENCES [config].[DefinitionRegistry] ([EntityId]),
    [ImportTransformDefinitionEntityId] UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Layer_ImportTransform] REFERENCES [config].[DefinitionRegistry] ([EntityId]),
    [OwnerEntityEntityId]               UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Layer_Owner] REFERENCES [party].[EntityRegistry] ([EntityId]),
    [Notes]                             NVARCHAR(MAX)     NULL,
    CONSTRAINT [PK_Layer] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Layer_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [network].[Layer_History]));
GO
CREATE INDEX [IX_Layer_Entity] ON [network].[Layer] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_Layer_Name] ON [network].[Layer] ([Name]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'network', @level1type = N'TABLE', @level1name = N'Layer';
GO
