-- PROCEDURE-ENGINE §4 (W4). The interpreter's write for a step instance's non-commit states: Pending → Ready (the
-- precondition holds or there is none), Pending/Ready → Held (the precondition is Unknown; HeldReason names the
-- facts), Held → Ready, any uncommitted state → Skipped (its scope ended with a branch outcome, or a choice
-- passed it by; Outcome carries the reason). Committed is written only by CommitStep and is final (50152).
CREATE PROCEDURE [process].[SetStepState]
    @EntityId UNIQUEIDENTIFIER,
    @State NVARCHAR(40),
    @HeldReason NVARCHAR(400) = NULL,
    @Outcome NVARCHAR(40) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @cur NVARCHAR(40), @block UNIQUEIDENTIFIER;
    SELECT @cur = [State], @block = [BlockInstanceEntityId] FROM [process].[StepInstance] WHERE [EntityId] = @EntityId AND [IsDeleted] = 0;
    IF @cur IS NULL THROW 50143, N'process.SetStepState: no live step instance with that id.', 1;
    IF @cur IN (N'Committed', N'Skipped', N'Varied') THROW 50152, N'process.SetStepState: a committed, skipped or varied step is final.', 1;
    IF @State NOT IN (N'Pending', N'Ready', N'Held', N'Skipped') THROW 50151, N'process.SetStepState: only Pending, Ready, Held and Skipped are set here; Committed is CommitStep''s.', 1;
    UPDATE [process].[StepInstance]
       SET [State] = @State,
           [HeldReason] = CASE WHEN @State = N'Held' THEN @HeldReason ELSE NULL END,
           [Outcome] = CASE WHEN @State = N'Skipped' THEN ISNULL(@Outcome, N'Skipped') ELSE [Outcome] END,
           [ModifiedBy] = @ActorId, [ModifiedAt] = @now
     WHERE [EntityId] = @EntityId AND [IsDeleted] = 0;
    -- the step's block mirrors it: Ready/Held/Active steps are Running/Held blocks; a skipped step is a skipped block
    UPDATE [process].[BlockInstance]
       SET [State] = CASE @State WHEN N'Skipped' THEN N'Skipped' WHEN N'Held' THEN N'Held' WHEN N'Pending' THEN N'Pending' ELSE N'Running' END,
           [Outcome] = CASE WHEN @State = N'Skipped' THEN ISNULL(@Outcome, N'Skipped') ELSE [Outcome] END,
           [StartedAt] = CASE WHEN @State IN (N'Ready', N'Held') AND [StartedAt] IS NULL THEN @now ELSE [StartedAt] END,
           [CompletedAt] = CASE WHEN @State = N'Skipped' THEN @now ELSE [CompletedAt] END,
           [ModifiedBy] = @ActorId, [ModifiedAt] = @now
     WHERE [EntityId] = @block AND [IsDeleted] = 0 AND [State] NOT IN (N'Completed', N'Skipped', N'Cancelled');
END;
GO
