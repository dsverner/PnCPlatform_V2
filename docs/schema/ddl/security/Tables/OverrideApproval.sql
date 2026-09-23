-- #232 (2026-09-23): a segregation override approved by the approver, from their own session (security.ApproveOverride) —
-- never a name typed by the person who wants the override. The owner, 2026-09-23: the approver must be someone who could do
-- the action themselves. Append-only events, never edited: 'Approved' (the approver's act: the subject, the action being
-- approved, the person it is for, why, until when), 'Withdrawn' (the same approver takes it back before use) and 'Used'
-- (security.CheckSegregation consumed it for one override — single use). An approval is live while it is unexpired and no
-- 'Withdrawn' or 'Used' event names it (RefersToOverrideApprovalId).
CREATE TABLE [security].[OverrideApproval] (
    [OverrideApprovalId]         BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_OverrideApproval] PRIMARY KEY CLUSTERED,
    [EventKind]                  NVARCHAR(20)     NOT NULL CONSTRAINT [CK_OverrideApproval_EventKind] CHECK ([EventKind] IN (N'Approved', N'Withdrawn', N'Used')),
    [RefersToOverrideApprovalId] BIGINT           NULL     CONSTRAINT [FK_OverrideApproval_RefersTo] REFERENCES [security].[OverrideApproval] ([OverrideApprovalId]),
    [SubjectKind]                NVARCHAR(40)     NOT NULL CONSTRAINT [FK_OverrideApproval_SubjectKind] REFERENCES [ref].[SubjectKind] ([SubjectKindCode]),
    [SubjectEntityId]            UNIQUEIDENTIFIER NOT NULL,
    [Action]                     NVARCHAR(100)    NOT NULL,
    [ForPersonEntityId]          UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_OverrideApproval_ForPerson] REFERENCES [personnel].[PersonRegistry] ([EntityId]),
    [Reason]                     NVARCHAR(400)    NULL,
    [ActorId]                    UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_OverrideApproval_Actor] REFERENCES [personnel].[Actor] ([ActorId]),
    [OccurredAt]                 DATETIMEOFFSET(7) NOT NULL,
    [ExpiresAt]                  DATETIMEOFFSET(7) NULL,
    [SegregationOverrideId]      BIGINT           NULL     CONSTRAINT [FK_OverrideApproval_Override] REFERENCES [security].[SegregationOverride] ([OverrideId]),
    [ActionLogId]                BIGINT           NOT NULL CONSTRAINT [FK_OverrideApproval_ActionLog] REFERENCES [audit].[ActionLog] ([ActionLogId]),
    CONSTRAINT [CK_OverrideApproval_Shape] CHECK (
        ([EventKind] = N'Approved' AND [RefersToOverrideApprovalId] IS NULL AND [ExpiresAt] IS NOT NULL AND [Reason] IS NOT NULL)
     OR ([EventKind] = N'Withdrawn' AND [RefersToOverrideApprovalId] IS NOT NULL)
     OR ([EventKind] = N'Used' AND [RefersToOverrideApprovalId] IS NOT NULL AND [SegregationOverrideId] IS NOT NULL))
);
GO
CREATE INDEX [IX_OverrideApproval_Subject] ON [security].[OverrideApproval] ([SubjectKind], [SubjectEntityId], [Action], [ForPersonEntityId]) INCLUDE ([EventKind], [ExpiresAt]);
GO
CREATE INDEX [IX_OverrideApproval_RefersTo] ON [security].[OverrideApproval] ([RefersToOverrideApprovalId]) WHERE [RefersToOverrideApprovalId] IS NOT NULL;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'security', @level1type = N'TABLE', @level1name = N'OverrideApproval';
GO
