-- SCHEMA-DESIGN §6.7 (113). Shape now, built in the SCADA phase; lifted from comms.ProtocolConfig.
CREATE TABLE [connection].[ProtocolEndpoint] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_ProtocolEndpoint_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProtocolEndpoint_Registry] REFERENCES [connection].[ProtocolEndpointRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_ProtocolEndpoint_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProtocolEndpoint_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProtocolEndpoint_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_ProtocolEndpoint_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ProtocolEndpoint_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ProtocolEndpoint_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [NetworkPortEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_ProtocolEndpoint_Port] REFERENCES [connection].[PortRegistry] ([EntityId]),
    [Protocol]           NVARCHAR(20)     NOT NULL CONSTRAINT [CK_ProtocolEndpoint_Protocol] CHECK ([Protocol] IN (N'Dnp3', N'Modbus', N'Iec104', N'Iec61850Mms')),
    [Role]               NVARCHAR(20)     NOT NULL CONSTRAINT [CK_ProtocolEndpoint_Role] CHECK ([Role] IN (N'Master', N'Outstation', N'Server', N'Client')),
    [Address]            NVARCHAR(50)     NULL,
    [RemoteEndpointEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_ProtocolEndpoint_Remote] REFERENCES [connection].[ProtocolEndpointRegistry] ([EntityId]),
    [ConfigDetail]       NVARCHAR(MAX)    NULL,
    CONSTRAINT [PK_ProtocolEndpoint] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_ProtocolEndpoint_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [connection].[ProtocolEndpoint_History]));
GO
CREATE INDEX [IX_ProtocolEndpoint_Entity] ON [connection].[ProtocolEndpoint] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'connection', @level1type = N'TABLE', @level1name = N'ProtocolEndpoint';
GO
