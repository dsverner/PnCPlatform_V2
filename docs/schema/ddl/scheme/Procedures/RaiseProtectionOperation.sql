-- SCHEMA-DESIGN §7.6 (decision 122), §12.8 (168); PROCEDURES.md #13 (#23 partial).
-- Raises a protection operation and, in the same transaction:
--   * links it to the schemes involved — those protecting the primary asset (scheme.SchemeProtects)
--     plus @SchemeEntityId when given — as ProtectionOperationScheme rows (Role = @SchemeRole);
--   * appends ProtectionOperationSnapshot rows citing the ROW VERSIONS as-of the event of every
--     scheme membership of those schemes, every protection condition on those schemes, their member
--     functions and connections and the devices installed at the functions' positions, and every
--     configuration file in service on those devices, so a later correction never changes what was
--     recorded (vision §4.10, scenario 4);
--   * for Outcome = Incorrect opens a compliance.Exception of kind Misoperation on the primary asset,
--     citing @MisoperationRuleVersionRowId (required: an exception is opened under a rule version,
--     §12.8) with @ClockDueAt if the caller derived it — the derivation from the rule payload waits
--     on the formula grammar (PROCEDURES.md #23 stays partial) — and sets ExceptionEntityId.
CREATE PROCEDURE [scheme].[RaiseProtectionOperation]
    @OccurredAt DATETIMEOFFSET(7),
    @TimeSourceQuality TINYINT,
    @PrimaryAssetEntityId UNIQUEIDENTIFIER,
    @Outcome NVARCHAR(20),
    @DataSource NVARCHAR(20),
    @ElementsOperated NVARCHAR(400) = NULL,
    @ClearingTimeMs INT = NULL,
    @RecloseAttempts TINYINT = NULL,
    @RecloseSuccessful BIT = NULL,
    @IsConfirmed BIT = 0,
    @ReviewRecordEntityId UNIQUEIDENTIFIER = NULL,
    @Notes NVARCHAR(MAX) = NULL,
    @SchemeEntityId UNIQUEIDENTIFIER = NULL,
    @SchemeRole NVARCHAR(20) = N'Operated',
    @MisoperationRuleVersionRowId UNIQUEIDENTIFIER = NULL,
    @ClockDueAt DATETIMEOFFSET(7) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,
    @EntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @RowId UNIQUEIDENTIFIER = NULL OUTPUT,
    @ExceptionEntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @SnapshotRows INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM [asset].[vAsset] WHERE [EntityId] = @PrimaryAssetEntityId)
        THROW 50280, N'scheme.RaiseProtectionOperation: the primary asset is not a current asset.', 1;
    IF @SchemeEntityId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [scheme].[vScheme] WHERE [EntityId] = @SchemeEntityId)
        THROW 50281, N'scheme.RaiseProtectionOperation: the scheme is not a current scheme.', 1;
    IF @Outcome = N'Incorrect' AND @MisoperationRuleVersionRowId IS NULL
        THROW 50282, N'scheme.RaiseProtectionOperation: an Incorrect outcome opens a Misoperation exception under a rule version; pass @MisoperationRuleVersionRowId (the effective Program.ObligationRule version for misoperations, §12.8).', 1;
    IF @MisoperationRuleVersionRowId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [config].[vDefinitionVersion] WHERE [RowId] = @MisoperationRuleVersionRowId)
        THROW 50283, N'scheme.RaiseProtectionOperation: unknown rule definition version.', 1;

    DECLARE @schemes TABLE ([SchemeEntityId] UNIQUEIDENTIFIER PRIMARY KEY);
    INSERT @schemes SELECT DISTINCT [SchemeEntityId] FROM [scheme].[vSchemeProtects] WHERE [PrimaryAssetEntityId] = @PrimaryAssetEntityId;
    IF @SchemeEntityId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM @schemes WHERE [SchemeEntityId] = @SchemeEntityId) INSERT @schemes VALUES (@SchemeEntityId);

    DECLARE @believed DATETIME2(7) = SYSUTCDATETIME();
    SET @SnapshotRows = 0; SET @ExceptionEntityId = NULL;
    -- PROCEDURES.md #23: the exception clock comes from the caller. It used to be derived here from the
    -- rule version's 'within … of event' cadence; that evaluator left the database on 2026-09-10, and
    -- the application derives it (PnC.Api Services/ObligationDue.ClockDueAsync). A NULL clock stores
    -- nothing rather than a guess, exactly as fClockDue returning NULL did.
    BEGIN TRANSACTION;
    IF @Outcome = N'Incorrect'
        EXEC [compliance].[Exception_Add] @SubjectKind = N'Asset', @SubjectEntityId = @PrimaryAssetEntityId, @RuleDefinitionVersionRowId = @MisoperationRuleVersionRowId,
             @ExceptionKind = N'Misoperation', @OpenedAt = @OccurredAt, @OpenedByActorId = @ActorId, @ClockDueAt = @ClockDueAt,
             @ValidFrom = @OccurredAt, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @ExceptionEntityId OUTPUT;

    EXEC [scheme].[ProtectionOperation_Add] @OccurredAt = @OccurredAt, @TimeSourceQuality = @TimeSourceQuality, @PrimaryAssetEntityId = @PrimaryAssetEntityId, @Outcome = @Outcome,
         @ElementsOperated = @ElementsOperated, @ClearingTimeMs = @ClearingTimeMs, @RecloseAttempts = @RecloseAttempts, @RecloseSuccessful = @RecloseSuccessful,
         @DataSource = @DataSource, @IsConfirmed = @IsConfirmed, @ReviewRecordEntityId = @ReviewRecordEntityId, @ExceptionEntityId = @ExceptionEntityId, @Notes = @Notes,
         @ValidFrom = @OccurredAt, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @EntityId OUTPUT, @RowId = @RowId OUTPUT;

    DECLARE @s UNIQUEIDENTIFIER;
    DECLARE sc CURSOR LOCAL FAST_FORWARD FOR SELECT [SchemeEntityId] FROM @schemes;
    OPEN sc; FETCH NEXT FROM sc INTO @s;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC [scheme].[ProtectionOperationScheme_Add] @OperationEntityId = @EntityId, @SchemeEntityId = @s, @Role = @SchemeRole,
             @ValidFrom = @OccurredAt, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId;
        FETCH NEXT FROM sc INTO @s;
    END;
    CLOSE sc; DEALLOCATE sc;

    -- snapshot: row versions as-of the event (valid at OccurredAt, as believed now)
    DECLARE @members TABLE ([RowId] UNIQUEIDENTIFIER, [MemberKind] NVARCHAR(40), [MemberEntityId] UNIQUEIDENTIFIER);
    INSERT @members SELECT m.[RowId], m.[MemberKind], m.[MemberEntityId]
    FROM [scheme].[fSchemeMemberAsOf](@OccurredAt, @believed) m JOIN @schemes x ON x.[SchemeEntityId] = m.[SchemeEntityId] WHERE m.[IsDeleted] = 0;

    DECLARE @devices TABLE ([DeviceEntityId] UNIQUEIDENTIFIER);
    INSERT @devices SELECT DISTINCT pl.[AssetEntityId]
    FROM @members m
    JOIN [location].[vNode] fn ON m.[MemberKind] = N'ProtectionFunction' AND fn.[EntityId] = m.[MemberEntityId]
    JOIN [asset].[fPlacementAsOf](@OccurredAt, @believed) pl ON pl.[NodeEntityId] = fn.[ParentEntityId] AND pl.[PlacementKind] = N'Installed' AND pl.[IsDeleted] = 0;
    -- #193 (2026-09-19): since #176/#181 a scheme's relay is an Asset member (the function is the relay's, at its position, no node);
    -- the in-service settings of those relays are snapshotted too. Found by the schema smoke once it ran again (dead since #181).
    INSERT @devices SELECT DISTINCT m.[MemberEntityId] FROM @members m
    WHERE m.[MemberKind] = N'Asset' AND NOT EXISTS (SELECT 1 FROM @devices d WHERE d.[DeviceEntityId] = m.[MemberEntityId]);

    DECLARE @snap TABLE ([SubjectKind] NVARCHAR(40), [SubjectRowId] UNIQUEIDENTIFIER);
    INSERT @snap SELECT N'SchemeMember', [RowId] FROM @members;
    INSERT @snap SELECT N'ProtectionCondition', pc.[RowId]
    FROM [scheme].[fProtectionConditionAsOf](@OccurredAt, @believed) pc
    WHERE pc.[IsDeleted] = 0 AND (
          (pc.[SubjectKind] = N'Scheme' AND pc.[SubjectEntityId] IN (SELECT [SchemeEntityId] FROM @schemes))
       OR (pc.[SubjectKind] IN (N'ProtectionFunction', N'Connection') AND pc.[SubjectEntityId] IN (SELECT [MemberEntityId] FROM @members WHERE [MemberKind] = pc.[SubjectKind]))
       OR (pc.[SubjectKind] = N'Device' AND pc.[SubjectEntityId] IN (SELECT [DeviceEntityId] FROM @devices)));
    INSERT @snap SELECT N'ConfigurationFileRevision', cf.[RevisionRowId]
    FROM [document].[vConfigurationFile] cf JOIN @devices d ON d.[DeviceEntityId] = cf.[DeviceEntityId]
    WHERE cf.[InServiceFrom] IS NOT NULL AND cf.[InServiceFrom] <= @OccurredAt AND (cf.[InServiceTo] IS NULL OR cf.[InServiceTo] > @OccurredAt);

    DECLARE @k NVARCHAR(40), @r UNIQUEIDENTIFIER;
    DECLARE sn CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT [SubjectKind], [SubjectRowId] FROM @snap;
    OPEN sn; FETCH NEXT FROM sn INTO @k, @r;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC [scheme].[ProtectionOperationSnapshot_Append] @OperationEntityId = @EntityId, @SubjectKind = @k, @SubjectRowId = @r, @CapturedAt = @OccurredAt;
        SET @SnapshotRows += 1;
        FETCH NEXT FROM sn INTO @k, @r;
    END;
    CLOSE sn; DEALLOCATE sn;
    COMMIT TRANSACTION;
END;
GO
