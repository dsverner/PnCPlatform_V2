-- SCHEMA-DESIGN §9.6 (140). Class AppendOnly; the predecessor's DeliveryLog.
CREATE TABLE [work].[NotificationDelivery] (
    [NotificationDeliveryId] BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_NotificationDelivery] PRIMARY KEY CLUSTERED,
    [NotificationEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_NotificationDelivery_Notification] REFERENCES [work].[NotificationRegistry] ([EntityId]),
    [Channel]            NVARCHAR(20)     NOT NULL CONSTRAINT [CK_NotificationDelivery_Channel] CHECK ([Channel] IN (N'InApp', N'Email')),
    [SentAt]             DATETIMEOFFSET(7) NOT NULL,
    [DeliveryStatus]     NVARCHAR(40)     NOT NULL
);
GO
CREATE INDEX [IX_NotificationDelivery_Notification] ON [work].[NotificationDelivery] ([NotificationEntityId], [SentAt]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'work', @level1type = N'TABLE', @level1name = N'NotificationDelivery';
GO
