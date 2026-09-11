-- SCHEMA-DESIGN §6.4 (110). Parsed SCL ExtRef (subscription); ConnectionEntityId is the promoted
-- connection.Connection row (PROCEDURES.md #10).
CREATE TABLE [connection].[ExtRef] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_ExtRef_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ExtRef_Registry] REFERENCES [connection].[ExtRefRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_ExtRef_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ExtRef_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ExtRef_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_ExtRef_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ExtRef_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ExtRef_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ConfigurationFileRevisionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_ExtRef_Revision] REFERENCES [document].[ConfigurationFile] ([RevisionRowId]),
    [IedEntityId]        UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_ExtRef_Ied] REFERENCES [connection].[IedRegistry] ([EntityId]),
    [IntAddr]            NVARCHAR(200)    NULL,
    [LdInst]             NVARCHAR(100)    NULL,
    [LnClass]            NVARCHAR(10)     NULL,
    [LnInst]             NVARCHAR(10)     NULL,
    [DoName]             NVARCHAR(100)    NULL,
    [DaName]             NVARCHAR(100)    NULL,
    [PublisherIedName]   NVARCHAR(100)    NULL,
    [CbName]             NVARCHAR(100)    NULL,
    [DatasetRef]         NVARCHAR(200)    NULL,
    [ConnectionEntityId] UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_ExtRef_Connection] REFERENCES [connection].[ConnectionRegistry] ([EntityId]),
    CONSTRAINT [PK_ExtRef] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_ExtRef_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [connection].[ExtRef_History]));
GO
CREATE INDEX [IX_ExtRef_Entity] ON [connection].[ExtRef] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'connection', @level1type = N'TABLE', @level1name = N'ExtRef';
GO
