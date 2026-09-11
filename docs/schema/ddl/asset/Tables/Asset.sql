-- SCHEMA-DESIGN §4.2 (89, 90). One table for every asset of the four classes; devices extend it
-- (device.Device shares the EntityId). Everything else about an asset is a CharacteristicValue row.
CREATE TABLE [asset].[Asset] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Asset_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Asset_Registry] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Asset_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Asset_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Asset_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Asset_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Asset_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Asset_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [AssetTypeCode]      NVARCHAR(40)     NOT NULL CONSTRAINT [FK_Asset_Type] REFERENCES [ref].[AssetType] ([AssetTypeCode]),
    [Name]               NVARCHAR(200)    NOT NULL,
    [VoltageClassCode]   NVARCHAR(20)     NULL     CONSTRAINT [FK_Asset_VoltageClass] REFERENCES [ref].[VoltageClass] ([VoltageClassCode]),
    [ManufacturerEntityId] UNIQUEIDENTIFIER NULL   CONSTRAINT [FK_Asset_Manufacturer] REFERENCES [party].[EntityRegistry] ([EntityId]),
    [ModelId]            UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Asset_Model] REFERENCES [ref].[Model] ([ModelId]),
    [Status]             NVARCHAR(20)     NOT NULL CONSTRAINT [CK_Asset_Status] CHECK ([Status] IN (N'Planned', N'InService', N'OutOfService', N'Retired')),
    [CommissionedAt]     DATETIMEOFFSET(7) NULL,
    [RetiredAt]          DATETIMEOFFSET(7) NULL,
    [Notes]              NVARCHAR(MAX)    NULL,
    CONSTRAINT [PK_Asset] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Asset_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [asset].[Asset_History]));
GO
CREATE INDEX [IX_Asset_Entity] ON [asset].[Asset] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'asset', @level1type = N'TABLE', @level1name = N'Asset';
GO
