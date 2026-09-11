-- SCHEMA-DESIGN §10.8 (decision 150), decision 55; PROCEDURES.md #19.
-- Records a readback (a record of kind Readback with its extension row) comparing the as-found
-- configuration file to the in-service one; a Differs result raises a Finding of category
-- AsFoundDrift in the same transaction — a record of kind Finding on the same subject, citing the
-- readback as its second subject. Severity is not stated by the design: Major (STEPS.md step 10).
CREATE PROCEDURE [record].[RecordReadback]
    @SubjectKind NVARCHAR(40),
    @SubjectEntityId UNIQUEIDENTIFIER,
    @ProducedConfigurationFileRevisionRowId UNIQUEIDENTIFIER,
    @ComparedToConfigurationFileRevisionRowId UNIQUEIDENTIFIER = NULL,
    @ComparisonResult NVARCHAR(20),
    @DifferenceCount INT = NULL,
    @DifferenceDetailRecordEntityId UNIQUEIDENTIFIER = NULL,
    @OccurredAt DATETIMEOFFSET(7) = NULL,
    @TimeSourceQuality TINYINT = 3,
    @PerformedByActorId UNIQUEIDENTIFIER = NULL,
    @WorkRequestEntityId UNIQUEIDENTIFIER = NULL,
    @Summary NVARCHAR(1000) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,
    @RecordEntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @FindingEntityId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @OccurredAt = ISNULL(@OccurredAt, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    SET @PerformedByActorId = ISNULL(@PerformedByActorId, @ActorId);
    IF @ComparisonResult NOT IN (N'Identical', N'Differs', N'NotComparable') THROW 50310, N'record.RecordReadback: ComparisonResult is Identical, Differs or NotComparable (§10.8).', 1;
    IF NOT EXISTS (SELECT 1 FROM [document].[vConfigurationFile] WHERE [RevisionRowId] = @ProducedConfigurationFileRevisionRowId)
        THROW 50311, N'record.RecordReadback: the produced revision carries no current configuration file.', 1;
    IF @ComparedToConfigurationFileRevisionRowId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [document].[vConfigurationFile] WHERE [RevisionRowId] = @ComparedToConfigurationFileRevisionRowId)
        THROW 50311, N'record.RecordReadback: the compared-to revision carries no current configuration file.', 1;
    IF @ComparisonResult = N'Differs' AND @ComparedToConfigurationFileRevisionRowId IS NULL
        THROW 50312, N'record.RecordReadback: Differs needs the revision compared to.', 1;

    SET @FindingEntityId = NULL;
    BEGIN TRANSACTION;
    DECLARE @result NVARCHAR(20) = CASE @ComparisonResult WHEN N'Identical' THEN N'Pass' WHEN N'Differs' THEN N'Fail' ELSE N'Informational' END;
    EXEC [record].[Record_Add] @RecordKindCode = N'Readback', @SubjectKind = @SubjectKind, @SubjectEntityId = @SubjectEntityId, @WorkRequestEntityId = @WorkRequestEntityId,
         @OccurredAt = @OccurredAt, @TimeSourceQuality = @TimeSourceQuality, @PerformedByActorId = @PerformedByActorId, @OverallResult = @result, @Summary = @Summary,
         @ValidFrom = @OccurredAt, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @RecordEntityId OUTPUT;
    EXEC [record].[Readback_Add] @EntityId = @RecordEntityId, @ProducedConfigurationFileRevisionRowId = @ProducedConfigurationFileRevisionRowId,
         @ComparedToConfigurationFileRevisionRowId = @ComparedToConfigurationFileRevisionRowId, @ComparisonResult = @ComparisonResult,
         @DifferenceCount = @DifferenceCount, @DifferenceDetailRecordEntityId = @DifferenceDetailRecordEntityId,
         @ValidFrom = @OccurredAt, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId;

    IF @ComparisonResult = N'Differs'
    BEGIN
        DECLARE @desc NVARCHAR(MAX) = CONCAT(N'As-found settings differ from the in-service configuration file (', ISNULL(CONVERT(NVARCHAR(10), @DifferenceCount), N'?'), N' differences) — readback ', CONVERT(NVARCHAR(36), @RecordEntityId), N'.');
        EXEC [record].[Record_Add] @RecordKindCode = N'Finding', @SubjectKind = @SubjectKind, @SubjectEntityId = @SubjectEntityId,
             @SecondSubjectKind = N'Record', @SecondSubjectEntityId = @RecordEntityId, @WorkRequestEntityId = @WorkRequestEntityId,
             @OccurredAt = @OccurredAt, @TimeSourceQuality = @TimeSourceQuality, @PerformedByActorId = @PerformedByActorId, @OverallResult = N'Fail', @Summary = N'As-found drift',
             @ValidFrom = @OccurredAt, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @FindingEntityId OUTPUT;
        DECLARE @asFound NVARCHAR(400) = CONVERT(NVARCHAR(36), @ProducedConfigurationFileRevisionRowId), @expected NVARCHAR(400) = CONVERT(NVARCHAR(36), @ComparedToConfigurationFileRevisionRowId);
        EXEC [record].[Finding_Add] @EntityId = @FindingEntityId, @FindingCategoryCode = N'AsFoundDrift', @Severity = N'Major', @Description = @desc,
             @AsFoundValue = @asFound, @ExpectedValue = @expected, @ValidFrom = @OccurredAt, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId;
    END;
    COMMIT TRANSACTION;
END;
GO
