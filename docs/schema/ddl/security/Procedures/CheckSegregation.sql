-- SCHEMA-DESIGN §11.7 (decision 158); vision §9.5; PROCEDURES.md #1.
-- Segregation of duties from Program.SegregationRule definitions. Called by the procedure that
-- performs action B on a subject with the actor who performed action A. When both actors are the
-- same person, the strictest effective rule naming the pair (either order) and the subject kind
-- (or '*') applies:
--   WarnAndLog (the design's default) — proceeds only with a stated @OverrideReason; the override
--     is logged (audit.ActionLog kind Override) and appended to security.SegregationOverride.
--   Block — refuses unless a different person who could do the act has approved the override from their own session
--     (security.ApproveOverride, #232); the approval is used once and its approver recorded in SegregationOverride.ApprovedByActorId.
--     @OverrideApprovedByActorId is kept for the callers' signatures and ignored.
-- No effective rule naming the pair → no constraint. Payload shape (implementation choice, STEPS.md
-- step 11): {"rules":[{"actionA":"Prepare","actionB":"Approve","subjectKind":"ConfigurationFileRevision","mode":"WarnAndLog"}]}
CREATE PROCEDURE [security].[CheckSegregation]
    @ActionA NVARCHAR(100),
    @ActionB NVARCHAR(100),
    @SubjectKind NVARCHAR(40),
    @SubjectEntityId UNIQUEIDENTIFIER = NULL,
    @ActorA UNIQUEIDENTIFIER,
    @ActorB UNIQUEIDENTIFIER,
    @OverrideReason NVARCHAR(400) = NULL,
    @OverrideApprovedByActorId UNIQUEIDENTIFIER = NULL,
    @OccurredAt DATETIMEOFFSET(7) = NULL,
    @OverrideId BIGINT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @OccurredAt = ISNULL(@OccurredAt, SYSDATETIMEOFFSET());
    SET @OverrideId = NULL;
    IF @ActorA IS NULL OR @ActorB IS NULL RETURN;

    -- same actor, or two actor rows of one person (an author acting through another actor is still the author)
    DECLARE @same BIT = CASE WHEN @ActorA = @ActorB THEN 1 ELSE 0 END;
    IF @same = 0 AND EXISTS (SELECT 1 FROM [personnel].[Actor] a JOIN [personnel].[Actor] b ON b.[PersonEntityId] = a.[PersonEntityId]
                             WHERE a.[ActorId] = @ActorA AND b.[ActorId] = @ActorB AND a.[PersonEntityId] IS NOT NULL)
        SET @same = 1;
    IF @same = 0 RETURN;

    -- strictest effective rule for the pair
    DECLARE @mode NVARCHAR(20), @ruleVersion UNIQUEIDENTIFIER;
    SELECT TOP (1) @mode = r.[mode], @ruleVersion = v.[RowId]
    FROM [config].[vDefinitionVersion] v
    JOIN [config].[vDefinition] d ON d.[EntityId] = v.[DefinitionEntityId]
    CROSS APPLY OPENJSON(v.[PayloadText], '$.rules')
         WITH ([actionA] NVARCHAR(100), [actionB] NVARCHAR(100), [subjectKind] NVARCHAR(40), [mode] NVARCHAR(20)) r
    WHERE d.[DefinitionKind] = N'Program.SegregationRule' AND v.[Status] = N'Effective' AND v.[EffectiveTo] IS NULL
      AND ((r.[actionA] = @ActionA AND r.[actionB] = @ActionB) OR (r.[actionA] = @ActionB AND r.[actionB] = @ActionA))
      AND (r.[subjectKind] = @SubjectKind OR r.[subjectKind] = N'*' OR r.[subjectKind] IS NULL)
    ORDER BY CASE r.[mode] WHEN N'Block' THEN 0 ELSE 1 END, v.[EffectiveFrom] DESC;
    IF @mode IS NULL RETURN;

    DECLARE @pair NVARCHAR(200) = CONCAT(@ActionA, N' and ', @ActionB, N' of ', @SubjectKind);
    -- #232 (2026-09-23): the approval is the approver's own act (security.ApproveOverride, from their own session, by someone
    -- who could do this themselves), never a name the caller passes: @OverrideApprovedByActorId is ignored. The live approval
    -- for this item, this action and this person is taken, and used once.
    SET @OverrideApprovedByActorId = NULL;
    DECLARE @personB UNIQUEIDENTIFIER = (SELECT [PersonEntityId] FROM [personnel].[Actor] WHERE [ActorId] = @ActorB);
    DECLARE @approvalId BIGINT, @approvalReason NVARCHAR(400);
    SELECT @approvalId = [OverrideApprovalId], @OverrideApprovedByActorId = [ApprovedByActorId], @approvalReason = [Reason]
    FROM [security].[fLiveOverrideApproval](@SubjectKind, @SubjectEntityId, @ActionB, @personB, @OccurredAt);
    SET @OverrideReason = ISNULL(NULLIF(LTRIM(RTRIM(@OverrideReason)), N''), @approvalReason);
    IF @mode = N'Block'
    BEGIN
        IF @approvalId IS NULL
        BEGIN
            DECLARE @m1 NVARCHAR(400) = CONCAT(N'security.CheckSegregation: the same person may not perform ', @pair, N' unless another person who could do this approves an override first, from their own session.');
            THROW 50250, @m1, 1;
        END;
    END
    ELSE IF @OverrideReason IS NULL
    BEGIN
        DECLARE @m2 NVARCHAR(400) = CONCAT(N'security.CheckSegregation: segregation of duties — the same person is performing ', @pair, N'; state @OverrideReason to proceed (warn-and-log, vision §9.5).');
        THROW 50252, @m2, 1;
    END;

    DECLARE @detail NVARCHAR(MAX) = (SELECT @ActionA AS [actionA], @ActionB AS [actionB], @SubjectKind AS [subjectKind], @mode AS [mode], @OverrideReason AS [reason], @OverrideApprovedByActorId AS [approvedBy] FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DECLARE @logId BIGINT;
    EXEC [audit].[LogAction] @ActionKindCode = N'Override', @SubjectEntityId = @SubjectEntityId, @DefinitionVersionRowId = @ruleVersion,
                             @Detail = @detail, @ActorId = @ActorB, @OccurredAt = @OccurredAt, @ActionLogId = @logId OUTPUT;
    DECLARE @taken NVARCHAR(100) = LEFT(CONCAT(@ActionB, N' after ', @ActionA), 100);
    EXEC [security].[SegregationOverride_Append] @RuleDefinitionVersionRowId = @ruleVersion, @SubjectKind = @SubjectKind, @SubjectEntityId = @SubjectEntityId,
         @ActionTaken = @taken, @ActorId = @ActorB, @Reason = @OverrideReason, @ApprovedByActorId = @OverrideApprovedByActorId,
         @OccurredAt = @OccurredAt, @ActionLogId = @logId, @OverrideId = @OverrideId OUTPUT;
    IF @approvalId IS NOT NULL   -- #232: single use
        INSERT [security].[OverrideApproval] ([EventKind], [RefersToOverrideApprovalId], [SubjectKind], [SubjectEntityId], [Action], [ForPersonEntityId], [ActorId], [OccurredAt], [SegregationOverrideId], [ActionLogId])
        VALUES (N'Used', @approvalId, @SubjectKind, @SubjectEntityId, @ActionB, @personB, @ActorB, @OccurredAt, @OverrideId, @logId);
END;
GO
