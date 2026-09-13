-- W7 (decisions #56, #141). An open legacy change (an M row) lands as a running SETTINGS_CHANGE_REQUEST / SETTINGS_CHANGE
-- pair at the COMPLETION block: the request workflow started and moved to InProgress by the migration run (no person's
-- role to check — @MigrationRunId on process.Transition), the procedure started with the versions pinned as any run's
-- are, and then every block and step before COMPLETION set Skipped with the outcome 'Migrated' ("migrated — not
-- performed in this platform"); COMPLETION Running; its two branches from the legacy tracks:
--   Complete → Completed / Done      NA → Skipped / NotApplicable      Change In Progress (or unknown) → Running
-- A Running branch is then the interpreter's: the sweep continues it live (the drawings call starts its child run, the
-- baseline step becomes Ready). Nothing about steps 1–12 is invented (#56). The software track is not a branch (#58):
-- its legacy status is a note on the request, written by the importer. Every row carries the run.
--   50175 the request has no SETTINGS_CHANGE_REQUEST instance   50176 no root run   50177 the run has no COMPLETION block
CREATE PROCEDURE [process].[LandMigratedInstance]
    @WorkRequestEntityId UNIQUEIDENTIFIER,
    @DocumentationStatus NVARCHAR(50) = NULL,      -- the legacy Relay Document Management status
    @DatabaseStatus NVARCHAR(50) = NULL,           -- the legacy Setting Database Management status
    @DocumentationAt DATETIMEOFFSET(7) = NULL,     -- W8 (#149): the legacy track row's Date — a Complete / NA branch completes then, not at the capture instant
    @DatabaseAt DATETIMEOFFSET(7) = NULL,
    @At DATETIMEOFFSET(7) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER,
    @WorkflowInstanceEntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @ProcedureInstanceEntityId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = ISNULL(@At, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;

    BEGIN TRANSACTION;
    -- the request workflow: Raised, then Start → InProgress; the onEnter effect starts the procedure, pinned
    EXEC [process].[StartWorkflow] @WorkflowKey = N'SETTINGS_CHANGE_REQUEST', @SubjectKind = N'WorkRequest', @SubjectEntityId = @WorkRequestEntityId,
         @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @WorkflowInstanceEntityId OUTPUT;
    IF @WorkflowInstanceEntityId IS NULL THROW 50175, N'process.LandMigratedInstance: the request workflow did not start.', 1;
    DECLARE @to NVARCHAR(40), @tid BIGINT;
    EXEC [process].[Transition] @WorkflowInstanceEntityId = @WorkflowInstanceEntityId, @TransitionName = N'Start', @Reason = N'migrated: open in the legacy system at cutover',
         @At = @now, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @ToState = @to OUTPUT, @TransitionId = @tid OUTPUT;
    SELECT TOP (1) @ProcedureInstanceEntityId = [EntityId] FROM [process].[ProcedureInstance]
    WHERE [WorkflowInstanceEntityId] = @WorkflowInstanceEntityId AND [ParentInstanceEntityId] IS NULL AND [IsDeleted] = 0 ORDER BY [RowSeq] DESC;
    IF @ProcedureInstanceEntityId IS NULL THROW 50176, N'process.LandMigratedInstance: entering InProgress started no SETTINGS_CHANGE run.', 1;

    -- the materialised tree: MAIN (root), its items, COMPLETION and the two branches with their bodies
    DECLARE @completion UNIQUEIDENTIFIER = (SELECT TOP (1) [EntityId] FROM [process].[BlockInstance] WHERE [ProcedureInstanceEntityId] = @ProcedureInstanceEntityId AND [BlockPath] = N'MAIN/COMPLETION' AND [IsDeleted] = 0);
    IF @completion IS NULL THROW 50177, N'process.LandMigratedInstance: the run has no MAIN/COMPLETION block.', 1;
    DECLARE @root UNIQUEIDENTIFIER = (SELECT TOP (1) [EntityId] FROM [process].[BlockInstance] WHERE [ProcedureInstanceEntityId] = @ProcedureInstanceEntityId AND [BlockPath] = N'MAIN' AND [BlockKind] = N'sequence' AND [IsDeleted] = 0);

    -- steps 1–12: every step whose block is not under COMPLETION → Skipped / Migrated; then every such block → Skipped / Migrated
    DECLARE @sid UNIQUEIDENTIFIER;
    DECLARE st CURSOR LOCAL FAST_FORWARD FOR
        SELECT s.[EntityId] FROM [process].[StepInstance] s JOIN [process].[BlockInstance] b ON b.[EntityId] = s.[BlockInstanceEntityId]
        WHERE b.[ProcedureInstanceEntityId] = @ProcedureInstanceEntityId AND b.[IsDeleted] = 0 AND s.[IsDeleted] = 0 AND s.[State] = N'Pending'
          AND b.[BlockPath] NOT LIKE N'MAIN/COMPLETION%';
    OPEN st; FETCH NEXT FROM st INTO @sid;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC [process].[SetStepState] @EntityId = @sid, @State = N'Skipped', @Outcome = N'Migrated', @ActorId = @ActorId;
        FETCH NEXT FROM st INTO @sid;
    END
    CLOSE st; DEALLOCATE st;
    DECLARE @bid UNIQUEIDENTIFIER;
    DECLARE bl CURSOR LOCAL FAST_FORWARD FOR
        SELECT b.[EntityId] FROM [process].[BlockInstance] b
        WHERE b.[ProcedureInstanceEntityId] = @ProcedureInstanceEntityId AND b.[IsDeleted] = 0 AND b.[State] = N'Pending'
          AND b.[BlockPath] NOT LIKE N'MAIN/COMPLETION%' AND b.[EntityId] <> @root
        ORDER BY b.[RowSeq] DESC;   -- children before parents
    OPEN bl; FETCH NEXT FROM bl INTO @bid;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC [process].[SetBlockState] @EntityId = @bid, @State = N'Skipped', @Outcome = N'Migrated', @At = @now, @ActorId = @ActorId;
        FETCH NEXT FROM bl INTO @bid;
    END
    CLOSE bl; DEALLOCATE bl;

    -- COMPLETION Running; each branch from its legacy track
    EXEC [process].[SetBlockState] @EntityId = @completion, @State = N'Running', @At = @now, @ActorId = @ActorId;
    DECLARE @branchPath NVARCHAR(400), @status NVARCHAR(50), @branch UNIQUEIDENTIFIER, @inner UNIQUEIDENTIFIER, @trackAt DATETIMEOFFSET(7);
    DECLARE br CURSOR LOCAL FAST_FORWARD FOR SELECT * FROM (VALUES (N'MAIN/COMPLETION/DOCUMENTATION', @DocumentationStatus, @DocumentationAt), (N'MAIN/COMPLETION/DATABASE', @DatabaseStatus, @DatabaseAt)) v ([Path], [Status], [At]);
    OPEN br; FETCH NEXT FROM br INTO @branchPath, @status, @trackAt;
    SET @trackAt = ISNULL(@trackAt, @now);
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT TOP (1) @branch = [EntityId] FROM [process].[BlockInstance] WHERE [ProcedureInstanceEntityId] = @ProcedureInstanceEntityId AND [BlockPath] = @branchPath AND [BlockKind] = N'branch' AND [IsDeleted] = 0;
        IF @branch IS NOT NULL
        BEGIN
            IF @status = N'Complete'
            BEGIN
                -- the body (a call or a step) and its step are done in the legacy system: Skipped / Migrated, the branch Completed / Done
                DECLARE cs CURSOR LOCAL FAST_FORWARD FOR
                    SELECT s.[EntityId] FROM [process].[StepInstance] s JOIN [process].[BlockInstance] b ON b.[EntityId] = s.[BlockInstanceEntityId]
                    WHERE b.[ProcedureInstanceEntityId] = @ProcedureInstanceEntityId AND b.[BlockPath] LIKE @branchPath + N'/%' AND s.[State] = N'Pending' AND s.[IsDeleted] = 0;
                OPEN cs; FETCH NEXT FROM cs INTO @sid;
                WHILE @@FETCH_STATUS = 0 BEGIN EXEC [process].[SetStepState] @EntityId = @sid, @State = N'Skipped', @Outcome = N'Migrated', @ActorId = @ActorId; FETCH NEXT FROM cs INTO @sid; END
                CLOSE cs; DEALLOCATE cs;
                DECLARE cb CURSOR LOCAL FAST_FORWARD FOR
                    SELECT b.[EntityId] FROM [process].[BlockInstance] b WHERE b.[ProcedureInstanceEntityId] = @ProcedureInstanceEntityId AND b.[BlockPath] LIKE @branchPath + N'/%' AND b.[State] = N'Pending' AND b.[IsDeleted] = 0 ORDER BY b.[RowSeq] DESC;
                OPEN cb; FETCH NEXT FROM cb INTO @inner;
                WHILE @@FETCH_STATUS = 0 BEGIN EXEC [process].[SetBlockState] @EntityId = @inner, @State = N'Skipped', @Outcome = N'Migrated', @At = @now, @ActorId = @ActorId; FETCH NEXT FROM cb INTO @inner; END
                CLOSE cb; DEALLOCATE cb;
                EXEC [process].[SetBlockState] @EntityId = @branch, @State = N'Running', @At = @trackAt, @ActorId = @ActorId;
                EXEC [process].[SetBlockState] @EntityId = @branch, @State = N'Completed', @Outcome = N'Done', @At = @trackAt, @ActorId = @ActorId;
            END
            ELSE IF @status = N'NA'
            BEGIN
                DECLARE ns CURSOR LOCAL FAST_FORWARD FOR
                    SELECT s.[EntityId] FROM [process].[StepInstance] s JOIN [process].[BlockInstance] b ON b.[EntityId] = s.[BlockInstanceEntityId]
                    WHERE b.[ProcedureInstanceEntityId] = @ProcedureInstanceEntityId AND b.[BlockPath] LIKE @branchPath + N'/%' AND s.[State] = N'Pending' AND s.[IsDeleted] = 0;
                OPEN ns; FETCH NEXT FROM ns INTO @sid;
                WHILE @@FETCH_STATUS = 0 BEGIN EXEC [process].[SetStepState] @EntityId = @sid, @State = N'Skipped', @Outcome = N'NotApplicable', @ActorId = @ActorId; FETCH NEXT FROM ns INTO @sid; END
                CLOSE ns; DEALLOCATE ns;
                DECLARE nb CURSOR LOCAL FAST_FORWARD FOR
                    SELECT b.[EntityId] FROM [process].[BlockInstance] b WHERE b.[ProcedureInstanceEntityId] = @ProcedureInstanceEntityId AND b.[BlockPath] LIKE @branchPath + N'/%' AND b.[State] = N'Pending' AND b.[IsDeleted] = 0 ORDER BY b.[RowSeq] DESC;
                OPEN nb; FETCH NEXT FROM nb INTO @inner;
                WHILE @@FETCH_STATUS = 0 BEGIN EXEC [process].[SetBlockState] @EntityId = @inner, @State = N'Skipped', @Outcome = N'NotApplicable', @At = @now, @ActorId = @ActorId; FETCH NEXT FROM nb INTO @inner; END
                CLOSE nb; DEALLOCATE nb;
                EXEC [process].[SetBlockState] @EntityId = @branch, @State = N'Skipped', @Outcome = N'NotApplicable', @At = @now, @ActorId = @ActorId;
            END
            ELSE
                EXEC [process].[SetBlockState] @EntityId = @branch, @State = N'Running', @At = @now, @ActorId = @ActorId;   -- Change In Progress, or unknown: the platform continues it
        END
        FETCH NEXT FROM br INTO @branchPath, @status, @trackAt; SET @trackAt = ISNULL(@trackAt, @now);
    END
    CLOSE br; DEALLOCATE br;
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"migrated-landed","documentation":"', ISNULL(STRING_ESCAPE(@DocumentationStatus, 'json'), N''), N'","database":"', ISNULL(STRING_ESCAPE(@DatabaseStatus, 'json'), N''), N'"}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'process', @SubjectTable = N'ProcedureInstance', @SubjectEntityId = @ProcedureInstanceEntityId, @ActorId = @ActorId, @Detail = @detail;
    COMMIT TRANSACTION;
END;
GO
