-- Registry of work.RequestTrack identities (SCHEMA-DESIGN §0.3, decision 67): one row per thing, for life.
-- Foreign keys that mean "the thing" reference this table; "the fact version" references RowId.
CREATE TABLE [work].[RequestTrackRegistry] (
    [EntityId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [PK_RequestTrackRegistry] PRIMARY KEY CLUSTERED,
    [CreatedAt] DATETIMEOFFSET(7) NOT NULL CONSTRAINT [DF_RequestTrackRegistry_CreatedAt] DEFAULT SYSDATETIMEOFFSET()
);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Registry',
    @level0type = N'SCHEMA', @level0name = N'work', @level1type = N'TABLE', @level1name = N'RequestTrackRegistry';
GO
