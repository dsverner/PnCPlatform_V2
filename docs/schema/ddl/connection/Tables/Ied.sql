-- SCHEMA-DESIGN §6.4 (110). Parsed SCL content, keyed to the configuration-file revision that produced it.
-- DeviceEntityId is matched by IED name → asset.AlternateKey of kind IedName; null until matched.
CREATE TABLE [connection].[Ied] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Ied_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Ied_Registry] REFERENCES [connection].[IedRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Ied_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Ied_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Ied_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Ied_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Ied_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Ied_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ConfigurationFileRevisionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Ied_Revision] REFERENCES [document].[ConfigurationFile] ([RevisionRowId]),
    [DeviceEntityId]     UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Ied_Device] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [IedName]            NVARCHAR(100)    NOT NULL,
    [ConfigVersion]      NVARCHAR(100)    NULL,
    [Manufacturer]       NVARCHAR(200)    NULL,
    [IedType]            NVARCHAR(100)    NULL,
    CONSTRAINT [PK_Ied] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Ied_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [connection].[Ied_History]));
GO
CREATE INDEX [IX_Ied_Entity] ON [connection].[Ied] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_Ied_Name] ON [connection].[Ied] ([ConfigurationFileRevisionRowId], [IedName]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'connection', @level1type = N'TABLE', @level1name = N'Ied';
GO
