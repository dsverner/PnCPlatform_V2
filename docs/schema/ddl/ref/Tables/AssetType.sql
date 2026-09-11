-- SCHEMA-DESIGN §4.1 (89). Asset types with class and the device / routed / assembly flags and a
-- default template. Rows come from migration (§14.2: the predecessor's 54 codes + the sketch
-- additions); nothing is seeded here because the design states no class per added type.
CREATE TABLE [ref].[AssetType] (
    [AssetTypeCode]     NVARCHAR(40)      NOT NULL,
    [Name]              NVARCHAR(200)     NOT NULL,
    [Description]       NVARCHAR(MAX)     NULL,
    [AssetClassCode]    NVARCHAR(40)      NOT NULL CONSTRAINT [FK_AssetType_Class] REFERENCES [ref].[AssetClass] ([AssetClassCode]),
    [IsDevice]          BIT               NOT NULL CONSTRAINT [DF_AssetType_IsDevice] DEFAULT 0,
    [IsRouted]          BIT               NOT NULL CONSTRAINT [DF_AssetType_IsRouted] DEFAULT 0,
    [IsAssembly]        BIT               NOT NULL CONSTRAINT [DF_AssetType_IsAssembly] DEFAULT 0,
    [DefaultTemplateDefinitionEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_AssetType_DefaultTemplate] REFERENCES [config].[DefinitionRegistry] ([EntityId]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AssetType_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AssetType_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_AssetType_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AssetType_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_AssetType] PRIMARY KEY CLUSTERED ([AssetTypeCode])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [ref].[AssetType_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'ref', @level1type = N'TABLE', @level1name = N'AssetType';
GO
