-- PROCEDURE-ENGINE §4 (W4). The interpreter's one write for a block activation's state: Pending → Running / Skipped,
-- Running → Held / Completed / Cancelled, Held → Running / Completed. Completed and Skipped carry an Outcome
-- (Done, NotApplicable, a branch outcome such as Superseded). A terminal state is final (50150). When a block
-- completes with a branch outcome, the interpreter skips the remaining steps of that scope itself (SetStepState).
CREATE PROCEDURE [process].[SetBlockState]
    @EntityId UNIQUEIDENTIFIER,
    @State NVARCHAR(40),
    @Outcome NVARCHAR(40) = NULL,
    @At DATETIMEOFFSET(7) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIMEOFFSET(7) = ISNULL(@At, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @cur NVARCHAR(40);
    SELECT @cur = [State] FROM [process].[BlockInstance] WHERE [EntityId] = @EntityId AND [IsDeleted] = 0;
    IF @cur IS NULL THROW 50143, N'process.SetBlockState: no live block instance with that id.', 1;
    IF @cur IN (N'Completed', N'Skipped', N'Cancelled') AND @State <> @cur THROW 50150, N'process.SetBlockState: a completed, skipped or cancelled block is final.', 1;
    IF @State NOT IN (N'Pending', N'Running', N'Held', N'Completed', N'Skipped', N'Cancelled') THROW 50151, N'process.SetBlockState: unknown state.', 1;
    UPDATE [process].[BlockInstance]
       SET [State] = @State,
           [Outcome] = CASE WHEN @State IN (N'Completed', N'Skipped', N'Cancelled') THEN ISNULL(@Outcome, CASE @State WHEN N'Completed' THEN N'Done' WHEN N'Skipped' THEN N'NotApplicable' ELSE N'Cancelled' END) ELSE [Outcome] END,
           [StartedAt] = CASE WHEN @State IN (N'Running', N'Held') AND [StartedAt] IS NULL THEN @now ELSE [StartedAt] END,
           [CompletedAt] = CASE WHEN @State IN (N'Completed', N'Skipped', N'Cancelled') THEN @now ELSE [CompletedAt] END,
           [ModifiedBy] = @ActorId, [ModifiedAt] = SYSDATETIMEOFFSET()
     WHERE [EntityId] = @EntityId AND [IsDeleted] = 0;
END;
GO
