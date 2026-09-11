-- SCHEMA-DESIGN §6.5 (111). A service on a network port; lifted from the predecessor's hardware.PortService.
CREATE TABLE [connection].[PortService] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_PortService_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_PortService_Registry] REFERENCES [connection].[PortServiceRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_PortService_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_PortService_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_PortService_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_PortService_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_PortService_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_PortService_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [NetworkPortEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_PortService_Port] REFERENCES [connection].[PortRegistry] ([EntityId]),
    [Protocol]           NVARCHAR(40)     NOT NULL,
    [LogicalPort]        INT              NULL,
    [ServiceName]        NVARCHAR(100)    NULL,
    [Direction]          NVARCHAR(20)     NULL     CONSTRAINT [CK_PortService_Direction] CHECK ([Direction] IS NULL OR [Direction] IN (N'In', N'Out', N'Bidirectional')),
    [BusinessJustification] NVARCHAR(400) NULL,
    [IsInsideSecurityPerimeter] BIT       NOT NULL CONSTRAINT [DF_PortService_IsInsidePerimeter] DEFAULT 0,
    CONSTRAINT [PK_PortService] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_PortService_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_PortService_LogicalPort] CHECK ([LogicalPort] IS NULL OR [LogicalPort] BETWEEN 0 AND 65535)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [connection].[PortService_History]));
GO
CREATE INDEX [IX_PortService_Entity] ON [connection].[PortService] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'connection', @level1type = N'TABLE', @level1name = N'PortService';
GO
