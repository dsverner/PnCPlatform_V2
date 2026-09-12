-- PROCEDURE-ENGINE §4 (W4). Ends a procedure instance: Completed with an outcome (the document's outcomes; default
-- Completed) or Cancelled with a reason. A child run (a call block) completes its parent's call block with the same
-- outcome so the parent's interpreter advances past it. 50175 already ended; 50155 a cancellation needs a reason.
CREATE PROCEDURE [process].[CompleteInstance]
    @ProcedureInstanceEntityId UNIQUEIDENTIFIER,
    @State NVARCHAR(40) = N'Completed',
    @Outcome NVARCHAR(40) = NULL,
    @Reason NVARCHAR(400) = NULL,
    @At DATETIMEOFFSET(7) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = ISNULL(@At, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    IF @State NOT IN (N'Completed', N'Cancelled') THROW 50151, N'process.CompleteInstance: State is Completed or Cancelled.', 1;
    IF @State = N'Cancelled' AND NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL THROW 50155, N'process.CompleteInstance: a cancellation needs a reason.', 1;
    DECLARE @cur NVARCHAR(40), @parent UNIQUEIDENTIFIER, @callPath NVARCHAR(400), @version UNIQUEIDENTIFIER;
    SELECT @cur = [State], @parent = [ParentInstanceEntityId], @callPath = [CallBlockPath], @version = [DefinitionVersionRowId]
    FROM [process].[ProcedureInstance] WHERE [EntityId] = @ProcedureInstanceEntityId AND [IsDeleted] = 0;
    IF @cur IS NULL THROW 50143, N'process.CompleteInstance: no live procedure instance with that id.', 1;
    IF @cur IN (N'Completed', N'Cancelled') THROW 50175, N'process.CompleteInstance: the instance has already ended.', 1;
    SET @Outcome = ISNULL(@Outcome, CASE @State WHEN N'Completed' THEN N'Completed' ELSE N'Cancelled' END);
    BEGIN TRANSACTION;
    UPDATE [process].[ProcedureInstance] SET [State] = @State, [Outcome] = @Outcome, [CompletedAt] = @now, [ModifiedBy] = @ActorId, [ModifiedAt] = SYSDATETIMEOFFSET()
    WHERE [EntityId] = @ProcedureInstanceEntityId AND [IsDeleted] = 0;
    IF @State = N'Cancelled'
    BEGIN
        UPDATE [process].[BlockInstance] SET [State] = N'Cancelled', [Outcome] = N'Cancelled', [CompletedAt] = @now, [ModifiedBy] = @ActorId, [ModifiedAt] = SYSDATETIMEOFFSET()
        WHERE [ProcedureInstanceEntityId] = @ProcedureInstanceEntityId AND [IsDeleted] = 0 AND [State] NOT IN (N'Completed', N'Skipped', N'Cancelled');
        UPDATE s SET s.[State] = N'Skipped', s.[Outcome] = N'Cancelled', s.[ModifiedBy] = @ActorId, s.[ModifiedAt] = SYSDATETIMEOFFSET()
        FROM [process].[StepInstance] s JOIN [process].[BlockInstance] b ON b.[EntityId] = s.[BlockInstanceEntityId]
        WHERE b.[ProcedureInstanceEntityId] = @ProcedureInstanceEntityId AND s.[IsDeleted] = 0 AND s.[State] NOT IN (N'Committed', N'Skipped', N'Varied');
    END
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"procedure-', LOWER(@State), N'","outcome":"', STRING_ESCAPE(@Outcome, 'json'), N'","reason":', CASE WHEN @Reason IS NULL THEN N'null' ELSE CONCAT(N'"', STRING_ESCAPE(@Reason, 'json'), N'"') END, N'}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'process', @SubjectTable = N'ProcedureInstance', @SubjectEntityId = @ProcedureInstanceEntityId,
         @DefinitionVersionRowId = @version, @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now;
    -- a child run completes its parent's call block
    IF @parent IS NOT NULL
    BEGIN
        DECLARE @callBlock UNIQUEIDENTIFIER;
        SELECT TOP (1) @callBlock = [EntityId] FROM [process].[BlockInstance]
        WHERE [ProcedureInstanceEntityId] = @parent AND [BlockPath] = @callPath AND [BlockKind] = N'call' AND [IsDeleted] = 0 AND [State] NOT IN (N'Completed', N'Skipped', N'Cancelled')
        ORDER BY [RowSeq] DESC;
        DECLARE @blockState NVARCHAR(40) = CASE WHEN @State = N'Completed' THEN N'Completed' ELSE N'Cancelled' END;
        IF @callBlock IS NOT NULL
            EXEC [process].[SetBlockState] @EntityId = @callBlock, @State = @blockState, @Outcome = @Outcome, @At = @now, @ActorId = @ActorId;
    END
    COMMIT TRANSACTION;
END;
GO
