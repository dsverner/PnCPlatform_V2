-- SCHEMA-DESIGN §13.3 (175). Class AppendOnly, EventData filegroup. Shape only.
CREATE TABLE [event].[PhasorBlock] (
    [PhasorBlockId]     BIGINT IDENTITY(1,1) NOT NULL,
    [StreamId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_PhasorBlock_Stream] REFERENCES [event].[PmuStream] ([StreamId]),
    [BlockStartAt]      DATETIMEOFFSET(7) NOT NULL,
    [BlockEndAt]        DATETIMEOFFSET(7) NOT NULL,
    [Encoding]          NVARCHAR(40)      NOT NULL,
    [Data]              VARBINARY(MAX)    NOT NULL,
    CONSTRAINT [PK_PhasorBlock] PRIMARY KEY CLUSTERED ([PhasorBlockId]) ON [EventData],
    CONSTRAINT [CK_PhasorBlock_Period] CHECK ([BlockEndAt] >= [BlockStartAt])
) ON [EventData];
GO
CREATE INDEX [IX_PhasorBlock_Stream] ON [event].[PhasorBlock] ([StreamId], [BlockStartAt]) ON [EventIndex];
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'event', @level1type = N'TABLE', @level1name = N'PhasorBlock';
GO
