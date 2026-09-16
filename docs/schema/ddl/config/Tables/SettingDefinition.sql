-- SCHEMA-DESIGN §8.5 (129). Class Versioned. A setting as the vendor names it, under the
-- Transform.SettingsParse version for a model × firmware. IsCatalogueFact publishes
-- device.settings.<code>.
CREATE TABLE [config].[SettingDefinition] (
    [RowSeq]                    BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]                     UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_SettingDefinition_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]                  UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SettingDefinition_Registry] REFERENCES [config].[SettingDefinitionRegistry] ([EntityId]),
    [SysStart]                  DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]                    DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]                 UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SettingDefinition_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]                 DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]                UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SettingDefinition_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]                DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]                 BIT               NOT NULL CONSTRAINT [DF_SettingDefinition_IsDeleted] DEFAULT 0,
    [DeletedBy]                 UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_SettingDefinition_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]                 DATETIMEOFFSET(7) NULL,
    [MigrationRunId]            UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_SettingDefinition_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [DefinitionVersionRowId]    UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SettingDefinition_Version] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [SettingCode]               NVARCHAR(100)     NOT NULL,
    [Name]                      NVARCHAR(200)     NOT NULL,
    [Category]                  NVARCHAR(100)     NULL,
    [Description]               NVARCHAR(MAX)     NULL,
    [DataType]                  NVARCHAR(20)      NOT NULL CONSTRAINT [CK_SettingDefinition_DataType] CHECK ([DataType] IN (N'Text', N'Integer', N'Decimal', N'Boolean', N'DateTime', N'Reference', N'Enumeration')),
    [UnitCode]                  NVARCHAR(20)      NULL     CONSTRAINT [FK_SettingDefinition_Unit] REFERENCES [ref].[Unit] ([UnitCode]),
    [Base]                      NVARCHAR(20)      NULL     CONSTRAINT [CK_SettingDefinition_Base] CHECK ([Base] IS NULL OR [Base] IN (N'Primary', N'Secondary', N'PerUnit')),
    [MinValue]                  DECIMAL(28,10)    NULL,
    [MaxValue]                  DECIMAL(28,10)    NULL,
    [DefaultValue]              NVARCHAR(400)     NULL,
    [EnumerationDefinitionRowId] UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_SettingDefinition_Enumeration] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [IsGroupSpecific]           BIT               NOT NULL CONSTRAINT [DF_SettingDefinition_IsGroupSpecific] DEFAULT 0,
    [AnsiCode]                  NVARCHAR(10)      NULL     CONSTRAINT [FK_SettingDefinition_Ansi] REFERENCES [ref].[AnsiFunction] ([AnsiCode]),
    [IsCatalogueFact]           BIT               NOT NULL CONSTRAINT [DF_SettingDefinition_IsCatalogueFact] DEFAULT 0,
    -- #168 (2026-09-16): the writer's order (the vendor's SET order), the legacy spellings the parser accepts, and how the
    -- writer prints the value (decimal:2 | integer | text | mask3) — a template reads and writes the same file
    [DisplayOrder]              INT               NOT NULL CONSTRAINT [DF_SettingDefinition_DisplayOrder] DEFAULT 0,
    [Aliases]                   NVARCHAR(400)     NULL,
    [Format]                    NVARCHAR(40)      NULL,
    CONSTRAINT [PK_SettingDefinition] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_SettingDefinition_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_SettingDefinition_Range] CHECK ([MinValue] IS NULL OR [MaxValue] IS NULL OR [MaxValue] >= [MinValue])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [config].[SettingDefinition_History]));
GO
CREATE INDEX [IX_SettingDefinition_Entity] ON [config].[SettingDefinition] ([EntityId]);
GO
CREATE UNIQUE INDEX [UX_SettingDefinition_Code] ON [config].[SettingDefinition] ([DefinitionVersionRowId], [SettingCode]) WHERE [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'config', @level1type = N'TABLE', @level1name = N'SettingDefinition';
GO
