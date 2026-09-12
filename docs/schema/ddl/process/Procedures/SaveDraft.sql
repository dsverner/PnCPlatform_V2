-- PROCEDURE-ENGINE §1, §4 (W4). The draft of an Active step: writable only by its claimant (50164), replaced whole on
-- every save (a JSON object of captured field values as the document declares them), renewing the claim's lease.
-- Reads of the draft by anyone but the claimant are audit-logged by the API's read logging (config.ReadLoggedClass
-- process.StepInstance, decision #68) — nothing here.
CREATE PROCEDURE [process].[SaveDraft]
    @StepInstanceEntityId UNIQUEIDENTIFIER,
    @Draft NVARCHAR(MAX),
    @LeaseMinutes INT = 30,
    @ActorId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    IF @Draft IS NOT NULL AND ISJSON(@Draft) <> 1 THROW 50165, N'process.SaveDraft: the draft is not valid JSON.', 1;
    DECLARE @state NVARCHAR(40), @claimant UNIQUEIDENTIFIER;
    SELECT @state = [State], @claimant = [ClaimedByActorId] FROM [process].[StepInstance] WHERE [EntityId] = @StepInstanceEntityId AND [IsDeleted] = 0;
    IF @state IS NULL THROW 50143, N'process.SaveDraft: no live step instance with that id.', 1;
    IF @state <> N'Active' THROW 50157, N'process.SaveDraft: claim the step first; only an Active step holds a draft.', 1;
    IF (SELECT [PersonEntityId] FROM [personnel].[Actor] WHERE [ActorId] = @claimant) <> (SELECT [PersonEntityId] FROM [personnel].[Actor] WHERE [ActorId] = @ActorId)
        THROW 50164, N'process.SaveDraft: the draft is writable only by the claimant.', 1;
    UPDATE [process].[StepInstance]
       SET [Draft] = @Draft, [DraftModifiedAt] = @now, [ClaimExpiresAt] = DATEADD(MINUTE, @LeaseMinutes, @now), [ModifiedBy] = @ActorId, [ModifiedAt] = @now
     WHERE [EntityId] = @StepInstanceEntityId AND [IsDeleted] = 0;
END;
GO
