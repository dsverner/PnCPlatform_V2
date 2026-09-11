-- SCHEMA-DESIGN §13.3 (173). Class AppendOnly, EventData filegroup. A recorded channel of an event.
CREATE TABLE [event].[Channel] (
    [ChannelId]             BIGINT IDENTITY(1,1) NOT NULL,
    [EventId]               UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Channel_Event] REFERENCES [event].[Event] ([EventId]),
    [ChannelKind]           NVARCHAR(20)      NOT NULL CONSTRAINT [CK_Channel_Kind] CHECK ([ChannelKind] IN (N'Analog', N'Digital')),
    [Name]                  NVARCHAR(200)     NOT NULL,
    [UnitCode]              NVARCHAR(20)      NULL     CONSTRAINT [FK_Channel_Unit] REFERENCES [ref].[Unit] ([UnitCode]),
    [Phase]                 NVARCHAR(10)      NULL,
    [CtRatio]               DECIMAL(18,4)     NULL,
    [PtRatio]               DECIMAL(18,4)     NULL,
    [PrimaryOrSecondary]    NVARCHAR(20)      NULL     CONSTRAINT [CK_Channel_PrimaryOrSecondary] CHECK ([PrimaryOrSecondary] IS NULL OR [PrimaryOrSecondary] IN (N'Primary', N'Secondary')),
    [SortOrder]             INT               NOT NULL CONSTRAINT [DF_Channel_SortOrder] DEFAULT 0,
    [SourcePortEntityId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Channel_SourcePort] REFERENCES [connection].[PortRegistry] ([EntityId]),
    CONSTRAINT [PK_Channel] PRIMARY KEY CLUSTERED ([ChannelId]) ON [EventData]
) ON [EventData];
GO
CREATE INDEX [IX_Channel_Event] ON [event].[Channel] ([EventId], [SortOrder]) ON [EventIndex];
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'event', @level1type = N'TABLE', @level1name = N'Channel';
GO
