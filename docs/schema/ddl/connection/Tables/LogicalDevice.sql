-- SCHEMA-DESIGN §6.4 (110). Parsed SCL logical device.
CREATE TABLE [connection].[LogicalDevice] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_LogicalDevice_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LogicalDevice_Registry] REFERENCES [connection].[LogicalDeviceRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_LogicalDevice_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LogicalDevice_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LogicalDevice_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_LogicalDevice_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_LogicalDevice_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_LogicalDevice_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ConfigurationFileRevisionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_LogicalDevice_Revision] REFERENCES [document].[ConfigurationFile] ([RevisionRowId]),
    [IedEntityId]        UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_LogicalDevice_Ied] REFERENCES [connection].[IedRegistry] ([EntityId]),
    [Inst]               NVARCHAR(100)    NOT NULL,
    [LdName]             NVARCHAR(100)    NULL,
    CONSTRAINT [PK_LogicalDevice] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_LogicalDevice_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [connection].[LogicalDevice_History]));
GO
CREATE INDEX [IX_LogicalDevice_Entity] ON [connection].[LogicalDevice] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'connection', @level1type = N'TABLE', @level1name = N'LogicalDevice';
GO
