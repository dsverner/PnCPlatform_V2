-- SCHEMA-DESIGN §6.4 (110). Parsed SCL dataset member (FCDA).
CREATE TABLE [connection].[DatasetMember] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_DatasetMember_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_DatasetMember_Registry] REFERENCES [connection].[DatasetMemberRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_DatasetMember_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_DatasetMember_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_DatasetMember_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_DatasetMember_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_DatasetMember_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_DatasetMember_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ConfigurationFileRevisionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_DatasetMember_Revision] REFERENCES [document].[ConfigurationFile] ([RevisionRowId]),
    [DatasetEntityId]    UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_DatasetMember_Dataset] REFERENCES [connection].[DatasetRegistry] ([EntityId]),
    [LdInst]             NVARCHAR(100)    NULL,
    [LnClass]            NVARCHAR(10)     NULL,
    [LnInst]             NVARCHAR(10)     NULL,
    [DoName]             NVARCHAR(100)    NULL,
    [DaName]             NVARCHAR(100)    NULL,
    [Fc]                 NVARCHAR(10)     NULL,
    CONSTRAINT [PK_DatasetMember] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_DatasetMember_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [connection].[DatasetMember_History]));
GO
CREATE INDEX [IX_DatasetMember_Entity] ON [connection].[DatasetMember] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'connection', @level1type = N'TABLE', @level1name = N'DatasetMember';
GO
