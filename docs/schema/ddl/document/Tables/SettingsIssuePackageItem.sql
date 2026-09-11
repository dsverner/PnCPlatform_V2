-- SCHEMA-DESIGN §8.4 (128). An item of a settings-issue package revision. Approval cascade is PROCEDURES.md #15.
CREATE TABLE [document].[SettingsIssuePackageItem] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_SettingsIssuePackageItem_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SettingsIssuePackageItem_Registry] REFERENCES [document].[SettingsIssuePackageItemRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_SettingsIssuePackageItem_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SettingsIssuePackageItem_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SettingsIssuePackageItem_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_SettingsIssuePackageItem_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_SettingsIssuePackageItem_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_SettingsIssuePackageItem_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [PackageRevisionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_SettingsIssuePackageItem_Package] REFERENCES [document].[Revision] ([RowId]),
    [ConfigurationFileRevisionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_SettingsIssuePackageItem_File] REFERENCES [document].[ConfigurationFile] ([RevisionRowId]),
    [Sequence]           INT              NOT NULL,
    CONSTRAINT [PK_SettingsIssuePackageItem] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_SettingsIssuePackageItem_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [document].[SettingsIssuePackageItem_History]));
GO
CREATE INDEX [IX_SettingsIssuePackageItem_Entity] ON [document].[SettingsIssuePackageItem] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_SettingsIssuePackageItem] ON [document].[SettingsIssuePackageItem] ([PackageRevisionRowId], [ConfigurationFileRevisionRowId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'document', @level1type = N'TABLE', @level1name = N'SettingsIssuePackageItem';
GO
