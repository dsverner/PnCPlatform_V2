-- SCHEMA-DESIGN §9.7 (decision 141), §11.4, §11.6 (decision 157); PROCEDURES.md #18.
-- "Assign" is a grant of an assignment role (security.Role.RoleKind = Assignment) to the person's
-- user with ScopeKind = WorkRequest; no assignee column exists. The grant is gated by the effective
-- Program.QualificationRequirement definitions: work type × device category → qualification type,
-- mode Block or Warn. Warn proceeds and logs; Block refuses unless an override (§11.7) is recorded
-- with a reason and another person's approval. Payload shape (implementation choice, STEPS.md
-- step 11): {"requirements":[{"workType":"<Program.WorkType key>|*","deviceCategory":"<ref.Model.DeviceCategory>|*",
-- "qualificationTypeCode":"...","mode":"Block|Warn"}]}. The device category comes from the request's
-- scope when it is an Asset with a model; otherwise only "*" requirements apply.
CREATE PROCEDURE [work].[AssignPerson]
    @WorkRequestEntityId UNIQUEIDENTIFIER,
    @PersonEntityId UNIQUEIDENTIFIER,
    @RoleCode NVARCHAR(40) = N'Assignee',
    @OverrideReason NVARCHAR(400) = NULL,
    @OverrideApprovedByActorId UNIQUEIDENTIFIER = NULL,
    @OccurredAt DATETIMEOFFSET(7) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,
    @GrantEntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @RowId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @OccurredAt = ISNULL(@OccurredAt, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;

    DECLARE @workTypeVersion UNIQUEIDENTIFIER, @scopeKind NVARCHAR(40), @scope UNIQUEIDENTIFIER;
    SELECT @workTypeVersion = [WorkTypeDefinitionVersionRowId], @scopeKind = [ScopeKind], @scope = [ScopeEntityId] FROM [work].[vWorkRequest] WHERE [EntityId] = @WorkRequestEntityId;
    IF @workTypeVersion IS NULL THROW 50300, N'work.AssignPerson: the work request is not current.', 1;
    IF ISNULL((SELECT [RoleKind] FROM [security].[Role] WHERE [RoleCode] = @RoleCode AND [IsActive] = 1), N'') <> N'Assignment'
    BEGIN
        DECLARE @m0 NVARCHAR(400) = CONCAT(N'work.AssignPerson: role ', @RoleCode, N' is not an assignment role (§11.3).');
        THROW 50301, @m0, 1;
    END;
    DECLARE @user UNIQUEIDENTIFIER = (SELECT TOP (1) [EntityId] FROM [security].[vUser] WHERE [PersonEntityId] = @PersonEntityId AND [IsEnabled] = 1);
    IF @user IS NULL THROW 50302, N'work.AssignPerson: the person has no enabled user to grant against.', 1;

    DECLARE @workTypeKey NVARCHAR(100) = (SELECT d.[DefinitionKey] FROM [config].[vDefinitionVersion] v JOIN [config].[vDefinition] d ON d.[EntityId] = v.[DefinitionEntityId] WHERE v.[RowId] = @workTypeVersion);
    DECLARE @category NVARCHAR(40);
    IF @scopeKind = N'Asset'
        SELECT @category = m.[DeviceCategory] FROM [asset].[vAsset] a JOIN [ref].[Model] m ON m.[ModelId] = a.[ModelId] WHERE a.[EntityId] = @scope;

    -- the applicable requirements the person does not hold (current, unexpired, unrevoked qualification)
    DECLARE @missing TABLE ([QualificationTypeCode] NVARCHAR(40), [Mode] NVARCHAR(20), [RuleVersionRowId] UNIQUEIDENTIFIER);
    INSERT @missing
    SELECT r.[qualificationTypeCode], r.[mode], v.[RowId]
    FROM [config].[vDefinitionVersion] v JOIN [config].[vDefinition] d ON d.[EntityId] = v.[DefinitionEntityId]
    CROSS APPLY OPENJSON(v.[PayloadText], '$.requirements') WITH ([workType] NVARCHAR(100), [deviceCategory] NVARCHAR(40), [qualificationTypeCode] NVARCHAR(40), [mode] NVARCHAR(20)) r
    WHERE d.[DefinitionKind] = N'Program.QualificationRequirement' AND v.[Status] = N'Effective' AND v.[EffectiveTo] IS NULL
      AND (r.[workType] = N'*' OR r.[workType] = @workTypeKey)
      AND (r.[deviceCategory] = N'*' OR r.[deviceCategory] = @category)
      AND NOT EXISTS (SELECT 1 FROM [personnel].[vPersonQualification] pq
                      WHERE pq.[PersonEntityId] = @PersonEntityId AND pq.[QualificationTypeCode] = r.[qualificationTypeCode]
                        AND pq.[RevokedAt] IS NULL AND (pq.[ExpiresAt] IS NULL OR pq.[ExpiresAt] > @OccurredAt));
    DECLARE @blocked NVARCHAR(400) = (SELECT STRING_AGG([QualificationTypeCode], N', ') FROM @missing WHERE [Mode] = N'Block');
    DECLARE @warned  NVARCHAR(400) = (SELECT STRING_AGG([QualificationTypeCode], N', ') FROM @missing WHERE [Mode] <> N'Block');
    DECLARE @overrode BIT = 0;
    IF @blocked IS NOT NULL
    BEGIN
        IF @OverrideReason IS NULL OR @OverrideApprovedByActorId IS NULL
        BEGIN
            DECLARE @m1 NVARCHAR(400) = CONCAT(N'work.AssignPerson: the person lacks the qualification required for this work (Block): ', @blocked, N'; an override needs a reason and another person''s approval (§11.6, §11.7).');
            THROW 50303, @m1, 1;
        END;
        IF @OverrideApprovedByActorId = @ActorId THROW 50304, N'work.AssignPerson: the override must be approved by a different actor (§11.7).', 1;
        SET @overrode = 1;
    END;

    BEGIN TRANSACTION;
    IF @overrode = 1 OR @warned IS NOT NULL
    BEGIN
        DECLARE @ruleVersion UNIQUEIDENTIFIER = (SELECT TOP (1) [RuleVersionRowId] FROM @missing ORDER BY CASE [Mode] WHEN N'Block' THEN 0 ELSE 1 END);
        DECLARE @detail NVARCHAR(MAX) = (SELECT @blocked AS [blockedQualifications], @warned AS [warnedQualifications], @OverrideReason AS [reason], @OverrideApprovedByActorId AS [approvedBy] FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        DECLARE @logId BIGINT;
        EXEC [audit].[LogAction] @ActionKindCode = N'Override', @SubjectSchema = N'work', @SubjectTable = N'WorkRequest', @SubjectEntityId = @WorkRequestEntityId,
                                 @DefinitionVersionRowId = @ruleVersion, @Detail = @detail, @ActorId = @ActorId, @OccurredAt = @OccurredAt, @ActionLogId = @logId OUTPUT;
        IF @overrode = 1
            EXEC [security].[SegregationOverride_Append] @RuleDefinitionVersionRowId = @ruleVersion, @SubjectKind = N'WorkRequest', @SubjectEntityId = @WorkRequestEntityId,
                 @ActionTaken = N'Assign without required qualification', @ActorId = @ActorId, @Reason = @OverrideReason, @ApprovedByActorId = @OverrideApprovedByActorId,
                 @OccurredAt = @OccurredAt, @ActionLogId = @logId;
    END;
    EXEC [security].[Grant_Add] @GranteeKind = N'User', @GranteeEntityId = @user, @RoleCode = @RoleCode, @ScopeKind = N'WorkRequest', @ScopeWorkRequestEntityId = @WorkRequestEntityId,
         @GrantedByActorId = @ActorId, @ValidFrom = @OccurredAt, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @GrantEntityId OUTPUT, @RowId = @RowId OUTPUT;
    EXEC [audit].[LogAction] @ActionKindCode = N'Grant', @SubjectSchema = N'security', @SubjectTable = N'Grant', @SubjectEntityId = @GrantEntityId, @SubjectRowId = @RowId, @ActorId = @ActorId, @OccurredAt = @OccurredAt;
    COMMIT TRANSACTION;
END;
GO
