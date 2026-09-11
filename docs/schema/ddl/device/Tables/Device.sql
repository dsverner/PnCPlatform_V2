-- SCHEMA-DESIGN §5.1 (98). Extension of asset.Asset for types with IsDevice = 1, sharing the EntityId.
-- CurrentFirmwareVersionId is derived from FirmwareHistory by procedure (PROCEDURES.md #8), never
-- edited directly. Serial number is an asset.AlternateKey of kind SerialNumber.
CREATE TABLE [device].[Device] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Device_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Device_Registry] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Device_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Device_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Device_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Device_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Device_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Device_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [PartNumber]         NVARCHAR(100)    NULL,
    [HardwareRevision]   NVARCHAR(50)     NULL,
    [ManufacturedAt]     DATE             NULL,
    [CurrentFirmwareVersionId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Device_CurrentFirmware] REFERENCES [ref].[FirmwareVersion] ([FirmwareVersionId]),
    [Notes]              NVARCHAR(MAX)    NULL,
    CONSTRAINT [PK_Device] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Device_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [device].[Device_History]));
GO
CREATE INDEX [IX_Device_Entity] ON [device].[Device] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'device', @level1type = N'TABLE', @level1name = N'Device';
GO
