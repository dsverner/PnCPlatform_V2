-- SCHEMA-DESIGN §6.5 (111). Extension of connection.Port for kinds Ethernet, Serial, Fiber, sharing the
-- port's EntityId (no own registry). Column lengths are this project's defaults (design gives none).
CREATE TABLE [connection].[NetworkPort] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_NetworkPort_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_NetworkPort_Registry] REFERENCES [connection].[PortRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_NetworkPort_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_NetworkPort_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_NetworkPort_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_NetworkPort_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_NetworkPort_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_NetworkPort_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [MacAddress]         NVARCHAR(17)     NULL,
    [IpAddress]          NVARCHAR(45)     NULL,
    [SubnetMask]         NVARCHAR(45)     NULL,
    [Gateway]            NVARCHAR(45)     NULL,
    [VlanId]             INT              NULL     CONSTRAINT [FK_NetworkPort_Vlan] REFERENCES [ref].[Vlan] ([VlanId]),
    [Speed]              NVARCHAR(40)     NULL,
    [IsEnabled]          BIT              NOT NULL CONSTRAINT [DF_NetworkPort_IsEnabled] DEFAULT 1,
    CONSTRAINT [PK_NetworkPort] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_NetworkPort_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [connection].[NetworkPort_History]));
GO
CREATE INDEX [IX_NetworkPort_Entity] ON [connection].[NetworkPort] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'connection', @level1type = N'TABLE', @level1name = N'NetworkPort';
GO
