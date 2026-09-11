-- SCHEMA-DESIGN §6.4 (110). Parsed SCL control block (GOOSE, sampled values, report).
CREATE TABLE [connection].[ControlBlock] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_ControlBlock_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ControlBlock_Registry] REFERENCES [connection].[ControlBlockRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_ControlBlock_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ControlBlock_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ControlBlock_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_ControlBlock_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ControlBlock_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ControlBlock_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ConfigurationFileRevisionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_ControlBlock_Revision] REFERENCES [document].[ConfigurationFile] ([RevisionRowId]),
    [LogicalDeviceEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_ControlBlock_LogicalDevice] REFERENCES [connection].[LogicalDeviceRegistry] ([EntityId]),
    [ControlBlockKind]   NVARCHAR(20)     NOT NULL CONSTRAINT [CK_ControlBlock_Kind] CHECK ([ControlBlockKind] IN (N'Goose', N'SampledValues', N'Report')),
    [CbName]             NVARCHAR(100)    NOT NULL,
    [AppId]              NVARCHAR(20)     NULL,
    [ConfRev]            BIGINT           NULL,
    [DatasetEntityId]    UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_ControlBlock_Dataset] REFERENCES [connection].[DatasetRegistry] ([EntityId]),
    [MulticastMac]       NVARCHAR(17)     NULL,
    [VlanId]             INT              NULL,
    [VlanPriority]       TINYINT          NULL,
    CONSTRAINT [PK_ControlBlock] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_ControlBlock_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [connection].[ControlBlock_History]));
GO
CREATE INDEX [IX_ControlBlock_Entity] ON [connection].[ControlBlock] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'connection', @level1type = N'TABLE', @level1name = N'ControlBlock';
GO
