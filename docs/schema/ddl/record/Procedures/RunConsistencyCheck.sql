-- SCHEMA-DESIGN §10.9 (decision 151), §6.9; PROCEDURES.md #21.
-- The SCD-versus-registry check: the IEDs the SCD revision's parse produced (connection.Ied rows
-- for that revision) against the registry — devices carrying an IedName alternate key, or already
-- matched by Ied.DeviceEntityId. Writes the ConsistencyCheck record with its counts and one Finding
-- of category ConsistencyMismatch per unmatched IED on either side, in one transaction.
-- Implementation choice (STEPS.md step 10): the registry side is every current device with an
-- IedName key (the design does not narrow it to a station); finding severity Minor.
CREATE PROCEDURE [record].[RunConsistencyCheck]
    @ScdConfigurationFileRevisionRowId UNIQUEIDENTIFIER,
    @OccurredAt DATETIMEOFFSET(7) = NULL,
    @PerformedByActorId UNIQUEIDENTIFIER = NULL,
    @WorkRequestEntityId UNIQUEIDENTIFIER = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,
    @RecordEntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @Findings INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @OccurredAt = ISNULL(@OccurredAt, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    SET @PerformedByActorId = ISNULL(@PerformedByActorId, @ActorId);
    IF NOT EXISTS (SELECT 1 FROM [document].[vConfigurationFile] WHERE [RevisionRowId] = @ScdConfigurationFileRevisionRowId AND [FileKind] = N'Scd')
        THROW 50330, N'record.RunConsistencyCheck: the revision is not a current SCD configuration file (§10.9).', 1;

    DECLARE @scl TABLE ([IedName] NVARCHAR(100), [DeviceEntityId] UNIQUEIDENTIFIER, [Matched] BIT);
    DECLARE @registry TABLE ([IedName] NVARCHAR(100), [DeviceEntityId] UNIQUEIDENTIFIER, [Matched] BIT);
    INSERT @registry SELECT k.[KeyValue], k.[SubjectEntityId], 0
    FROM [asset].[vAlternateKey] k JOIN [device].[vDevice] d ON d.[EntityId] = k.[SubjectEntityId] WHERE k.[KeyKindCode] = N'IedName';
    INSERT @scl SELECT i.[IedName], i.[DeviceEntityId], 0 FROM [connection].[vIed] i WHERE i.[ConfigurationFileRevisionRowId] = @ScdConfigurationFileRevisionRowId;
    UPDATE s SET [Matched] = 1 FROM @scl s WHERE s.[DeviceEntityId] IS NOT NULL OR EXISTS (SELECT 1 FROM @registry r WHERE r.[IedName] = s.[IedName]);
    UPDATE r SET [Matched] = 1 FROM @registry r WHERE EXISTS (SELECT 1 FROM @scl s WHERE s.[IedName] = r.[IedName] OR s.[DeviceEntityId] = r.[DeviceEntityId]);

    DECLARE @inScl INT = (SELECT COUNT(*) FROM @scl), @inReg INT = (SELECT COUNT(*) FROM @registry),
            @matched INT = (SELECT COUNT(*) FROM @scl WHERE [Matched] = 1),
            @unScl INT = (SELECT COUNT(*) FROM @scl WHERE [Matched] = 0), @unReg INT = (SELECT COUNT(*) FROM @registry WHERE [Matched] = 0);
    SET @Findings = 0;
    BEGIN TRANSACTION;
    DECLARE @result NVARCHAR(20) = CASE WHEN @unScl + @unReg = 0 THEN N'Pass' ELSE N'Fail' END;
    DECLARE @summary NVARCHAR(1000) = CONCAT(N'SCL ', @inScl, N', registry ', @inReg, N', matched ', @matched, N', unmatched SCL ', @unScl, N', unmatched registry ', @unReg);
    EXEC [record].[Record_Add] @RecordKindCode = N'ConsistencyCheck', @SubjectKind = N'ConfigurationFileRevision', @SubjectEntityId = @ScdConfigurationFileRevisionRowId,
         @WorkRequestEntityId = @WorkRequestEntityId, @OccurredAt = @OccurredAt, @TimeSourceQuality = 3, @PerformedByActorId = @PerformedByActorId, @OverallResult = @result, @Summary = @summary,
         @ValidFrom = @OccurredAt, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @RecordEntityId OUTPUT;
    EXEC [record].[ConsistencyCheck_Add] @EntityId = @RecordEntityId, @ScdConfigurationFileRevisionRowId = @ScdConfigurationFileRevisionRowId,
         @IedsInScl = @inScl, @IedsInRegistry = @inReg, @Matched = @matched, @UnmatchedScl = @unScl, @UnmatchedRegistry = @unReg,
         @ValidFrom = @OccurredAt, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId;

    DECLARE @name NVARCHAR(100), @dev UNIQUEIDENTIFIER, @side NVARCHAR(10), @f UNIQUEIDENTIFIER, @desc NVARCHAR(MAX);
    DECLARE un CURSOR LOCAL FAST_FORWARD FOR
        SELECT [IedName], NULL, N'Scl' FROM @scl WHERE [Matched] = 0
        UNION ALL SELECT [IedName], [DeviceEntityId], N'Registry' FROM @registry WHERE [Matched] = 0;
    OPEN un; FETCH NEXT FROM un INTO @name, @dev, @side;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @f = NULL;
        SET @desc = CASE @side WHEN N'Scl' THEN CONCAT(N'IED ', @name, N' is in the SCD but matches no registered device.') ELSE CONCAT(N'Device with IED name ', @name, N' is registered but absent from the SCD.') END;
        IF @side = N'Scl'
            EXEC [record].[Record_Add] @RecordKindCode = N'Finding', @SubjectKind = N'ConfigurationFileRevision', @SubjectEntityId = @ScdConfigurationFileRevisionRowId,
                 @SecondSubjectKind = N'Record', @SecondSubjectEntityId = @RecordEntityId, @WorkRequestEntityId = @WorkRequestEntityId,
                 @OccurredAt = @OccurredAt, @TimeSourceQuality = 3, @PerformedByActorId = @PerformedByActorId, @OverallResult = N'Fail', @Summary = N'Consistency mismatch',
                 @ValidFrom = @OccurredAt, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @f OUTPUT;
        ELSE
            EXEC [record].[Record_Add] @RecordKindCode = N'Finding', @SubjectKind = N'Device', @SubjectEntityId = @dev,
                 @SecondSubjectKind = N'Record', @SecondSubjectEntityId = @RecordEntityId, @WorkRequestEntityId = @WorkRequestEntityId,
                 @OccurredAt = @OccurredAt, @TimeSourceQuality = 3, @PerformedByActorId = @PerformedByActorId, @OverallResult = N'Fail', @Summary = N'Consistency mismatch',
                 @ValidFrom = @OccurredAt, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @f OUTPUT;
        EXEC [record].[Finding_Add] @EntityId = @f, @FindingCategoryCode = N'ConsistencyMismatch', @Severity = N'Minor', @Description = @desc, @AsFoundValue = @name,
             @ValidFrom = @OccurredAt, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId;
        SET @Findings += 1;
        FETCH NEXT FROM un INTO @name, @dev, @side;
    END;
    CLOSE un; DEALLOCATE un;
    COMMIT TRANSACTION;
END;
GO
