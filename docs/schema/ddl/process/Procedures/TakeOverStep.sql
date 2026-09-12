-- PROCEDURE-ENGINE §4 "The claim" (#55; W4). The responsible engineer takes a claimed step over with a reason, which is
-- logged (Override action naming the prior claimant); the draft stays. PCEngineer or Administrator only (50163);
-- a reason is required (50155).
CREATE PROCEDURE [process].[TakeOverStep]
    @StepInstanceEntityId UNIQUEIDENTIFIER,
    @Reason NVARCHAR(400),
    @LeaseMinutes INT = 30,
    @ActorId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    IF NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL THROW 50155, N'process.TakeOverStep: a take-over needs a reason.', 1;
    DECLARE @state NVARCHAR(40), @claimant UNIQUEIDENTIFIER, @block UNIQUEIDENTIFIER, @instance UNIQUEIDENTIFIER;
    SELECT @state = s.[State], @claimant = s.[ClaimedByActorId], @block = s.[BlockInstanceEntityId] FROM [process].[StepInstance] s WHERE s.[EntityId] = @StepInstanceEntityId AND s.[IsDeleted] = 0;
    IF @state IS NULL THROW 50143, N'process.TakeOverStep: no live step instance with that id.', 1;
    IF @state NOT IN (N'Ready', N'Active') THROW 50157, N'process.TakeOverStep: only a Ready or Active step can be taken over.', 1;
    SELECT @instance = [ProcedureInstanceEntityId] FROM [process].[BlockInstance] WHERE [EntityId] = @block;
    DECLARE @person UNIQUEIDENTIFIER = (SELECT [PersonEntityId] FROM [personnel].[Actor] WHERE [ActorId] = @ActorId);
    IF NOT EXISTS (SELECT 1 FROM [security].[fGrantAsOf](@now, SYSUTCDATETIME()) g JOIN [security].[vUser] u ON u.[EntityId] = g.[GranteeEntityId]
                   WHERE g.[GranteeKind] = N'User' AND u.[PersonEntityId] = @person AND g.[RevokedByActorId] IS NULL AND g.[IsDeleted] = 0 AND g.[RoleCode] IN (N'PCEngineer', N'Administrator'))
        THROW 50163, N'process.TakeOverStep: only the responsible engineer (PCEngineer) or an Administrator takes a step over.', 1;
    BEGIN TRANSACTION;
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"step-taken-over","from":', CASE WHEN @claimant IS NULL THEN N'null' ELSE CONCAT(N'"', LOWER(CONVERT(NVARCHAR(36), @claimant)), N'"') END, N',"reason":"', STRING_ESCAPE(@Reason, 'json'), N'","step":"', LOWER(CONVERT(NVARCHAR(36), @StepInstanceEntityId)), N'"}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Override', @SubjectSchema = N'process', @SubjectTable = N'StepInstance', @SubjectEntityId = @instance, @ActorId = @ActorId, @Detail = @detail;
    UPDATE [process].[StepInstance]
       SET [State] = N'Active', [ClaimedByActorId] = @ActorId, [ClaimedAt] = @now, [ClaimExpiresAt] = DATEADD(MINUTE, @LeaseMinutes, @now), [ModifiedBy] = @ActorId, [ModifiedAt] = @now
     WHERE [EntityId] = @StepInstanceEntityId AND [IsDeleted] = 0;
    COMMIT TRANSACTION;
END;
GO
