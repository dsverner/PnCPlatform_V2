-- SCHEMA-DESIGN §6.4 (110). Parsed SCL logical node; ProtectionFunctionNodeEntityId maps it to the
-- commissioned function's position (vision §4.12).
CREATE TABLE [connection].[LogicalNode] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_LogicalNode_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LogicalNode_Registry] REFERENCES [connection].[LogicalNodeRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_LogicalNode_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LogicalNode_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LogicalNode_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_LogicalNode_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_LogicalNode_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_LogicalNode_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ConfigurationFileRevisionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_LogicalNode_Revision] REFERENCES [document].[ConfigurationFile] ([RevisionRowId]),
    [LogicalDeviceEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_LogicalNode_LogicalDevice] REFERENCES [connection].[LogicalDeviceRegistry] ([EntityId]),
    [LnClass]            NVARCHAR(10)     NOT NULL,
    [LnInst]             NVARCHAR(10)     NULL,
    [Prefix]             NVARCHAR(40)     NULL,
    [LnType]             NVARCHAR(100)    NULL,
    [ProtectionFunctionNodeEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_LogicalNode_ProtectionFunction] REFERENCES [location].[NodeRegistry] ([EntityId]),
    CONSTRAINT [PK_LogicalNode] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_LogicalNode_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [connection].[LogicalNode_History]));
GO
CREATE INDEX [IX_LogicalNode_Entity] ON [connection].[LogicalNode] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'connection', @level1type = N'TABLE', @level1name = N'LogicalNode';
GO
