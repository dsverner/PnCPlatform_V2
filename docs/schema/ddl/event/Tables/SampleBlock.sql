-- SCHEMA-DESIGN §13.3 (173). Class AppendOnly, EventData filegroup. Compressed sample blocks of a channel.
CREATE TABLE [event].[SampleBlock] (
    [ChannelId]         BIGINT            NOT NULL CONSTRAINT [FK_SampleBlock_Channel] REFERENCES [event].[Channel] ([ChannelId]),
    [BlockSequence]     INT               NOT NULL,
    [SampleCount]       INT               NOT NULL,
    [Encoding]          NVARCHAR(40)      NOT NULL,
    [Samples]           VARBINARY(MAX)    NOT NULL,
    CONSTRAINT [PK_SampleBlock] PRIMARY KEY CLUSTERED ([ChannelId], [BlockSequence]) ON [EventData]
) ON [EventData];
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'event', @level1type = N'TABLE', @level1name = N'SampleBlock';
GO
