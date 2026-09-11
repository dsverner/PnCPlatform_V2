-- SCHEMA-DESIGN §12.7 (decision 167); PROCEDURES.md #24.
-- Approves an evidence package: computes PackageHash as SHA-256 over its manifest (every row
-- version and file the package cites, in manifest order), sets the approver and instant, and logs
-- the approval. From then on the package and its manifest are read-only — enforced by the triggers
-- compliance.trEvidencePackageFrozen and trEvidencePackageManifestFrozen, the only way to stop the
-- generated _Update / _Append (implementation choice, STEPS.md step 12). A correction is a new
-- package citing the old.
CREATE PROCEDURE [compliance].[ApproveEvidencePackage]
    @PackageEntityId UNIQUEIDENTIFIER,
    @ApprovedAt DATETIMEOFFSET(7) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @PackageHash BINARY(32) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    SET @ApprovedAt = ISNULL(@ApprovedAt, @now);
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;

    DECLARE @rowId UNIQUEIDENTIFIER, @priorApprovedAt DATETIMEOFFSET(7);
    SELECT @rowId = [RowId], @priorApprovedAt = [ApprovedAt] FROM [compliance].[vEvidencePackage] WHERE [EntityId] = @PackageEntityId;
    IF @rowId IS NULL THROW 50350, N'compliance.ApproveEvidencePackage: the package is not current.', 1;
    IF @priorApprovedAt IS NOT NULL THROW 50351, N'compliance.ApproveEvidencePackage: the package is already approved and read-only (§12.7).', 1;
    IF NOT EXISTS (SELECT 1 FROM [compliance].[EvidencePackageManifest] WHERE [PackageEntityId] = @PackageEntityId)
        THROW 50352, N'compliance.ApproveEvidencePackage: the package has no manifest; an approved package must list what it contains (§12.7).', 1;

    DECLARE @manifest NVARCHAR(MAX) = (
        SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), CONCAT([ItemKind], N':', CONVERT(NVARCHAR(36), [ItemRowId]), N':', ISNULL(CONVERT(NVARCHAR(64), [FileSha256], 2), N''))), N'|')
               WITHIN GROUP (ORDER BY [ManifestId])
        FROM [compliance].[EvidencePackageManifest] WHERE [PackageEntityId] = @PackageEntityId);
    SET @PackageHash = HASHBYTES('SHA2_256', @manifest);

    BEGIN TRANSACTION;
    UPDATE [compliance].[EvidencePackage]
       SET [ApprovedByActorId] = @ActorId, [ApprovedAt] = @ApprovedAt, [PackageHash] = @PackageHash, [ModifiedBy] = @ActorId, [ModifiedAt] = @now
     WHERE [RowId] = @rowId AND [IsDeleted] = 0;
    EXEC [audit].[LogAction] @ActionKindCode = N'Approval', @SubjectSchema = N'compliance', @SubjectTable = N'EvidencePackage',
                             @SubjectEntityId = @PackageEntityId, @SubjectRowId = @rowId, @ActorId = @ActorId, @OccurredAt = @ApprovedAt;
    COMMIT TRANSACTION;
END;
GO
