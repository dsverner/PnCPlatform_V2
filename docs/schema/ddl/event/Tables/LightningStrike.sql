-- PLATFORM-ARCHITECTURE §5.2 (217); SCHEMA-DESIGN §13.3 (236). Class AppendOnly, EventData filegroup. The
-- OT landing for the lightning satellite feed: one row per strike the feed puller landed, keyed by the
-- satellite's own strike id (idempotent landing: a second pull of the same strike is refused by the unique
-- key, never duplicated). FeedRunId is a migration.Run row with SourceSystem = the feed name — feed runs
-- reuse the migration run and provenance shape (PLATFORM-ARCHITECTURE §5.1, decision 216).
-- Correlation to protection operations is the catalogue fact operation.lightning_nearby[km, minutes]
-- (compliance.fFactRead): a spatial query over the index below — set-based in SQL Server by design; a native
-- correlation module is the fallback earned only by a measurement on QA (vision §7.3).
CREATE TABLE [event].[LightningStrike] (
    [StrikeId]            BIGINT IDENTITY(1,1) NOT NULL,
    [SourceSystem]        NVARCHAR(50)      NOT NULL,
    [SourceStrikeId]      NVARCHAR(100)     NOT NULL,
    [OccurredAt]          DATETIMEOFFSET(7) NOT NULL,
    [TimeSourceQuality]   TINYINT           NOT NULL CONSTRAINT [CK_LightningStrike_TimeSourceQuality] CHECK ([TimeSourceQuality] BETWEEN 0 AND 4),
    [Location]            GEOGRAPHY         NOT NULL,
    [AmplitudeKa]         DECIMAL(10,3)     NULL,
    [StationCount]        INT               NULL,
    [FeedRunId]           UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LightningStrike_FeedRun] REFERENCES [migration].[Run] ([RunId]),
    [SourceHash]          BINARY(32)        NULL,
    CONSTRAINT [PK_LightningStrike] PRIMARY KEY CLUSTERED ([StrikeId]) ON [EventData],
    CONSTRAINT [UQ_LightningStrike_Source] UNIQUE NONCLUSTERED ([SourceSystem], [SourceStrikeId]) ON [EventData]
) ON [EventData];
GO
CREATE INDEX [IX_LightningStrike_OccurredAt] ON [event].[LightningStrike] ([OccurredAt]) ON [EventData];
GO
CREATE SPATIAL INDEX [SX_LightningStrike_Location] ON [event].[LightningStrike] ([Location]) ON [EventData];
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'event', @level1type = N'TABLE', @level1name = N'LightningStrike';
GO
