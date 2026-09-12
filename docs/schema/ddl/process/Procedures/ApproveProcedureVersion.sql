-- PROCEDURE-ENGINE §8 "Approval … Projection on approval" (W3). One transaction: config.ApproveDefinitionVersion
-- (the Author/Approve segregation rule, Effective from @EffectiveFrom, the prior version Retired, the Approval action
-- logged) and then process.ProjectProcedureVersion, so a version is never Effective without its projection.
-- Refuses any version that is not a Program.Procedure (workflows approve through config.ApproveDefinitionVersion alone).
CREATE PROCEDURE [process].[ApproveProcedureVersion]
    @VersionRowId UNIQUEIDENTIFIER,
    @EffectiveFrom DATETIMEOFFSET(7) = NULL,
    @OverrideReason NVARCHAR(400) = NULL,
    @OverrideApprovedByActorId UNIQUEIDENTIFIER = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @kind NVARCHAR(40);
    SELECT @kind = d.[DefinitionKind]
    FROM [config].[DefinitionVersion] dv JOIN [config].[Definition] d ON d.[EntityId] = dv.[DefinitionEntityId]
    WHERE dv.[RowId] = @VersionRowId AND dv.[IsDeleted] = 0;
    IF @kind IS NULL THROW 50030, N'Unknown definition version.', 1;
    IF @kind <> N'Program.Procedure' THROW 50134, N'Only a Program.Procedure version is approved here; workflows use config.ApproveDefinitionVersion.', 1;

    BEGIN TRANSACTION;
    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @VersionRowId, @EffectiveFrom = @EffectiveFrom,
         @OverrideReason = @OverrideReason, @OverrideApprovedByActorId = @OverrideApprovedByActorId, @ActorId = @ActorId;
    EXEC [process].[ProjectProcedureVersion] @VersionRowId = @VersionRowId, @ActorId = @ActorId;
    COMMIT TRANSACTION;
END;
GO
