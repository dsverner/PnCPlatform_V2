-- SCHEMA-DESIGN §4.8 (96). Lifted from the predecessor's protection.DeviceType; lifecycle status added
-- (decision 49). Rows come from migration (51 models).
CREATE TABLE [ref].[Model] (
    [ModelId]           UNIQUEIDENTIFIER  NOT NULL,
    [ManufacturerId]    UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Model_Manufacturer] REFERENCES [ref].[Manufacturer] ([ManufacturerId]),
    [ModelCode]         NVARCHAR(100)     NOT NULL,
    [ModelName]         NVARCHAR(200)     NOT NULL,
    [AssetTypeCode]     NVARCHAR(40)      NOT NULL CONSTRAINT [FK_Model_AssetType] REFERENCES [ref].[AssetType] ([AssetTypeCode]),
    [DeviceCategory]    NVARCHAR(40)      NULL,
    [FirmwareFamily]    NVARCHAR(60)      NULL,
    [MaxSettingGroups]  TINYINT           NULL,
    [VendorSoftware]    NVARCHAR(100)     NULL,
    [ProjectFileExtension] NVARCHAR(20)   NULL,
    [Technology]        NVARCHAR(20)      NOT NULL CONSTRAINT [CK_Model_Technology] CHECK ([Technology] IN (N'Electromechanical', N'Static', N'Microprocessor', N'IEC61850')),
    [VendorLifecycleStatus] NVARCHAR(20)  NULL CONSTRAINT [CK_Model_LifecycleStatus] CHECK ([VendorLifecycleStatus] IS NULL OR [VendorLifecycleStatus] IN (N'Active', N'MatureSupport', N'EndOfSale', N'EndOfSupport', N'Obsolete')),
    [StatusAsOf]        DATETIMEOFFSET(7) NULL,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Model_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Model_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_Model_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Model_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_Model] PRIMARY KEY CLUSTERED ([ModelId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [ref].[Model_History]));
GO
CREATE UNIQUE INDEX [UX_Model_Code] ON [ref].[Model] ([ManufacturerId], [ModelCode]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'ref', @level1type = N'TABLE', @level1name = N'Model';
GO
