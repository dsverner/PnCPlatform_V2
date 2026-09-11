-- SCHEMA-DESIGN §6.4 (110). The flat data-attribute map (the predecessor's 277,743 rows): parsed content
-- only, never referenced by rules.
CREATE TABLE [connection].[DataAttribute] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_DataAttribute_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_DataAttribute_Registry] REFERENCES [connection].[DataAttributeRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_DataAttribute_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_DataAttribute_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_DataAttribute_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_DataAttribute_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_DataAttribute_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_DataAttribute_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ConfigurationFileRevisionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_DataAttribute_Revision] REFERENCES [document].[ConfigurationFile] ([RevisionRowId]),
    [LogicalNodeEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_DataAttribute_LogicalNode] REFERENCES [connection].[LogicalNodeRegistry] ([EntityId]),
    [DoName]             NVARCHAR(100)    NOT NULL,
    [DaName]             NVARCHAR(100)    NULL,
    [Fc]                 NVARCHAR(10)     NULL,
    [DataSource]         NVARCHAR(200)    NULL,
    CONSTRAINT [PK_DataAttribute] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_DataAttribute_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [connection].[DataAttribute_History]));
GO
CREATE INDEX [IX_DataAttribute_Entity] ON [connection].[DataAttribute] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'connection', @level1type = N'TABLE', @level1name = N'DataAttribute';
GO
