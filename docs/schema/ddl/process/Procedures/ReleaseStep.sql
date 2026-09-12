-- PROCEDURE-ENGINE §4 "The claim" (#55; W4). The claimant releases the step: it returns to Ready for anyone in the role;
-- the draft stays with the step. Only the claimant (or their person under another actor) may release (50162).
CREATE PROCEDURE [process].[ReleaseStep]
    @StepInstanceEntityId UNIQUEIDENTIFIER,
    @ActorId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @state NVARCHAR(40), @claimant UNIQUEIDENTIFIER;
    SELECT @state = [State], @claimant = [ClaimedByActorId] FROM [process].[StepInstance] WHERE [EntityId] = @StepInstanceEntityId AND [IsDeleted] = 0;
    IF @state IS NULL THROW 50143, N'process.ReleaseStep: no live step instance with that id.', 1;
    IF @state <> N'Active' THROW 50157, N'process.ReleaseStep: the step is not claimed.', 1;
    IF (SELECT [PersonEntityId] FROM [personnel].[Actor] WHERE [ActorId] = @claimant) <> (SELECT [PersonEntityId] FROM [personnel].[Actor] WHERE [ActorId] = @ActorId)
        THROW 50162, N'process.ReleaseStep: only the claimant releases a step; an engineer may take it over with a reason.', 1;
    UPDATE [process].[StepInstance]
       SET [State] = N'Ready', [ClaimedByActorId] = NULL, [ClaimedAt] = NULL, [ClaimExpiresAt] = NULL, [ModifiedBy] = @ActorId, [ModifiedAt] = @now
     WHERE [EntityId] = @StepInstanceEntityId AND [IsDeleted] = 0;
END;
GO
