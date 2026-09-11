-- SCHEMA-DESIGN §6.5 (111). Device membership of a perimeter; lifted from comms.ESPDevice.
CREATE TABLE [connection].[SecurityPerimeterMember] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_SecurityPerimeterMember_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SecurityPerimeterMember_Registry] REFERENCES [connection].[SecurityPerimeterMemberRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_SecurityPerimeterMember_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SecurityPerimeterMember_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SecurityPerimeterMember_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_SecurityPerimeterMember_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_SecurityPerimeterMember_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_SecurityPerimeterMember_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [PerimeterEntityId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_SecurityPerimeterMember_Perimeter] REFERENCES [connection].[SecurityPerimeterRegistry] ([EntityId]),
    [DeviceEntityId]     UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_SecurityPerimeterMember_Device] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [Role]               NVARCHAR(20)     NOT NULL CONSTRAINT [CK_SecurityPerimeterMember_Role] CHECK ([Role] IN (N'Inside', N'AccessPoint')),
    CONSTRAINT [PK_SecurityPerimeterMember] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_SecurityPerimeterMember_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [connection].[SecurityPerimeterMember_History]));
GO
CREATE INDEX [IX_SecurityPerimeterMember_Entity] ON [connection].[SecurityPerimeterMember] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_SecurityPerimeterMember] ON [connection].[SecurityPerimeterMember] ([PerimeterEntityId], [DeviceEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'connection', @level1type = N'TABLE', @level1name = N'SecurityPerimeterMember';
GO
