-- SCHEMA-DESIGN §5.4 (99). Class AppendOnly. Current lifecycle state is derived from the latest event.
-- Installed / Removed events are written by the placement procedure (PROCEDURES.md #6).
-- WorkRequestEntityId FK → work.WorkRequestRegistry (step 9); RecordEntityId FK → record.RecordRegistry (step 10).
CREATE TABLE [device].[LifecycleEvent] (
    [LifecycleEventId]   BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_LifecycleEvent] PRIMARY KEY CLUSTERED,
    [DeviceEntityId]     UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_LifecycleEvent_Device] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [EventKind]          NVARCHAR(20)     NOT NULL CONSTRAINT [CK_LifecycleEvent_Kind] CHECK ([EventKind] IN (N'Received', N'BenchTested', N'Installed', N'Removed', N'SentForRepair', N'Returned', N'Retired', N'Disposed', N'Lost')),
    [OccurredAt]         DATETIMEOFFSET(7) NOT NULL,
    [TimeSourceQuality]  TINYINT          NOT NULL CONSTRAINT [CK_LifecycleEvent_TimeSourceQuality] CHECK ([TimeSourceQuality] BETWEEN 0 AND 4),
    [ActorId]            UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_LifecycleEvent_Actor] REFERENCES [personnel].[Actor] ([ActorId]),
    [NodeEntityId]       UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_LifecycleEvent_Node] REFERENCES [location].[NodeRegistry] ([EntityId]),
    [CustodyLocationEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_LifecycleEvent_Custody] REFERENCES [location].[CustodyLocationRegistry] ([EntityId]),
    [WorkRequestEntityId] UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_LifecycleEvent_WorkRequest] REFERENCES [work].[WorkRequestRegistry] ([EntityId]),
    [RecordEntityId]     UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_LifecycleEvent_Record] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [Notes]              NVARCHAR(MAX)    NULL,
    CONSTRAINT [CK_LifecycleEvent_OneLocation] CHECK (([NodeEntityId] IS NOT NULL AND [CustodyLocationEntityId] IS NULL) OR ([NodeEntityId] IS NULL AND [CustodyLocationEntityId] IS NOT NULL))
);
GO
CREATE INDEX [IX_LifecycleEvent_Device] ON [device].[LifecycleEvent] ([DeviceEntityId], [OccurredAt]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'device', @level1type = N'TABLE', @level1name = N'LifecycleEvent';
GO
