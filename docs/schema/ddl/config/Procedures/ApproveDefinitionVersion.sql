-- SCHEMA-DESIGN §2.2. Approves a Draft version and makes it Effective from @EffectiveFrom,
-- retiring the prior effective version of the same definition (rule: one Effective version at an
-- instant per applies-to match). Author ≠ approver is the segregation rule of §11.7, evaluated by
-- security.CheckSegregation against the effective Program.SegregationRule definitions (Author /
-- Approve on a DefinitionVersion; warn-and-log by default, so the same person proceeds only with
-- @OverrideReason and the override is recorded). Logs an Approval action.
CREATE PROCEDURE [config].[ApproveDefinitionVersion]
    @VersionRowId UNIQUEIDENTIFIER,
    @EffectiveFrom DATETIMEOFFSET(7) = NULL,
    @OverrideReason NVARCHAR(400) = NULL,
    @OverrideApprovedByActorId UNIQUEIDENTIFIER = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    SET @EffectiveFrom = ISNULL(@EffectiveFrom, @now);
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;

    DECLARE @defEntity UNIQUEIDENTIFIER, @createdBy UNIQUEIDENTIFIER, @status NVARCHAR(20), @entityId UNIQUEIDENTIFIER;
    SELECT @defEntity = [DefinitionEntityId], @createdBy = [CreatedBy], @status = [Status], @entityId = [EntityId]
    FROM [config].[DefinitionVersion] WHERE [RowId] = @VersionRowId AND [IsDeleted] = 0;
    IF @defEntity IS NULL THROW 50030, N'Unknown definition version.', 1;
    IF @status <> N'Draft' THROW 50031, N'Only Draft versions can be approved.', 1;

    BEGIN TRANSACTION;
    EXEC [security].[CheckSegregation] @ActionA = N'Author', @ActionB = N'Approve', @SubjectKind = N'DefinitionVersion', @SubjectEntityId = @VersionRowId,
         @ActorA = @createdBy, @ActorB = @ActorId, @OverrideReason = @OverrideReason, @OverrideApprovedByActorId = @OverrideApprovedByActorId, @OccurredAt = @now;

    UPDATE [config].[DefinitionVersion]
       SET [Status] = N'Retired', [EffectiveTo] = @EffectiveFrom, [ModifiedBy] = @ActorId, [ModifiedAt] = @now
     WHERE [DefinitionEntityId] = @defEntity AND [IsDeleted] = 0 AND [Status] = N'Effective' AND [EffectiveTo] IS NULL;

    UPDATE [config].[DefinitionVersion]
       SET [Status] = N'Effective', [EffectiveFrom] = @EffectiveFrom, [ApprovedBy] = @ActorId, [ApprovedAt] = @now,
           [ModifiedBy] = @ActorId, [ModifiedAt] = @now
     WHERE [RowId] = @VersionRowId;

    EXEC [audit].[LogAction] @ActionKindCode = N'Approval', @SubjectSchema = N'config', @SubjectTable = N'DefinitionVersion',
                             @SubjectEntityId = @entityId, @SubjectRowId = @VersionRowId, @DefinitionVersionRowId = @VersionRowId, @ActorId = @ActorId;
    COMMIT TRANSACTION;
END;
GO
