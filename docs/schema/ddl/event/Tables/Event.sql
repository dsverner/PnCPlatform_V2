-- SCHEMA-DESIGN §13.3 (173). Class AppendOnly, on the EventData filegroup (§13.4, decision 177).
-- RawFileEntityId nullable: an event correlated from SER records may have no raw file (recorded).
-- IngestRunId references migration.Run (the design names no separate ingest-run table; recorded).
CREATE TABLE [event].[Event] (
    [EventId]                   UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Event_EventId] DEFAULT NEWSEQUENTIALID(),
    [OccurredAt]                DATETIMEOFFSET(7) NOT NULL,
    [TimeSourceQuality]         TINYINT           NOT NULL CONSTRAINT [CK_Event_TimeSourceQuality] CHECK ([TimeSourceQuality] BETWEEN 0 AND 4),
    [SourceDeviceEntityId]      UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Event_SourceDevice] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [SourceKind]                NVARCHAR(40)      NOT NULL CONSTRAINT [CK_Event_SourceKind] CHECK ([SourceKind] IN (N'Dfr', N'RelayEventReport', N'Pmu', N'Ser')),
    [Format]                    NVARCHAR(40)      NOT NULL,
    [SampleRateHz]              DECIMAL(18,4)     NULL,
    [DurationMs]                INT               NULL,
    [NominalFrequencyHz]        DECIMAL(18,4)     NULL,
    [TriggerDescription]        NVARCHAR(400)     NULL,
    [ProtectionOperationEntityId] UNIQUEIDENTIFIER NULL    CONSTRAINT [FK_Event_ProtectionOperation] REFERENCES [scheme].[ProtectionOperationRegistry] ([EntityId]),
    [RawFileEntityId]           UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Event_RawFile] REFERENCES [document].[FileRegistry] ([EntityId]),
    [IngestedAt]                DATETIMEOFFSET(7) NOT NULL,
    [IngestRunId]               UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Event_IngestRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_Event] PRIMARY KEY CLUSTERED ([EventId]) ON [EventData]
) ON [EventData];
GO
CREATE INDEX [IX_Event_Device] ON [event].[Event] ([SourceDeviceEntityId], [OccurredAt]) ON [EventIndex];
GO
CREATE INDEX [IX_Event_OccurredAt] ON [event].[Event] ([OccurredAt]) ON [EventIndex];
GO
CREATE INDEX [IX_Event_Operation] ON [event].[Event] ([ProtectionOperationEntityId]) WHERE [ProtectionOperationEntityId] IS NOT NULL ON [EventIndex];
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'event', @level1type = N'TABLE', @level1name = N'Event';
GO
