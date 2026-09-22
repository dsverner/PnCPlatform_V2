-- SCHEMA-DESIGN §8.1 (decision 124), §8.4 (128), §11.7 (158); PROCEDURES.md #16, #15 (item rule).
-- Approves a Draft or Checked revision: prepared ≠ approved through security.CheckSegregation
-- (Prepare / Approve on a ConfigurationFileRevision when the revision carries a configuration file,
-- else on a DocumentRevision; the preparer is PreparedByActorId, falling back to CreatedBy).
-- A configuration-file revision that belongs to an open settings-issue package (package revision
-- Draft or Checked) may not be approved on its own; document.ApproveSettingsIssuePackage passes
-- @PackageRevisionRowId and the package is recorded as the authority. Logs an Approval action.
-- Implementation choice (STEPS.md step 8): the status change is applied to the current revision
-- row in place (system versioning keeps the prior state) because subclasses, files, links and
-- package items key the revision by RowId; "open package" = package revision Draft or Checked.
CREATE PROCEDURE [document].[ApproveRevision]
    @RevisionRowId UNIQUEIDENTIFIER,
    @ApprovedAt DATETIMEOFFSET(7) = NULL,
    @OverrideReason NVARCHAR(400) = NULL,
    @OverrideApprovedByActorId UNIQUEIDENTIFIER = NULL,
    @PackageRevisionRowId UNIQUEIDENTIFIER = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    SET @ApprovedAt = ISNULL(@ApprovedAt, @now);
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;

    DECLARE @entityId UNIQUEIDENTIFIER, @status NVARCHAR(20), @preparer UNIQUEIDENTIFIER, @createdBy UNIQUEIDENTIFIER, @docEntity UNIQUEIDENTIFIER;
    SELECT @entityId = [EntityId], @status = [Status], @preparer = [PreparedByActorId], @createdBy = [CreatedBy], @docEntity = [DocumentEntityId]
    FROM [document].[vRevision] WHERE [RowId] = @RevisionRowId;
    IF @entityId IS NULL THROW 50240, N'document.ApproveRevision: the revision is not a current revision.', 1;
    IF @status NOT IN (N'Draft', N'Checked')
    BEGIN
        DECLARE @m1 NVARCHAR(400) = CONCAT(N'document.ApproveRevision: only a Draft or Checked revision can be approved; this one is ', @status, N'.');
        THROW 50241, @m1, 1;
    END;

    DECLARE @isConfig BIT = CASE WHEN EXISTS (SELECT 1 FROM [document].[vConfigurationFile] WHERE [RevisionRowId] = @RevisionRowId) THEN 1 ELSE 0 END;
    DECLARE @subjectKind NVARCHAR(40) = CASE WHEN @isConfig = 1 THEN N'ConfigurationFileRevision' ELSE N'DocumentRevision' END;

    -- an item of an open package is approved through the package (§8.4)
    DECLARE @openPackage UNIQUEIDENTIFIER;
    SELECT TOP (1) @openPackage = i.[PackageRevisionRowId]
    FROM [document].[vSettingsIssuePackageItem] i JOIN [document].[vRevision] p ON p.[RowId] = i.[PackageRevisionRowId]
    WHERE i.[ConfigurationFileRevisionRowId] = @RevisionRowId AND p.[Status] IN (N'Draft', N'Checked');
    IF @openPackage IS NOT NULL AND (@PackageRevisionRowId IS NULL OR @PackageRevisionRowId <> @openPackage)
        THROW 50242, N'document.ApproveRevision: the revision belongs to an open settings-issue package and is approved through the package (§8.4).', 1;

    BEGIN TRANSACTION;
    DECLARE @author UNIQUEIDENTIFIER = ISNULL(@preparer, @createdBy);
    EXEC [security].[CheckSegregation] @ActionA = N'Prepare', @ActionB = N'Approve', @SubjectKind = @subjectKind, @SubjectEntityId = @RevisionRowId,
         @ActorA = @author, @ActorB = @ActorId, @OverrideReason = @OverrideReason, @OverrideApprovedByActorId = @OverrideApprovedByActorId, @OccurredAt = @ApprovedAt;

    UPDATE [document].[Revision]
       SET [Status] = N'Approved', [ApprovedByActorId] = @ActorId, [ApprovedAt] = @ApprovedAt, [ModifiedBy] = @ActorId, [ModifiedAt] = @now
     WHERE [RowId] = @RevisionRowId AND [IsDeleted] = 0 AND [ValidTo] IS NULL;
    IF @@ROWCOUNT = 0 THROW 50240, N'document.ApproveRevision: the revision is not a current revision.', 1;

    -- #219: the platform-generated rationale of a configuration-file revision is issued with it and never edited after
    IF @isConfig = 1
        UPDATE r SET r.[Status] = N'Issued', r.[IssuedAt] = @ApprovedAt, r.[ModifiedBy] = @ActorId, r.[ModifiedAt] = @now
          FROM [document].[Revision] r
          JOIN [document].[Rationale] ra ON ra.[RevisionRowId] = r.[RowId] AND ra.[IsDeleted] = 0
          JOIN [document].[RevisionLink] l ON l.[RevisionRowId] = r.[RowId] AND l.[LinkKind] = N'About' AND l.[SubjectKind] = N'DocumentRevision'
                                            AND l.[SubjectEntityId] = @RevisionRowId AND l.[ValidTo] IS NULL AND l.[IsDeleted] = 0
         WHERE r.[Status] = N'Draft' AND r.[IsDeleted] = 0 AND r.[ValidTo] IS NULL;

    DECLARE @detail NVARCHAR(MAX) = CASE WHEN @PackageRevisionRowId IS NULL THEN NULL
                                         ELSE (SELECT @PackageRevisionRowId AS [authorityPackageRevisionRowId] FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) END;
    EXEC [audit].[LogAction] @ActionKindCode = N'Approval', @SubjectSchema = N'document', @SubjectTable = N'Revision',
                             @SubjectEntityId = @entityId, @SubjectRowId = @RevisionRowId, @Detail = @detail, @ActorId = @ActorId, @OccurredAt = @ApprovedAt;
    COMMIT TRANSACTION;
END;
GO
