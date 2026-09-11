-- SCHEMA-DESIGN §13.3 (175). Class AppendOnly, EventData filegroup. Shape only.
CREATE TABLE [event].[PmuStream] (
    [StreamId]                      UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_PmuStream_StreamId] DEFAULT NEWSEQUENTIALID(),
    [PmuDeviceEntityId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_PmuStream_Device] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [ConfigurationFileRevisionRowId] UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_PmuStream_ConfigurationFile] REFERENCES [document].[ConfigurationFile] ([RevisionRowId]),
    [ReportingRateHz]               DECIMAL(18,4)     NULL,
    [StartedAt]                     DATETIMEOFFSET(7) NOT NULL,
    [EndedAt]                       DATETIMEOFFSET(7) NULL,
    CONSTRAINT [PK_PmuStream] PRIMARY KEY CLUSTERED ([StreamId]) ON [EventData]
) ON [EventData];
GO
CREATE INDEX [IX_PmuStream_Device] ON [event].[PmuStream] ([PmuDeviceEntityId], [StartedAt]) ON [EventIndex];
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'event', @level1type = N'TABLE', @level1name = N'PmuStream';
GO
