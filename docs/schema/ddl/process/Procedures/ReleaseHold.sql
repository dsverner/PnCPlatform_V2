-- PROCEDURE-ENGINE §3 hold, §4 HoldInstance, #69 (W4). Releases an open hold: Condition (the interpreter found
-- hold.until true), Manual (a person in the release role, with a reason, logged), or Expired (the sweep found the hold
-- past maxDuration — the block completes with Outcome Expired and the expiry is logged; the obligation of #69 waits
-- for the rule engine, decision #111). The block completes and the interpreter advances past it.
CREATE PROCEDURE [process].[ReleaseHold]
    @BlockInstanceEntityId UNIQUEIDENTIFIER,
    @ReleaseBasis NVARCHAR(20),
    @Reason NVARCHAR(400) = NULL,
    @At DATETIMEOFFSET(7) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = ISNULL(@At, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    IF @ReleaseBasis NOT IN (N'Condition', N'Manual', N'Expired') THROW 50151, N'process.ReleaseHold: ReleaseBasis is Condition, Manual or Expired.', 1;
    IF @ReleaseBasis = N'Manual' AND NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL THROW 50155, N'process.ReleaseHold: a manual release needs a reason.', 1;
    DECLARE @hold UNIQUEIDENTIFIER, @holdRow UNIQUEIDENTIFIER, @hReason NVARCHAR(400), @heldAt DATETIMEOFFSET(7), @heldBy UNIQUEIDENTIFIER, @instance UNIQUEIDENTIFIER;
    SELECT TOP (1) @hold = h.[EntityId], @holdRow = h.[RowId], @hReason = h.[Reason], @heldAt = h.[HeldAt], @heldBy = h.[HeldByActorId]
    FROM [process].[HoldInstance] h WHERE h.[BlockInstanceEntityId] = @BlockInstanceEntityId AND h.[IsDeleted] = 0 AND h.[ReleasedAt] IS NULL ORDER BY h.[RowSeq] DESC;
    IF @hold IS NULL THROW 50156, N'process.ReleaseHold: no open hold on that block.', 1;
    SELECT @instance = [ProcedureInstanceEntityId] FROM [process].[BlockInstance] WHERE [EntityId] = @BlockInstanceEntityId AND [IsDeleted] = 0;
    BEGIN TRANSACTION;
    EXEC [process].[HoldInstance_Update] @RowId = @holdRow, @BlockInstanceEntityId = @BlockInstanceEntityId, @Reason = @hReason, @HeldAt = @heldAt, @HeldByActorId = @heldBy,
         @ReleasedAt = @now, @ReleasedByActorId = @ActorId, @ReleaseBasis = @ReleaseBasis, @ActorId = @ActorId;
    DECLARE @outcome NVARCHAR(40) = CASE @ReleaseBasis WHEN N'Expired' THEN N'Expired' ELSE N'Released' END;
    EXEC [process].[SetBlockState] @EntityId = @BlockInstanceEntityId, @State = N'Completed', @Outcome = @outcome, @At = @now, @ActorId = @ActorId;
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"hold-released","basis":"', @ReleaseBasis, N'","reason":', CASE WHEN @Reason IS NULL THEN N'null' ELSE CONCAT(N'"', STRING_ESCAPE(@Reason, 'json'), N'"') END, N',"block":"', LOWER(CONVERT(NVARCHAR(36), @BlockInstanceEntityId)), N'"}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'process', @SubjectTable = N'HoldInstance', @SubjectEntityId = @instance, @ActorId = @ActorId, @Detail = @detail;
    COMMIT TRANSACTION;
END;
GO
