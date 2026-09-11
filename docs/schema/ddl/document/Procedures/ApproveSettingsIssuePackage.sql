-- SCHEMA-DESIGN §8.4 (decision 128); PROCEDURES.md #15.
-- Approves a settings-issue package revision and, in the same transaction, every item's
-- configuration-file revision not already approved, recording the package as the authority
-- (decision 60). Segregation applies to the package (Prepare / Approve) through ApproveRevision.
CREATE PROCEDURE [document].[ApproveSettingsIssuePackage]
    @PackageRevisionRowId UNIQUEIDENTIFIER,
    @ApprovedAt DATETIMEOFFSET(7) = NULL,
    @OverrideReason NVARCHAR(400) = NULL,
    @OverrideApprovedByActorId UNIQUEIDENTIFIER = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @ItemsApproved INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ApprovedAt = ISNULL(@ApprovedAt, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM [document].[vSettingsIssuePackageItem] WHERE [PackageRevisionRowId] = @PackageRevisionRowId)
        THROW 50243, N'document.ApproveSettingsIssuePackage: the revision has no package items (§8.4).', 1;

    SET @ItemsApproved = 0;
    BEGIN TRANSACTION;
    EXEC [document].[ApproveRevision] @RevisionRowId = @PackageRevisionRowId, @ApprovedAt = @ApprovedAt,
         @OverrideReason = @OverrideReason, @OverrideApprovedByActorId = @OverrideApprovedByActorId, @ActorId = @ActorId;

    DECLARE @item UNIQUEIDENTIFIER;
    DECLARE items CURSOR LOCAL FAST_FORWARD FOR
        SELECT i.[ConfigurationFileRevisionRowId]
        FROM [document].[vSettingsIssuePackageItem] i JOIN [document].[vRevision] r ON r.[RowId] = i.[ConfigurationFileRevisionRowId]
        WHERE i.[PackageRevisionRowId] = @PackageRevisionRowId AND r.[Status] IN (N'Draft', N'Checked')
        ORDER BY i.[Sequence];
    OPEN items; FETCH NEXT FROM items INTO @item;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- the package's approver approves each item under the package's authority; the item's own
        -- preparer/approver segregation is evaluated per item with the same override, if any
        EXEC [document].[ApproveRevision] @RevisionRowId = @item, @ApprovedAt = @ApprovedAt, @OverrideReason = @OverrideReason,
             @OverrideApprovedByActorId = @OverrideApprovedByActorId, @PackageRevisionRowId = @PackageRevisionRowId, @ActorId = @ActorId;
        SET @ItemsApproved += 1;
        FETCH NEXT FROM items INTO @item;
    END;
    CLOSE items; DEALLOCATE items;
    COMMIT TRANSACTION;
END;
GO
