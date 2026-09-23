-- #232 (2026-09-23): a second person approves an override for someone else, from their own session — the witness pattern
-- (process.WitnessStep, #114) applied to §11.7. Until #232, security.CheckSegregation lifted a Block rule when the person who
-- wanted the override NAMED another person as approver; nothing showed that person approved. Now the approval is the
-- approver's own act, recorded here, and CheckSegregation (and work.AssignPerson) consume it; a name in a request is ignored.
-- The owner, 2026-09-23: the approver must be someone who could do the action themselves. So eligibility is the act's own
-- gate, decided here so every path agrees — the permission the act needs (security.fHasPermission, for any user), and where
-- the act is role-gated, the role (process.ClaimStep's grant predicate):
--   DefinitionVersion                    Definition.Approve
--   ConfigurationFileRevision, DocumentRevision  Document.Approve or ConfigurationFile.Approve (both Global, as the act is)
--   Record                               Record.Approve on the record
--   ProcedureInstance (a step sign-off)  Record.Modify on its work request + the role of a step of that run whose sign-off is
--                                        the action + that role's competency (@CompetencyOk: evaluated by the API endpoint,
--                                        as the commit's is; this procedure is not callable through the generic endpoint)
--   WorkflowInstance (a transition)      WorkRequest.Modify on its work request + the roles of a transition whose sign-off is
--                                        the action (or of its from-state), when it names any
--   WorkRequest (work.AssignPerson)      WorkRequest.Modify on the request
-- Never for oneself (person, not actor); a reason is required; single use; expires after @ValidHours (24 by default).
CREATE PROCEDURE [security].[ApproveOverride]
    @SubjectKind NVARCHAR(40),
    @SubjectEntityId UNIQUEIDENTIFIER,
    @Action NVARCHAR(100),
    @ForPersonEntityId UNIQUEIDENTIFIER,
    @Reason NVARCHAR(400),
    @CompetencyOk BIT = 0,
    @ValidHours INT = 24,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @OverrideApprovalId BIGINT = NULL OUTPUT,
    @ExpiresAt DATETIMEOFFSET(7) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @person UNIQUEIDENTIFIER, @user UNIQUEIDENTIFIER;
    SELECT @person = [PersonEntityId], @user = [ActingUserEntityId] FROM [personnel].[Actor] WHERE [ActorId] = @ActorId;
    IF @person IS NULL OR @user IS NULL THROW 50255, N'security.ApproveOverride: an override is approved by a signed-in person.', 1;
    IF @person = @ForPersonEntityId THROW 50256, N'security.ApproveOverride: you cannot approve an override for yourself; another person who could do this approves it.', 1;
    SET @Reason = NULLIF(LTRIM(RTRIM(@Reason)), N'');
    IF @Reason IS NULL THROW 50257, N'security.ApproveOverride: say why the override is acceptable.', 1;
    IF @SubjectEntityId IS NULL OR NULLIF(@Action, N'') IS NULL THROW 50257, N'security.ApproveOverride: name the item and the action being approved.', 1;
    IF NOT EXISTS (SELECT 1 FROM [personnel].[Actor] WHERE [PersonEntityId] = @ForPersonEntityId) THROW 50257, N'security.ApproveOverride: no such person.', 1;

    DECLARE @may BIT = 0, @wr UNIQUEIDENTIFIER, @version UNIQUEIDENTIFIER;
    DECLARE @roles TABLE ([RoleCode] NVARCHAR(40) PRIMARY KEY);
    IF @SubjectKind = N'DefinitionVersion'
        SET @may = [security].[fHasPermission](@user, N'Definition.Approve', N'DefinitionVersion', @SubjectEntityId, @now);
    ELSE IF @SubjectKind IN (N'ConfigurationFileRevision', N'DocumentRevision')
        SET @may = CASE WHEN [security].[fHasPermission](@user, N'Document.Approve', NULL, NULL, @now) = 1
                          OR [security].[fHasPermission](@user, N'ConfigurationFile.Approve', NULL, NULL, @now) = 1 THEN 1 ELSE 0 END;
    ELSE IF @SubjectKind = N'Record'
        SET @may = [security].[fHasPermission](@user, N'Record.Approve', N'Record', @SubjectEntityId, @now);
    ELSE IF @SubjectKind = N'WorkRequest'
        SET @may = [security].[fHasPermission](@user, N'WorkRequest.Modify', N'WorkRequest', @SubjectEntityId, @now);
    ELSE IF @SubjectKind = N'ProcedureInstance'
    BEGIN
        SELECT @wr = [WorkRequestEntityId], @version = [DefinitionVersionRowId] FROM [process].[ProcedureInstance] WHERE [EntityId] = @SubjectEntityId AND [IsDeleted] = 0;
        INSERT @roles SELECT DISTINCT ps.[RoleCode] FROM [process].[ProcedureStep] ps
        WHERE ps.[DefinitionVersionRowId] = @version AND ps.[IsDeleted] = 0 AND ps.[SignoffAction] = @Action AND ps.[RoleCode] IS NOT NULL;
        SET @may = CASE WHEN @version IS NOT NULL AND EXISTS (SELECT 1 FROM @roles) AND ISNULL(@CompetencyOk, 0) = 1
                         AND [security].[fHasPermission](@user, N'Record.Modify', N'WorkRequest', @wr, @now) = 1 THEN 1 ELSE 0 END;
    END
    ELSE IF @SubjectKind = N'WorkflowInstance'
    BEGIN
        DECLARE @wfSubjectKind NVARCHAR(40), @wfSubject UNIQUEIDENTIFIER;
        -- the work request as the transition endpoint finds it (ProcessEndpoints.WorkflowHead): the run the workflow started, else its subject
        SELECT TOP (1) @version = w.[WorkflowDefinitionVersionRowId], @wfSubjectKind = w.[SubjectKind], @wfSubject = w.[SubjectEntityId]
        FROM [process].[WorkflowInstance] w WHERE w.[EntityId] = @SubjectEntityId AND w.[IsDeleted] = 0 ORDER BY w.[RowSeq] DESC;
        SET @wr = (SELECT TOP (1) pi.[WorkRequestEntityId] FROM [process].[ProcedureInstance] pi WHERE pi.[WorkflowInstanceEntityId] = @SubjectEntityId AND pi.[IsDeleted] = 0);
        IF @wr IS NULL AND @wfSubjectKind = N'WorkRequest' SET @wr = @wfSubject;
        -- the transitions signed off with this action: their roles, else their from-state's
        INSERT @roles SELECT DISTINCT r.[value]
        FROM [config].[DefinitionVersion] dv CROSS APPLY OPENJSON(dv.[PayloadText], '$.transitions') tr
        CROSS APPLY OPENJSON(ISNULL(JSON_QUERY(tr.[value], '$.roles'),
                    (SELECT TOP (1) JSON_QUERY(st.[value], '$.roles') FROM OPENJSON(dv.[PayloadText], '$.states') st WHERE JSON_VALUE(st.[value], '$.code') = JSON_VALUE(tr.[value], '$.from')))) r
        WHERE dv.[RowId] = @version AND JSON_VALUE(tr.[value], '$.signoff') = @Action;
        SET @may = CASE WHEN @version IS NOT NULL AND [security].[fHasPermission](@user, N'WorkRequest.Modify', N'WorkRequest', @wr, @now) = 1 THEN 1 ELSE 0 END;
    END
    ELSE
    BEGIN
        DECLARE @m0 NVARCHAR(400) = CONCAT(N'security.ApproveOverride: overrides on ', @SubjectKind, N' are not approved this way.');
        THROW 50258, @m0, 1;
    END;
    -- a role-gated act: the approver holds one of its roles (any scope), or Administrator — as process.ClaimStep asks the claimant
    IF @may = 1 AND EXISTS (SELECT 1 FROM @roles)
       AND NOT EXISTS (SELECT 1 FROM [security].[fGrantAsOf](@now, SYSUTCDATETIME()) g JOIN [security].[vUser] u ON u.[EntityId] = g.[GranteeEntityId]
                       WHERE g.[GranteeKind] = N'User' AND u.[PersonEntityId] = @person AND g.[RevokedByActorId] IS NULL AND g.[IsDeleted] = 0
                         AND (g.[RoleCode] IN (SELECT [RoleCode] FROM @roles) OR g.[RoleCode] = N'Administrator'))
        SET @may = 0;
    IF @may = 0 THROW 50259, N'security.ApproveOverride: only a person who could do this themselves may approve the override.', 1;

    SET @ExpiresAt = DATEADD(HOUR, CASE WHEN @ValidHours BETWEEN 1 AND 24 THEN @ValidHours ELSE 24 END, @now);
    BEGIN TRANSACTION;
    DECLARE @detail NVARCHAR(MAX) = (SELECT N'override-approved' AS [action], @SubjectKind AS [subjectKind], @Action AS [approvedAction], @ForPersonEntityId AS [forPerson], @Reason AS [reason], @ExpiresAt AS [expiresAt] FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DECLARE @logId BIGINT;
    EXEC [audit].[LogAction] @ActionKindCode = N'Override', @SubjectSchema = N'security', @SubjectTable = N'OverrideApproval', @SubjectEntityId = @SubjectEntityId,
         @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now, @ActionLogId = @logId OUTPUT;
    INSERT [security].[OverrideApproval] ([EventKind], [SubjectKind], [SubjectEntityId], [Action], [ForPersonEntityId], [Reason], [ActorId], [OccurredAt], [ExpiresAt], [ActionLogId])
    VALUES (N'Approved', @SubjectKind, @SubjectEntityId, @Action, @ForPersonEntityId, @Reason, @ActorId, @now, @ExpiresAt, @logId);
    SET @OverrideApprovalId = SCOPE_IDENTITY();
    COMMIT TRANSACTION;
END;
GO
