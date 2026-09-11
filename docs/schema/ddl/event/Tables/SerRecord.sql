-- SCHEMA-DESIGN §13.3 (174). Class AppendOnly, EventData filegroup. Sequence-of-events record, lifted
-- from the predecessor; correlation to an operation is through scheme.ProtectionOperationSnapshot.
CREATE TABLE [event].[SerRecord] (
    [SerRecordId]           BIGINT IDENTITY(1,1) NOT NULL,
    [SourceDeviceEntityId]  UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SerRecord_SourceDevice] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [OccurredAt]            DATETIMEOFFSET(7) NOT NULL,
    [TimeSourceQuality]     TINYINT           NOT NULL CONSTRAINT [CK_SerRecord_TimeSourceQuality] CHECK ([TimeSourceQuality] BETWEEN 0 AND 4),
    [PointName]             NVARCHAR(200)     NOT NULL,
    [PointDescription]      NVARCHAR(400)     NULL,
    [PreviousState]         NVARCHAR(40)      NULL,
    [NewState]              NVARCHAR(40)      NULL,
    [SourceFormat]          NVARCHAR(40)      NULL,
    [SourceFileEntityId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_SerRecord_SourceFile] REFERENCES [document].[FileRegistry] ([EntityId]),
    CONSTRAINT [PK_SerRecord] PRIMARY KEY CLUSTERED ([SerRecordId]) ON [EventData]
) ON [EventData];
GO
CREATE INDEX [IX_SerRecord_Device] ON [event].[SerRecord] ([SourceDeviceEntityId], [OccurredAt]) ON [EventIndex];
GO
CREATE INDEX [IX_SerRecord_OccurredAt] ON [event].[SerRecord] ([OccurredAt]) ON [EventIndex];
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'event', @level1type = N'TABLE', @level1name = N'SerRecord';
GO
