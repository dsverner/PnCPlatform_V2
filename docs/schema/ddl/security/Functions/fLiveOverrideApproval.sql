-- #232 (2026-09-23): the approval a person holds, right now, for an override of one action on one item — the newest
-- 'Approved' event (security.ApproveOverride, the approver's own act) that has not expired and that no 'Withdrawn' or 'Used'
-- event names. Read by security.CheckSegregation and work.AssignPerson; the override then records a 'Used' event (single use).
CREATE FUNCTION [security].[fLiveOverrideApproval] (@SubjectKind NVARCHAR(40), @SubjectEntityId UNIQUEIDENTIFIER, @Action NVARCHAR(100), @ForPersonEntityId UNIQUEIDENTIFIER, @At DATETIMEOFFSET(7))
RETURNS TABLE
AS
RETURN (
    SELECT TOP (1) a.[OverrideApprovalId], a.[ActorId] AS [ApprovedByActorId], a.[Reason], a.[ExpiresAt]
    FROM [security].[OverrideApproval] a
    WHERE a.[EventKind] = N'Approved' AND a.[SubjectKind] = @SubjectKind AND a.[SubjectEntityId] = @SubjectEntityId
      AND a.[Action] = @Action AND a.[ForPersonEntityId] = @ForPersonEntityId AND a.[ExpiresAt] > @At
      AND NOT EXISTS (SELECT 1 FROM [security].[OverrideApproval] x WHERE x.[RefersToOverrideApprovalId] = a.[OverrideApprovalId])
    ORDER BY a.[OccurredAt] DESC, a.[OverrideApprovalId] DESC
);
GO
GRANT SELECT ON [security].[fLiveOverrideApproval] TO [app_execute];   -- the step read shows the live approval (ProcessEndpoints)
GO
