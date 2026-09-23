-- #232 (2026-09-23): the approver takes back an override approval before it is used — their own, from their own session.
-- Appends a 'Withdrawn' event naming it (security.OverrideApproval is append-only); audited.
CREATE PROCEDURE [security].[WithdrawOverrideApproval]
    @OverrideApprovalId BIGINT,
    @ActorId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @kind NVARCHAR(40), @subject UNIQUEIDENTIFIER, @action NVARCHAR(100), @for UNIQUEIDENTIFIER, @approver UNIQUEIDENTIFIER;
    SELECT @kind = [SubjectKind], @subject = [SubjectEntityId], @action = [Action], @for = [ForPersonEntityId], @approver = [ActorId]
    FROM [security].[OverrideApproval] WHERE [OverrideApprovalId] = @OverrideApprovalId AND [EventKind] = N'Approved';
    IF @approver IS NULL THROW 50260, N'security.WithdrawOverrideApproval: no override approval with that number.', 1;
    IF (SELECT [PersonEntityId] FROM [personnel].[Actor] WHERE [ActorId] = @approver) <> (SELECT [PersonEntityId] FROM [personnel].[Actor] WHERE [ActorId] = @ActorId)
        THROW 50260, N'security.WithdrawOverrideApproval: only the person who gave an approval can take it back.', 1;
    IF EXISTS (SELECT 1 FROM [security].[OverrideApproval] WHERE [RefersToOverrideApprovalId] = @OverrideApprovalId)
        THROW 50260, N'security.WithdrawOverrideApproval: that approval has already been used or taken back.', 1;
    BEGIN TRANSACTION;
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"override-approval-withdrawn","approval":', @OverrideApprovalId, N'}');
    DECLARE @logId BIGINT;
    EXEC [audit].[LogAction] @ActionKindCode = N'Override', @SubjectSchema = N'security', @SubjectTable = N'OverrideApproval', @SubjectEntityId = @subject,
         @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now, @ActionLogId = @logId OUTPUT;
    INSERT [security].[OverrideApproval] ([EventKind], [RefersToOverrideApprovalId], [SubjectKind], [SubjectEntityId], [Action], [ForPersonEntityId], [ActorId], [OccurredAt], [ActionLogId])
    VALUES (N'Withdrawn', @OverrideApprovalId, @kind, @subject, @action, @for, @ActorId, @now, @logId);
    COMMIT TRANSACTION;
END;
GO
