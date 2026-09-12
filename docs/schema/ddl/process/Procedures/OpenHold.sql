-- PROCEDURE-ENGINE §3 hold, §4 HoldInstance (W4). A hold block activates: its block goes Held and a HoldInstance row
-- records why and since when. Released by process.ReleaseHold (a condition, a person, or expiry).
CREATE PROCEDURE [process].[OpenHold]
    @BlockInstanceEntityId UNIQUEIDENTIFIER,
    @Reason NVARCHAR(400),
    @At DATETIMEOFFSET(7) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @EntityId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = ISNULL(@At, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM [process].[BlockInstance] WHERE [EntityId] = @BlockInstanceEntityId AND [IsDeleted] = 0 AND [BlockKind] = N'hold' AND [State] IN (N'Pending', N'Running'))
        THROW 50153, N'process.OpenHold: not a pending or running hold block.', 1;
    IF EXISTS (SELECT 1 FROM [process].[HoldInstance] WHERE [BlockInstanceEntityId] = @BlockInstanceEntityId AND [IsDeleted] = 0 AND [ReleasedAt] IS NULL)
        THROW 50154, N'process.OpenHold: the hold is already open.', 1;
    BEGIN TRANSACTION;
    EXEC [process].[HoldInstance_Add] @BlockInstanceEntityId = @BlockInstanceEntityId, @Reason = @Reason, @HeldAt = @now, @HeldByActorId = @ActorId, @ActorId = @ActorId, @EntityId = @EntityId OUTPUT;
    EXEC [process].[SetBlockState] @EntityId = @BlockInstanceEntityId, @State = N'Held', @At = @now, @ActorId = @ActorId;
    COMMIT TRANSACTION;
END;
GO
