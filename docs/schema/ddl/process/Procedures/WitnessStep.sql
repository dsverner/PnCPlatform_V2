-- PROCEDURE-ENGINE §5 action 6, decision #114 (W4). A second signed-in person attests an Active step from their own
-- session: their resolved actor is recorded on the step (WitnessedByActorId) and the attestation is logged with its
-- instant. CommitStep requires the attestation to be fresh (15 minutes) and by a different person than the committer.
-- The witness is never a typed name: it is the session's own identity (API.md §2). 50166 the witness is the claimant.
CREATE PROCEDURE [process].[WitnessStep]
    @StepInstanceEntityId UNIQUEIDENTIFIER,
    @ActorId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @state NVARCHAR(40), @claimant UNIQUEIDENTIFIER, @block UNIQUEIDENTIFIER, @instance UNIQUEIDENTIFIER;
    SELECT @state = [State], @claimant = [ClaimedByActorId], @block = [BlockInstanceEntityId] FROM [process].[StepInstance] WHERE [EntityId] = @StepInstanceEntityId AND [IsDeleted] = 0;
    IF @state IS NULL THROW 50143, N'process.WitnessStep: no live step instance with that id.', 1;
    IF @state <> N'Active' THROW 50157, N'process.WitnessStep: only an Active (claimed) step is witnessed.', 1;
    IF (SELECT [PersonEntityId] FROM [personnel].[Actor] WHERE [ActorId] = @claimant) = (SELECT [PersonEntityId] FROM [personnel].[Actor] WHERE [ActorId] = @ActorId)
        THROW 50166, N'process.WitnessStep: the witness must be a second person, not the claimant.', 1;
    SELECT @instance = [ProcedureInstanceEntityId] FROM [process].[BlockInstance] WHERE [EntityId] = @block;
    BEGIN TRANSACTION;
    UPDATE [process].[StepInstance] SET [WitnessedByActorId] = @ActorId, [ModifiedBy] = @ActorId, [ModifiedAt] = @now WHERE [EntityId] = @StepInstanceEntityId AND [IsDeleted] = 0;
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"witnessed","step":"', LOWER(CONVERT(NVARCHAR(36), @StepInstanceEntityId)), N'"}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'process', @SubjectTable = N'StepInstance', @SubjectEntityId = @StepInstanceEntityId, @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now;
    COMMIT TRANSACTION;
END;
GO
