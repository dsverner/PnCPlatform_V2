-- SCHEMA-DESIGN §6.4 (110). Parsed SCL dataset; the publisher endpoint of a Goose/SampledValues connection.
CREATE TABLE [connection].[Dataset] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Dataset_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Dataset_Registry] REFERENCES [connection].[DatasetRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Dataset_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Dataset_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Dataset_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Dataset_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Dataset_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Dataset_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ConfigurationFileRevisionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Dataset_Revision] REFERENCES [document].[ConfigurationFile] ([RevisionRowId]),
    [LogicalDeviceEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Dataset_LogicalDevice] REFERENCES [connection].[LogicalDeviceRegistry] ([EntityId]),
    [DatasetName]        NVARCHAR(100)    NOT NULL,
    CONSTRAINT [PK_Dataset] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Dataset_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [connection].[Dataset_History]));
GO
CREATE INDEX [IX_Dataset_Entity] ON [connection].[Dataset] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'connection', @level1type = N'TABLE', @level1name = N'Dataset';
GO
