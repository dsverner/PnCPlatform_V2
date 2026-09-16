-- SCHEMA-DESIGN §8.5 (129). A parsed setting value of a configuration-file revision; the working
-- representation (vision §4.4). Typed value columns as §2.4.
CREATE TABLE [document].[ParsedSetting] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_ParsedSetting_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ParsedSetting_Registry] REFERENCES [document].[ParsedSettingRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_ParsedSetting_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ParsedSetting_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ParsedSetting_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_ParsedSetting_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ParsedSetting_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ParsedSetting_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ConfigurationFileRevisionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_ParsedSetting_File] REFERENCES [document].[ConfigurationFile] ([RevisionRowId]),
    [SettingDefinitionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_ParsedSetting_Definition] REFERENCES [config].[SettingDefinition] ([RowId]),
    [GroupNumber]        TINYINT          NULL,
    [TextValue]          NVARCHAR(400)    NULL,
    [IntegerValue]       BIGINT           NULL,
    [DecimalValue]       DECIMAL(28,10)   NULL,
    [BooleanValue]       BIT              NULL,
    [DateTimeValue]      DATETIMEOFFSET(7) NULL,
    [ReferenceEntityId]  UNIQUEIDENTIFIER NULL,
    [RangeCheck]         NVARCHAR(20)     NOT NULL CONSTRAINT [DF_ParsedSetting_RangeCheck] DEFAULT N'NotChecked' CONSTRAINT [CK_ParsedSetting_RangeCheck] CHECK ([RangeCheck] IN (N'Ok', N'OutOfRange', N'NotChecked')),
    [RangeCheckNote]     NVARCHAR(400)    NULL,
    -- #168 (2026-09-16): the value text exactly as filed or entered (13.90, 12 CYCLES, F4 A2 00); the typed column is the
    -- reading of it; the writer prints RawValue, so a platform-written file re-parses to the same bytes
    [RawValue]           NVARCHAR(400)    NULL,
    CONSTRAINT [PK_ParsedSetting] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_ParsedSetting_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_ParsedSetting_OneValue] CHECK (
        (CASE WHEN [TextValue] IS NULL THEN 0 ELSE 1 END) + (CASE WHEN [IntegerValue] IS NULL THEN 0 ELSE 1 END)
      + (CASE WHEN [DecimalValue] IS NULL THEN 0 ELSE 1 END) + (CASE WHEN [BooleanValue] IS NULL THEN 0 ELSE 1 END)
      + (CASE WHEN [DateTimeValue] IS NULL THEN 0 ELSE 1 END) + (CASE WHEN [ReferenceEntityId] IS NULL THEN 0 ELSE 1 END) = 1)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [document].[ParsedSetting_History]));
GO
CREATE INDEX [IX_ParsedSetting_Entity] ON [document].[ParsedSetting] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_ParsedSetting_Current] ON [document].[ParsedSetting] ([ConfigurationFileRevisionRowId], [SettingDefinitionRowId], [GroupNumber]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'document', @level1type = N'TABLE', @level1name = N'ParsedSetting';
GO
