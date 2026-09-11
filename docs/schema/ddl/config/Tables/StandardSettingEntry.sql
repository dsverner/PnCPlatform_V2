-- SCHEMA-DESIGN §8.6 (130). Class Versioned. One row of a CharacteristicSchema.StandardSettings
-- definition version: (SettingCode, ExpectedValue, Tolerance, Basis). The version is applied to a
-- protection application × model through config.DefinitionAppliesTo; comparing a parsed revision against
-- the resolved standard produces a SettingsVerification record (§8.6). Added for MIGRATION-PLAN.md Q9:
-- the predecessor's protection.SettingTemplateEntry (SettingCode, ExpectedValue, Category, Tolerance,
-- Notes) lands here instead of in the definition's Description.
-- Same shape as config.SettingDefinition (§8.5): versioned content of a definition version, own registry,
-- unique SettingCode within the version while live.
CREATE TABLE [config].[StandardSettingEntry] (
    [RowSeq]                    BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]                     UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_StandardSettingEntry_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]                  UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_StandardSettingEntry_Registry] REFERENCES [config].[StandardSettingEntryRegistry] ([EntityId]),
    [SysStart]                  DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]                    DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]                 UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_StandardSettingEntry_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]                 DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]                UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_StandardSettingEntry_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]                DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]                 BIT               NOT NULL CONSTRAINT [DF_StandardSettingEntry_IsDeleted] DEFAULT 0,
    [DeletedBy]                 UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_StandardSettingEntry_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]                 DATETIMEOFFSET(7) NULL,
    [MigrationRunId]            UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_StandardSettingEntry_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [DefinitionVersionRowId]    UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_StandardSettingEntry_Version] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [SettingCode]               NVARCHAR(100)     NOT NULL,
    [ExpectedValue]             NVARCHAR(400)     NOT NULL,
    [Tolerance]                 NVARCHAR(100)     NULL,
    [Basis]                     NVARCHAR(400)     NULL,
    [Category]                  NVARCHAR(100)     NULL,
    [DisplayOrder]              INT               NOT NULL CONSTRAINT [DF_StandardSettingEntry_DisplayOrder] DEFAULT 0,
    CONSTRAINT [PK_StandardSettingEntry] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_StandardSettingEntry_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [config].[StandardSettingEntry_History]));
GO
CREATE INDEX [IX_StandardSettingEntry_Entity] ON [config].[StandardSettingEntry] ([EntityId]);
GO
CREATE UNIQUE INDEX [UX_StandardSettingEntry_Code] ON [config].[StandardSettingEntry] ([DefinitionVersionRowId], [SettingCode]) WHERE [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'config', @level1type = N'TABLE', @level1name = N'StandardSettingEntry';
GO
