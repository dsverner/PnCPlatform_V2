-- PROCEDURE-ENGINE §5 "Commit", §5.1, §5.2 (W4, decisions #106–#115). The one event that matters, in one transaction.
-- The grammar's verdicts (3 validation, 4 competency) are the interpreter's and arrive as parameters; everything else
-- is decided and written here, in §5's order:
--   1 claim  2 precondition (a step is Active only after it held)  3 validation  4 competency  5 segregation (instance-
--   wide: this step's signoff.action against every prior committer of a paired action in the instance, decision #110)
--   6 witness (a second person's attestation from their own session within 15 minutes, decision #114)  7 record
--   8 kind-specific rows (§5.1; the vocabulary of the deployed CHECKs, decision #108)  9 acceptance (no record kind
--   requires it yet — a template flag arrives with the kinds that do)  10 produces  11 branch outcome (the interpreter
--   ends the scope; the outcome is returned)  12 advances (the interpreter fires the transition; returned)  13 immutability.
-- Deferred commit (§5.2): @CapturedByActorId is the technician who captured (the act is theirs: PerformedBy and
-- CommittedBy), the session actor is AcceptedIntoPlatformBy, OccurredAt is the capture instant, and segregation and
-- competency are the technician's (the interpreter evaluated competency for that person).
-- Captured fields stay on the step (Draft, readable as step.capture); record.CharacteristicValue rows need a
-- characteristic template per record kind, which no kind carries yet (recorded, decision #115).
-- Evidence: a JSON array of {"name","mimeType","kind","contentBase64"}; for ConfigurationFileRevision and Readback the
-- first item IS the configuration file (a revision of the device's configuration document); the rest attach as evidence.
-- THROWs 50190–50199 in the rule's words.
CREATE PROCEDURE [process].[CommitStep]
    @StepInstanceEntityId UNIQUEIDENTIFIER,
    @Outcome NVARCHAR(40) = NULL,
    @Capture NVARCHAR(MAX) = NULL,
    @Evidence NVARCHAR(MAX) = NULL,
    @ValidationOk BIT = 1,
    @ValidationUnknowns NVARCHAR(MAX) = NULL,
    @CompetencyOk BIT = 1,
    @OverrideReason NVARCHAR(400) = NULL,
    @OverrideApprovedByActorId UNIQUEIDENTIFIER = NULL,
    @CapturedByActorId UNIQUEIDENTIFIER = NULL,
    @CapturedAt DATETIMEOFFSET(7) = NULL,
    @CaptureTimeQuality TINYINT = NULL,
    @At DATETIMEOFFSET(7) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @RecordEntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @ProducedEntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @BranchOutcome NVARCHAR(40) = NULL OUTPUT,
    @AdvancesWorkflowKey NVARCHAR(100) = NULL OUTPUT,
    @AdvancesTransition NVARCHAR(100) = NULL OUTPUT,
    @AdvancesSubjectEntityId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = ISNULL(@At, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;

    -- ---- the step, its block, its instance, its projection and its document node
    DECLARE @state NVARCHAR(40), @claimant UNIQUEIDENTIFIER, @block UNIQUEIDENTIFIER, @stepId NVARCHAR(64), @draft NVARCHAR(MAX), @witness UNIQUEIDENTIFIER,
            @instance UNIQUEIDENTIFIER, @version UNIQUEIDENTIFIER, @doc NVARCHAR(MAX), @subjectKind NVARCHAR(40), @subject UNIQUEIDENTIFIER, @wr UNIQUEIDENTIFIER, @produced NVARCHAR(MAX),
            @recordKind NVARCHAR(40), @signoff NVARCHAR(100), @needsWitness BIT, @title NVARCHAR(200), @producesName NVARCHAR(40), @producesKind NVARCHAR(40),
            @memberKind NVARCHAR(40), @member UNIQUEIDENTIFIER, @iRow UNIQUEIDENTIFIER;
    SELECT @state = s.[State], @claimant = s.[ClaimedByActorId], @block = s.[BlockInstanceEntityId], @stepId = s.[StepId], @draft = s.[Draft], @witness = s.[WitnessedByActorId],
           @instance = b.[ProcedureInstanceEntityId]
    FROM [process].[StepInstance] s JOIN [process].[BlockInstance] b ON b.[EntityId] = s.[BlockInstanceEntityId]
    WHERE s.[EntityId] = @StepInstanceEntityId AND s.[IsDeleted] = 0;
    IF @state IS NULL THROW 50143, N'process.CommitStep: no live step instance with that id.', 1;
    SELECT @iRow = i.[RowId], @version = i.[DefinitionVersionRowId], @doc = dv.[PayloadText], @subjectKind = i.[SubjectKind], @subject = i.[SubjectEntityId], @wr = i.[WorkRequestEntityId], @produced = ISNULL(i.[Produced], N'{}')
    FROM [process].[ProcedureInstance] i JOIN [config].[DefinitionVersion] dv ON dv.[RowId] = i.[DefinitionVersionRowId] WHERE i.[EntityId] = @instance;
    SELECT @recordKind = ps.[RecordKindCode], @signoff = ps.[SignoffAction], @needsWitness = ps.[RequiresWitness], @title = ps.[Title], @producesName = ps.[ProducesName], @producesKind = ps.[ProducesKind],
           @AdvancesWorkflowKey = ps.[AdvancesWorkflowKey], @AdvancesTransition = ps.[AdvancesTransition]
    FROM [process].[ProcedureStep] ps WHERE ps.[DefinitionVersionRowId] = @version AND ps.[StepId] = @stepId AND ps.[IsDeleted] = 0;
    DECLARE @node NVARCHAR(MAX) = (SELECT TOP (1) BlockJson FROM [process].[fProcedureBlocks](@doc) WHERE Kind = N'step' AND BlockId = @stepId);
    -- the subject: the nearest enclosing foreach member, else the instance's
    ;WITH up AS (
        SELECT [EntityId], [ParentBlockInstanceEntityId], [MemberSubjectKind], [MemberSubjectEntityId], 0 AS d FROM [process].[BlockInstance] WHERE [EntityId] = @block
        UNION ALL
        SELECT p.[EntityId], p.[ParentBlockInstanceEntityId], p.[MemberSubjectKind], p.[MemberSubjectEntityId], up.d + 1 FROM [process].[BlockInstance] p JOIN up ON p.[EntityId] = up.[ParentBlockInstanceEntityId] WHERE up.d < 32
    )
    SELECT TOP (1) @memberKind = [MemberSubjectKind], @member = [MemberSubjectEntityId] FROM up WHERE [MemberSubjectEntityId] IS NOT NULL ORDER BY d;
    DECLARE @recSubjectKind NVARCHAR(40) = ISNULL(@memberKind, @subjectKind), @recSubject UNIQUEIDENTIFIER = ISNULL(@member, @subject);
    DECLARE @pkg UNIQUEIDENTIFIER = TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(@produced, '$.package'));

    -- ---- 1 claim, 2 precondition
    IF @state <> N'Active' THROW 50190, N'process.CommitStep: only an Active (claimed) step commits; claim it first.', 1;
    DECLARE @person UNIQUEIDENTIFIER = (SELECT [PersonEntityId] FROM [personnel].[Actor] WHERE [ActorId] = @ActorId);
    IF (SELECT [PersonEntityId] FROM [personnel].[Actor] WHERE [ActorId] = @claimant) <> @person THROW 50190, N'process.CommitStep: the committing person must hold the claim.', 1;
    DECLARE @committer UNIQUEIDENTIFIER = ISNULL(@CapturedByActorId, @ActorId);     -- §5.2: the act is the technician's
    DECLARE @accepter UNIQUEIDENTIFIER = CASE WHEN @CapturedByActorId IS NULL THEN NULL ELSE @ActorId END;
    DECLARE @occurred DATETIMEOFFSET(7) = ISNULL(@CapturedAt, @now);
    DECLARE @tq TINYINT = ISNULL(@CaptureTimeQuality, CASE WHEN @CapturedByActorId IS NULL THEN 1 ELSE 2 END);
    DECLARE @source NVARCHAR(20) = CASE WHEN @CapturedByActorId IS NULL THEN N'Online' ELSE N'FieldPack' END;

    -- ---- the outcome: one of the step's (default Done)
    SET @Outcome = ISNULL(@Outcome, N'Done');
    IF NOT EXISTS (SELECT 1 FROM OPENJSON(ISNULL(JSON_QUERY(@node, '$.outcomes'), N'["Done"]')) o WHERE o.[value] = @Outcome)
    BEGIN DECLARE @m0 NVARCHAR(400) = N'process.CommitStep: ' + @Outcome + N' is not an outcome of step ' + @stepId + N' (' + (SELECT STRING_AGG([value], N', ') FROM OPENJSON(ISNULL(JSON_QUERY(@node, '$.outcomes'), N'["Done"]'))) + N').'; THROW 50195, @m0, 1; END
    SET @BranchOutcome = JSON_VALUE(@node, N'$.branchOutcome."' + @Outcome + N'"');

    -- ---- 3 validation (the interpreter's verdict, plus required fields present)
    IF @Capture IS NOT NULL AND ISJSON(@Capture) <> 1 THROW 50165, N'process.CommitStep: the capture is not valid JSON.', 1;
    SET @Capture = ISNULL(@Capture, @draft);
    IF @ValidationOk = 0
    BEGIN DECLARE @m1 NVARCHAR(400) = N'process.CommitStep: a captured value failed its validation' + CASE WHEN @ValidationUnknowns IS NULL THEN N'.' ELSE N'; unknown facts: ' + LEFT(@ValidationUnknowns, 300) END; THROW 50191, @m1, 1; END
    DECLARE @missing NVARCHAR(400) = (SELECT STRING_AGG(c.[key], N', ') FROM OPENJSON(@node, '$.capture') c
                                      WHERE JSON_VALUE(c.[value], '$.required') = 'true' AND JSON_VALUE(ISNULL(@Capture, N'{}'), N'$."' + c.[key] + N'"') IS NULL AND JSON_QUERY(ISNULL(@Capture, N'{}'), N'$."' + c.[key] + N'"') IS NULL);
    IF @missing IS NOT NULL BEGIN DECLARE @m2 NVARCHAR(400) = N'process.CommitStep: required captures are missing: ' + @missing; THROW 50191, @m2, 1; END

    -- ---- 4 competency
    IF @CompetencyOk = 0 THROW 50192, N'process.CommitStep: the committing person does not meet the role''s competency requirement.', 1;

    -- ---- 5 segregation, instance-wide (decision #110)
    IF @signoff IS NOT NULL
    BEGIN
        DECLARE @pa NVARCHAR(100), @pactor UNIQUEIDENTIFIER;
        DECLARE sc CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT ps2.[SignoffAction], s2.[CommittedByActorId]
            FROM [process].[StepInstance] s2 JOIN [process].[BlockInstance] b2 ON b2.[EntityId] = s2.[BlockInstanceEntityId]
            JOIN [process].[ProcedureStep] ps2 ON ps2.[DefinitionVersionRowId] = @version AND ps2.[StepId] = s2.[StepId] AND ps2.[IsDeleted] = 0
            WHERE b2.[ProcedureInstanceEntityId] = @instance AND s2.[IsDeleted] = 0 AND s2.[State] = N'Committed' AND ps2.[SignoffAction] IS NOT NULL AND s2.[CommittedByActorId] IS NOT NULL;
        OPEN sc; FETCH NEXT FROM sc INTO @pa, @pactor;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC [security].[CheckSegregation] @ActionA = @pa, @ActionB = @signoff, @SubjectKind = N'ProcedureInstance', @SubjectEntityId = @instance,
                 @ActorA = @pactor, @ActorB = @committer, @OverrideReason = @OverrideReason, @OverrideApprovedByActorId = @OverrideApprovedByActorId, @OccurredAt = @now;
            FETCH NEXT FROM sc INTO @pa, @pactor;
        END
        CLOSE sc; DEALLOCATE sc;
    END

    -- ---- 6 witness
    IF @needsWitness = 1
    BEGIN
        IF @witness IS NULL THROW 50193, N'process.CommitStep: this step must be witnessed by a second person before it commits.', 1;
        IF (SELECT [PersonEntityId] FROM [personnel].[Actor] WHERE [ActorId] = @witness) = (SELECT [PersonEntityId] FROM [personnel].[Actor] WHERE [ActorId] = @committer)
            THROW 50193, N'process.CommitStep: the witness must be a different person from the one committing.', 1;
        IF NOT EXISTS (SELECT 1 FROM [audit].[ActionLog] l WHERE l.[SubjectEntityId] = @StepInstanceEntityId AND l.[ActorId] = @witness AND JSON_VALUE(l.[Detail], '$.action') = N'witnessed' AND l.[OccurredAt] >= DATEADD(MINUTE, -15, @now))
            THROW 50193, N'process.CommitStep: the witness attestation is older than 15 minutes; witness again.', 1;
    END
    ELSE SET @witness = NULL;

    -- #168 (increment 2): the outstanding revision the package already holds for this step's device — the copy of the in-service
    -- settings made when the package was produced (CopyRevisionAsDraft), edited in the platform since
    DECLARE @pkgDraft UNIQUEIDENTIFIER;
    IF @pkg IS NOT NULL AND @recordKind = N'ConfigurationFileRevision'
        SELECT TOP (1) @pkgDraft = cf.[RevisionRowId]
        FROM [document].[SettingsIssuePackageItem] it JOIN [document].[ConfigurationFile] cf ON cf.[RevisionRowId] = it.[ConfigurationFileRevisionRowId] AND cf.[IsDeleted] = 0
        JOIN [document].[Revision] r ON r.[RowId] = cf.[RevisionRowId]
        WHERE it.[PackageRevisionRowId] = @pkg AND it.[IsDeleted] = 0 AND it.[ValidTo] IS NULL AND cf.[DeviceEntityId] = @recSubject AND r.[Status] = N'Draft' AND cf.[InServiceFrom] IS NULL
        ORDER BY it.[Sequence] DESC;

    -- ---- evidence: required kinds and minimum; the first item's bytes (#168: a settings step whose device holds a draft in the
    -- package needs no file — the platform writes the file from the settings edited here)
    IF @Evidence IS NOT NULL AND ISJSON(@Evidence) <> 1 THROW 50165, N'process.CommitStep: the evidence list is not valid JSON.', 1;
    DECLARE @evCount INT = ISNULL((SELECT COUNT(*) FROM OPENJSON(@Evidence)), 0);
    IF JSON_VALUE(@node, '$.evidence.required') = 'true' AND @evCount < ISNULL(TRY_CONVERT(INT, JSON_VALUE(@node, '$.evidence.min')), 1) AND NOT (@evCount = 0 AND @pkgDraft IS NOT NULL)
    BEGIN DECLARE @m3 NVARCHAR(400) = N'process.CommitStep: step ' + @stepId + N' requires evidence (' + ISNULL((SELECT STRING_AGG([value], N', ') FROM OPENJSON(@node, '$.evidence.kinds')), N'a file') + N'), at least ' + ISNULL(JSON_VALUE(@node, '$.evidence.min'), N'1') + N'.'; THROW 50194, @m3, 1; END
    DECLARE @f1Name NVARCHAR(255), @f1Mime NVARCHAR(100), @f1B64 NVARCHAR(MAX), @f1Bin VARBINARY(MAX), @f1Text NVARCHAR(MAX);
    IF @evCount > 0
    BEGIN
        SELECT @f1Name = JSON_VALUE(@Evidence, '$[0].name'), @f1Mime = ISNULL(JSON_VALUE(@Evidence, '$[0].mimeType'), N'application/octet-stream'), @f1B64 = JSON_VALUE(@Evidence, '$[0].contentBase64');
        SET @f1Bin = CAST(N'' AS XML).value('xs:base64Binary(sql:variable("@f1B64"))', 'VARBINARY(MAX)');
        SET @f1Text = CASE WHEN @f1Mime LIKE N'text/%' THEN CONVERT(NVARCHAR(MAX), CONVERT(VARCHAR(MAX), @f1Bin)) ELSE NULL END;
    END

    BEGIN TRANSACTION;
    -- ---- 7 record (§5.1 kinds that create their own record do so below)
    DECLARE @overall NVARCHAR(20) = CASE @Outcome WHEN N'Pass' THEN N'Pass' WHEN N'Fail' THEN N'Fail' ELSE NULL END;
    DECLARE @summary NVARCHAR(1000) = LEFT(@title + N' — ' + @Outcome, 1000);
    DECLARE @recRow UNIQUEIDENTIFIER, @cfRev UNIQUEIDENTIFIER, @cfKind NVARCHAR(20), @evRev UNIQUEIDENTIFIER, @evFiles INT, @restEvidence NVARCHAR(MAX) = @Evidence;

    IF @recordKind = N'Readback'
    BEGIN
        -- §5.1: the readback file as a new revision of the device's configuration document, compared with the package's design revision
        DECLARE @designRev UNIQUEIDENTIFIER;
        SELECT TOP (1) @designRev = cf.[RevisionRowId] FROM [document].[SettingsIssuePackageItem] it JOIN [document].[ConfigurationFile] cf ON cf.[RevisionRowId] = it.[ConfigurationFileRevisionRowId]
        WHERE it.[PackageRevisionRowId] = @pkg AND it.[IsDeleted] = 0 AND it.[ValidTo] IS NULL AND cf.[DeviceEntityId] = @recSubject AND cf.[CaptureKind] = N'Designed' ORDER BY it.[Sequence] DESC;
        IF @designRev IS NULL THROW 50196, N'process.CommitStep: no designed configuration-file revision for this device in the package to compare the readback with.', 1;
        IF @f1Bin IS NULL THROW 50194, N'process.CommitStep: a readback needs the readback file as its first evidence item.', 1;
        EXEC [process].[WriteConfigurationRevision] @DeviceEntityId = @recSubject, @CaptureKind = N'AsLeftReadback', @FileName = @f1Name, @MimeType = @f1Mime, @Content = @f1Bin, @TextContent = @f1Text,
             @PreparedByActorId = @committer, @At = @occurred, @ActorId = @ActorId, @RevisionRowId = @cfRev OUTPUT, @FileKind = @cfKind OUTPUT;
        DECLARE @diff INT = TRY_CONVERT(INT, JSON_VALUE(@Capture, '$.differenceCount'));
        IF @diff IS NULL SELECT TOP (1) @diff = TRY_CONVERT(INT, JSON_VALUE(@Capture, N'$."' + c.[key] + N'"')) FROM OPENJSON(@node, '$.capture') c WHERE JSON_VALUE(c.[value], '$.type') = N'num';
        DECLARE @cmp NVARCHAR(20) = CASE WHEN @diff IS NULL THEN N'NotComparable' WHEN @diff = 0 THEN N'Identical' ELSE N'Differs' END, @fnd UNIQUEIDENTIFIER;
        EXEC [record].[RecordReadback] @SubjectKind = @recSubjectKind, @SubjectEntityId = @recSubject, @ProducedConfigurationFileRevisionRowId = @cfRev, @ComparedToConfigurationFileRevisionRowId = @designRev,
             @ComparisonResult = @cmp, @DifferenceCount = @diff, @OccurredAt = @occurred, @TimeSourceQuality = @tq, @PerformedByActorId = @committer, @WorkRequestEntityId = @wr, @Summary = @summary,
             @ActorId = @ActorId, @RecordEntityId = @RecordEntityId OUTPUT, @FindingEntityId = @fnd OUTPUT;
        SET @restEvidence = (SELECT JSON_QUERY(N'[' + ISNULL(STRING_AGG(e.[value], N','), N'') + N']') FROM OPENJSON(@Evidence) e WHERE CAST(e.[key] AS INT) > 0);
    END
    ELSE
    BEGIN
        EXEC [record].[Record_Add] @RecordKindCode = @recordKind, @SubjectKind = @recSubjectKind, @SubjectEntityId = @recSubject, @WorkRequestEntityId = @wr,
             @OccurredAt = @occurred, @TimeSourceQuality = @tq, @PerformedByActorId = @committer, @WitnessedByActorId = @witness, @OverallResult = @overall, @Summary = @summary,
             @TemplateDefinitionVersionRowId = @version, @ActorId = @ActorId, @EntityId = @RecordEntityId OUTPUT, @RowId = @recRow OUTPUT;
    END

    -- ---- 8 kind-specific rows (§5.1)
    IF @recordKind = N'ConfigurationFileRevision'
    BEGIN
        IF @pkg IS NULL THROW 50196, N'process.CommitStep: no settings-issue package has been produced in this run (procedure.package).', 1;
        IF @f1Bin IS NULL AND @pkgDraft IS NULL THROW 50194, N'process.CommitStep: a configuration-file revision needs the settings file as its first evidence item (the device has no outstanding revision the platform could write).', 1;
        IF @f1Bin IS NULL
        BEGIN
            -- #168: no file attached — the platform writes the settings file from the draft's settings, edited here (IssueRenderedSettings)
            DECLARE @wrote BIT;
            EXEC [process].[IssueRenderedSettings] @ConfigurationFileRevisionRowId = @pkgDraft, @ActorId = @ActorId, @FileName = @f1Name OUTPUT, @Written = @wrote OUTPUT;
            SET @cfRev = @pkgDraft; SET @cfKind = N'SettingsText';
            SET @summary = LEFT(ISNULL(@summary + N' — ', N'') + N'settings file written by the platform: ' + ISNULL(@f1Name, N''), 400);
            UPDATE [record].[Record] SET [Summary] = @summary, [ModifiedBy] = @ActorId, [ModifiedAt] = @now WHERE [RowId] = @recRow;   -- the record was written before this branch
        END
        ELSE IF @pkgDraft IS NOT NULL
        BEGIN
            -- #168: a file attached over the platform's copy — the copy takes the file (one outstanding revision per device per package)
            DECLARE @filed NVARCHAR(255), @fsid2 UNIQUEIDENTIFIER;
            EXEC [process].[RefileRevision] @ConfigurationFileRevisionRowId = @pkgDraft, @FileName = @f1Name, @MimeType = @f1Mime, @Content = @f1Bin, @TextContent = @f1Text, @ActorId = @ActorId, @FiledName = @filed OUTPUT, @FileStreamId = @fsid2 OUTPUT;
            SET @cfRev = @pkgDraft; SET @cfKind = (SELECT [FileKind] FROM [document].[ConfigurationFile] WHERE [RevisionRowId] = @pkgDraft AND [IsDeleted] = 0);
        END
        ELSE
        BEGIN
            EXEC [process].[WriteConfigurationRevision] @DeviceEntityId = @recSubject, @CaptureKind = N'Designed', @FileName = @f1Name, @MimeType = @f1Mime, @Content = @f1Bin, @TextContent = @f1Text,
                 @PreparedByActorId = @committer, @At = @occurred, @ActorId = @ActorId, @RevisionRowId = @cfRev OUTPUT, @FileKind = @cfKind OUTPUT;
            DECLARE @seq INT = 1 + (SELECT COUNT(*) FROM [document].[SettingsIssuePackageItem] WHERE [PackageRevisionRowId] = @pkg AND [IsDeleted] = 0 AND [ValidTo] IS NULL), @ie UNIQUEIDENTIFIER, @ir UNIQUEIDENTIFIER;
            EXEC [document].[SettingsIssuePackageItem_Add] @PackageRevisionRowId = @pkg, @ConfigurationFileRevisionRowId = @cfRev, @Sequence = @seq, @ActorId = @ActorId, @EntityId = @ie OUTPUT, @RowId = @ir OUTPUT;
        END
        -- the record is about the revision it produced
        UPDATE [record].[Record] SET [SecondSubjectKind] = N'ConfigurationFileRevision', [SecondSubjectEntityId] = @cfRev WHERE [RowId] = @recRow;
        SET @restEvidence = (SELECT JSON_QUERY(N'[' + ISNULL(STRING_AGG(e.[value], N','), N'') + N']') FROM OPENJSON(@Evidence) e WHERE CAST(e.[key] AS INT) > 0);
    END
    ELSE IF @recordKind = N'Finding'
    BEGIN
        DECLARE @cat NVARCHAR(40) = ISNULL(JSON_VALUE(@node, '$.deviation.findingCategory'), N'SettingsDiscrepancy'), @fe UNIQUEIDENTIFIER, @frr UNIQUEIDENTIFIER;
        IF NOT EXISTS (SELECT 1 FROM [ref].[FindingCategory] WHERE [FindingCategoryCode] = @cat AND [IsActive] = 1) SET @cat = N'Observation';
        DECLARE @fdesc NVARCHAR(MAX) = ISNULL(JSON_VALUE(@node, '$.instruction'), @title) + N' Outcome: ' + @Outcome;
        DECLARE @disp NVARCHAR(30) = CASE WHEN @BranchOutcome IS NULL THEN N'Open' ELSE N'CorrectiveActionRaised' END;
        EXEC [record].[Finding_Add] @EntityId = @RecordEntityId, @FindingCategoryCode = @cat, @Severity = N'Major', @Description = @fdesc, @Disposition = @disp, @ActorId = @ActorId, @RowId = @frr OUTPUT;
    END
    ELSE IF @recordKind = N'EngineeringCheck' AND @pkg IS NOT NULL AND @Outcome = N'Pass'
    BEGIN
        UPDATE [document].[Revision] SET [Status] = N'Checked', [CheckedByActorId] = @committer, [CheckedAt] = @occurred, [ModifiedBy] = @ActorId, [ModifiedAt] = @now WHERE [RowId] = @pkg AND [IsDeleted] = 0 AND [Status] = N'Draft';
    END
    ELSE IF @recordKind = N'Approval' AND @pkg IS NOT NULL AND @Outcome = N'Approved'
    BEGIN
        DECLARE @approvedItems INT;
        EXEC [document].[ApproveSettingsIssuePackage] @PackageRevisionRowId = @pkg, @ApprovedAt = @occurred, @OverrideReason = @OverrideReason, @OverrideApprovedByActorId = @OverrideApprovedByActorId, @ActorId = @committer, @ItemsApproved = @approvedItems OUTPUT;
    END
    ELSE IF @recordKind = N'SettingsIssue' AND @pkg IS NOT NULL
    BEGIN
        UPDATE [document].[Revision] SET [Status] = N'Issued', [IssuedAt] = @occurred, [ModifiedBy] = @ActorId, [ModifiedAt] = @now WHERE [RowId] = @pkg AND [IsDeleted] = 0 AND [Status] = N'Approved';
    END
    ELSE IF @recordKind = N'Baseline' AND @pkg IS NOT NULL
    BEGIN
        -- FR-3.3: every designed revision in the package goes in service from the return-to-service instant, except a device whose member left the change (Superseded)
        DECLARE @rtsAt DATETIMEOFFSET(7) = ISNULL((SELECT TOP (1) s3.[CommittedAt] FROM [process].[StepInstance] s3 JOIN [process].[BlockInstance] b3 ON b3.[EntityId] = s3.[BlockInstanceEntityId]
                                                   JOIN [process].[ProcedureStep] ps3 ON ps3.[DefinitionVersionRowId] = @version AND ps3.[StepId] = s3.[StepId] AND ps3.[IsDeleted] = 0
                                                   WHERE b3.[ProcedureInstanceEntityId] = @instance AND s3.[State] = N'Committed' AND ps3.[RecordKindCode] = N'ReturnToService' ORDER BY s3.[CommittedAt] DESC), @occurred);
        DECLARE @itRev UNIQUEIDENTIFIER, @itDev UNIQUEIDENTIFIER, @unapproved BIT;
        DECLARE ic CURSOR LOCAL FAST_FORWARD FOR
            SELECT cf.[RevisionRowId], cf.[DeviceEntityId] FROM [document].[SettingsIssuePackageItem] it JOIN [document].[ConfigurationFile] cf ON cf.[RevisionRowId] = it.[ConfigurationFileRevisionRowId]
            WHERE it.[PackageRevisionRowId] = @pkg AND it.[IsDeleted] = 0 AND it.[ValidTo] IS NULL AND cf.[CaptureKind] = N'Designed'
              AND NOT EXISTS (SELECT 1 FROM [process].[BlockInstance] bx WHERE bx.[ProcedureInstanceEntityId] = @instance AND bx.[MemberSubjectEntityId] = cf.[DeviceEntityId] AND bx.[Outcome] = N'Superseded' AND bx.[IsDeleted] = 0)
            ORDER BY it.[Sequence];
        OPEN ic; FETCH NEXT FROM ic INTO @itRev, @itDev;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC [document].[SetInService] @RevisionRowId = @itRev, @InServiceFrom = @rtsAt, @InServiceFromQuality = 1, @ActorId = @ActorId, @IsUnapproved = @unapproved OUTPUT;
            FETCH NEXT FROM ic INTO @itRev, @itDev;
        END
        CLOSE ic; DEALLOCATE ic;
    END

    -- ---- 10 produces (the settings-issue package: a document of that class, its lifecycle workflow started)
    IF @producesName IS NOT NULL
    BEGIN
        IF @producesKind = N'SettingsIssuePackage'
        BEGIN
            DECLARE @pclass UNIQUEIDENTIFIER = (SELECT [EntityId] FROM [config].[Definition] WHERE [DefinitionKind] = N'CharacteristicSchema.DocumentClass' AND [DefinitionKey] = N'SettingsIssuePackage' AND [IsDeleted] = 0), @pdoc UNIQUEIDENTIFIER, @pe UNIQUEIDENTIFIER;
            IF @pclass IS NULL THROW 50198, N'process.CommitStep: the SettingsIssuePackage document class is not seeded.', 1;
            DECLARE @ptitle NVARCHAR(200) = LEFT(N'Settings-issue package — ' + ISNULL((SELECT TOP (1) [Title] FROM [work].[vWorkRequest] WHERE [EntityId] = @wr), LOWER(CONVERT(NVARCHAR(36), @instance))), 200);
            EXEC [document].[Document_Add] @DocumentClassDefinitionEntityId = @pclass, @Title = @ptitle, @ActorId = @ActorId, @EntityId = @pdoc OUTPUT;
            EXEC [document].[Revision_Add] @DocumentEntityId = @pdoc, @RevisionLabel = N'1', @Status = N'Draft', @PreparedByActorId = @committer, @PreparedAt = @occurred, @ActorId = @ActorId, @EntityId = @pe OUTPUT, @RowId = @ProducedEntityId OUTPUT;
            -- its lifecycle: every Effective workflow this version advances whose subject kind is the package's
            DECLARE @wfKey NVARCHAR(100), @wfi UNIQUEIDENTIFIER, @wfp UNIQUEIDENTIFIER;
            DECLARE wc CURSOR LOCAL FAST_FORWARD FOR
                SELECT DISTINCT ps4.[AdvancesWorkflowKey] FROM [process].[ProcedureStep] ps4
                JOIN [config].[Definition] wd ON wd.[DefinitionKind] = N'Program.Workflow' AND wd.[DefinitionKey] = ps4.[AdvancesWorkflowKey] AND wd.[IsDeleted] = 0
                JOIN [config].[DefinitionVersion] wv ON wv.[DefinitionEntityId] = wd.[EntityId] AND wv.[IsDeleted] = 0 AND wv.[Status] = N'Effective' AND JSON_VALUE(wv.[PayloadText], '$.subjectKind') = @producesKind
                WHERE ps4.[DefinitionVersionRowId] = @version AND ps4.[IsDeleted] = 0 AND ps4.[AdvancesWorkflowKey] IS NOT NULL;
            OPEN wc; FETCH NEXT FROM wc INTO @wfKey;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                EXEC [process].[StartWorkflow] @WorkflowKey = @wfKey, @SubjectKind = @producesKind, @SubjectEntityId = @ProducedEntityId, @WorkRequestEntityId = @wr, @ActorId = @ActorId, @EntityId = @wfi OUTPUT, @ProcedureInstanceEntityId = @wfp OUTPUT;
                FETCH NEXT FROM wc INTO @wfKey;
            END
            CLOSE wc; DEALLOCATE wc;
        END
        ELSE THROW 50198, N'process.CommitStep: only a SettingsIssuePackage can be produced in this wave.', 1;
        SET @produced = JSON_MODIFY(@produced, N'$."' + @producesName + N'"', LOWER(CONVERT(NVARCHAR(36), @ProducedEntityId)));
        UPDATE [process].[ProcedureInstance] SET [Produced] = @produced, [ModifiedBy] = @ActorId, [ModifiedAt] = @now WHERE [RowId] = @iRow;
        UPDATE [record].[Record] SET [SecondSubjectKind] = N'SettingsIssuePackage', [SecondSubjectEntityId] = @ProducedEntityId WHERE [RowId] = @recRow AND [SecondSubjectEntityId] IS NULL;
    END

    -- ---- 10b the devices this step names get their draft in the package (#168 increment 2; #187: at ANY step of the run,
    -- not only the one that produced the package). The full settings-change procedure captures its Device set at step [2],
    -- after step [1] produced the package; until #187 the drafting ran only inside the produces block, so [2]'s devices got
    -- nothing. The package is the one produced now, else the one this run produced earlier (procedure.package).
    DECLARE @draftPkg UNIQUEIDENTIFIER = COALESCE(CASE WHEN @producesKind = N'SettingsIssuePackage' THEN @ProducedEntityId END, @pkg);
    IF @draftPkg IS NOT NULL
    BEGIN
    -- #168 (increment 2): the legacy M from the A — every device named by a Device set captured at this step gets a draft
    -- revision copied from its in-service revision, in the package, outstanding at once (CopyRevisionAsDraft)
    DECLARE @devs TABLE ([DeviceEntityId] UNIQUEIDENTIFIER);
    DECLARE @capKey NVARCHAR(100), @capPath NVARCHAR(120);
    DECLARE ck CURSOR LOCAL FAST_FORWARD FOR SELECT c.[key] FROM OPENJSON(@node, '$.capture') c WHERE JSON_VALUE(c.[value], '$.type') = N'set' AND JSON_VALUE(c.[value], '$.refKind') = N'Device';
    OPEN ck; FETCH NEXT FROM ck INTO @capKey;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @capPath = N'$."' + @capKey + N'"';
        IF ISJSON(@Capture) = 1 AND JSON_QUERY(@Capture, @capPath) IS NOT NULL
            INSERT @devs SELECT DISTINCT TRY_CONVERT(UNIQUEIDENTIFIER, d.[value]) FROM OPENJSON(@Capture, @capPath) d WHERE TRY_CONVERT(UNIQUEIDENTIFIER, d.[value]) IS NOT NULL;
        FETCH NEXT FROM ck INTO @capKey;
    END
    CLOSE ck; DEALLOCATE ck;
    DECLARE @dev UNIQUEIDENTIFIER, @srcRev UNIQUEIDENTIFIER, @cpyRev UNIQUEIDENTIFIER;
    DECLARE dc CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT [DeviceEntityId] FROM @devs;
    OPEN dc; FETCH NEXT FROM dc INTO @dev;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC [process].[CopyRevisionAsDraft] @DeviceEntityId = @dev, @PackageRevisionRowId = @draftPkg, @PreparedByActorId = @committer, @At = @occurred, @ActorId = @ActorId, @SourceRevisionRowId = @srcRev OUTPUT, @RevisionRowId = @cpyRev OUTPUT;
        FETCH NEXT FROM dc INTO @dev;
    END
    CLOSE dc; DEALLOCATE dc;
    END

    -- ---- 7 (cont.) evidence files linked to the record
    IF @restEvidence IS NOT NULL AND EXISTS (SELECT 1 FROM OPENJSON(@restEvidence))
        EXEC [process].[WriteEvidence] @RecordEntityId = @RecordEntityId, @StepId = @stepId, @Evidence = @restEvidence, @PreparedByActorId = @committer, @At = @occurred, @ActorId = @ActorId, @RevisionRowId = @evRev OUTPUT, @Files = @evFiles OUTPUT;

    -- ---- 12 advances: the subject of the transition (the produced entity the document names, else the instance subject)
    IF @AdvancesWorkflowKey IS NOT NULL
    BEGIN
        DECLARE @advSubj NVARCHAR(100) = JSON_VALUE(@node, '$.advances.subject.fact');   -- procedure.<name>
        SET @AdvancesSubjectEntityId = CASE WHEN @advSubj LIKE N'procedure.%' THEN TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(@produced, N'$."' + SUBSTRING(@advSubj, 11, 100) + N'"')) ELSE @recSubject END;
        IF @AdvancesSubjectEntityId IS NULL THROW 50196, N'process.CommitStep: the advances subject is not bound (the producing step has not committed).', 1;
    END

    -- ---- 13 immutability
    UPDATE [process].[StepInstance]
       SET [State] = N'Committed', [Draft] = @Capture, [DraftModifiedAt] = ISNULL([DraftModifiedAt], @now),
           [CapturedAt] = @occurred, [CapturedByActorId] = @committer, [CaptureSource] = @source, [CaptureTimeQuality] = @tq,
           [CommittedRecordEntityId] = @RecordEntityId, [CommittedByActorId] = @committer, [WitnessedByActorId] = @witness, [AcceptedIntoPlatformByActorId] = @accepter,
           [CommittedAt] = @now, [Outcome] = @Outcome, [ClaimExpiresAt] = NULL, [HeldReason] = NULL, [ModifiedBy] = @ActorId, [ModifiedAt] = @now
     WHERE [EntityId] = @StepInstanceEntityId AND [IsDeleted] = 0;
    EXEC [process].[SetBlockState] @EntityId = @block, @State = N'Completed', @Outcome = @Outcome, @At = @now, @ActorId = @ActorId;
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"step-committed","step":"', @stepId, N'","outcome":"', STRING_ESCAPE(@Outcome, 'json'), N'","record":"', LOWER(CONVERT(NVARCHAR(36), @RecordEntityId)), N'","source":"', @source, N'"',
                                           CASE WHEN @accepter IS NULL THEN N'' ELSE CONCAT(N',"acceptedBy":"', LOWER(CONVERT(NVARCHAR(36), @accepter)), N'"') END, N'}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'process', @SubjectTable = N'StepInstance', @SubjectEntityId = @instance, @SubjectRowId = @StepInstanceEntityId,
         @DefinitionVersionRowId = @version, @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now;
    COMMIT TRANSACTION;
END;
GO
