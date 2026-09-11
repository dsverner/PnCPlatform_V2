-- SCHEMA-DESIGN §6.1 (107). The electrical or communications ports an asset presents; a port terminates at
-- a stud (a location node of type Stud). Kinds Ethernet/Serial/Fiber are extended by connection.NetworkPort.
CREATE TABLE [connection].[Port] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Port_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Port_Registry] REFERENCES [connection].[PortRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Port_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Port_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Port_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Port_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Port_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Port_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [AssetEntityId]      UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Port_Asset] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [PortDesignator]     NVARCHAR(50)     NOT NULL,
    [PortKindCode]       NVARCHAR(40)     NOT NULL CONSTRAINT [FK_Port_Kind] REFERENCES [ref].[PortKind] ([PortKindCode]),
    [Direction]          NVARCHAR(20)     NOT NULL CONSTRAINT [CK_Port_Direction] CHECK ([Direction] IN (N'In', N'Out', N'Bidirectional')),
    [Phase]              NVARCHAR(10)     NULL     CONSTRAINT [CK_Port_Phase] CHECK ([Phase] IS NULL OR [Phase] IN (N'A', N'B', N'C', N'N', N'Ground')),
    [ElectricalGroupCode] NVARCHAR(40)    NULL,
    [TerminatesAtStudEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Port_Stud] REFERENCES [location].[NodeRegistry] ([EntityId]),
    [Notes]              NVARCHAR(MAX)    NULL,
    CONSTRAINT [PK_Port] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Port_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [connection].[Port_History]));
GO
CREATE INDEX [IX_Port_Entity] ON [connection].[Port] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_Port_Designator] ON [connection].[Port] ([AssetEntityId], [PortDesignator]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'connection', @level1type = N'TABLE', @level1name = N'Port';
GO
