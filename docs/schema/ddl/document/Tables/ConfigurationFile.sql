-- SCHEMA-DESIGN §8.3 (127). Revision subclass (class Subclass, keyed by the revision's RowId). The
-- in-service invariant (vision §4.4) is the filtered unique index UX_ConfigurationFile_InService; opening
-- a new in-service period closes the prior one in the procedure of PROCEDURES.md #14.
-- IsInServiceUnapproved needs Revision.Status (another table) → it is a column of the hand-written view
-- document.vConfigurationFileStatus, not a computed column here (STEPS.md).
-- DifferentialRecordEntityId FK → record.RecordRegistry added in step 10.
CREATE TABLE [document].[ConfigurationFile] (
    [RevisionRowId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ConfigurationFile_Parent] REFERENCES [document].[Revision] ([RowId]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ConfigurationFile_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ConfigurationFile_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_ConfigurationFile_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ConfigurationFile_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ConfigurationFile_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [DeviceEntityId]     UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_ConfigurationFile_Device] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [FileKind]           NVARCHAR(20)     NOT NULL CONSTRAINT [CK_ConfigurationFile_Kind] CHECK ([FileKind] IN (N'NativeSettings', N'Cid', N'Scd', N'Icd', N'Iid', N'Ssd', N'DfrConfig', N'PmuConfig', N'VendorProject')),
    [ModelId]            UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_ConfigurationFile_Model] REFERENCES [ref].[Model] ([ModelId]),
    [FirmwareVersionId]  UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_ConfigurationFile_Firmware] REFERENCES [ref].[FirmwareVersion] ([FirmwareVersionId]),
    [CaptureKind]        NVARCHAR(20)     NOT NULL CONSTRAINT [CK_ConfigurationFile_Capture] CHECK ([CaptureKind] IN (N'Designed', N'Generated', N'AsLeftReadback', N'AsFound')),
    [InServiceFrom]      DATETIMEOFFSET(7) NULL,
    [InServiceTo]        DATETIMEOFFSET(7) NULL,
    [InServiceFromQuality] TINYINT        NOT NULL CONSTRAINT [DF_ConfigurationFile_InServiceFromQuality] DEFAULT 0,
    [DifferentialRecordEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_ConfigurationFile_DifferentialRecord] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [ParseStatus]        NVARCHAR(20)     NULL,
    [ParseError]         NVARCHAR(MAX)    NULL,
    [SettingsGroupCount] TINYINT          NULL,
    CONSTRAINT [PK_ConfigurationFile] PRIMARY KEY CLUSTERED ([RevisionRowId]),
    CONSTRAINT [CK_ConfigurationFile_ScdDevice] CHECK ([DeviceEntityId] IS NOT NULL OR [FileKind] = N'Scd'),
    CONSTRAINT [CK_ConfigurationFile_InServicePeriod] CHECK ([InServiceTo] IS NULL OR ([InServiceFrom] IS NOT NULL AND [InServiceTo] > [InServiceFrom]))
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [document].[ConfigurationFile_History]));
GO
-- the in-service invariant: one NativeSettings file in service per device at an instant
CREATE UNIQUE INDEX [UX_ConfigurationFile_InService] ON [document].[ConfigurationFile] ([DeviceEntityId])
    WHERE [FileKind] = N'NativeSettings' AND [InServiceFrom] IS NOT NULL AND [InServiceTo] IS NULL AND [IsDeleted] = 0;
GO
CREATE INDEX [IX_ConfigurationFile_Device] ON [document].[ConfigurationFile] ([DeviceEntityId], [FileKind]) WHERE [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Subclass',
    @level0type = N'SCHEMA', @level0name = N'document', @level1type = N'TABLE', @level1name = N'ConfigurationFile';
GO
