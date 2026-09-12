-- PROCEDURE-ENGINE §4 (W4, decision #106). Creates the process.BlockInstance rows (and a Pending process.StepInstance
-- per step) for one block of an instance's pinned document and everything under it, except the bodies of nested
-- foreach and repeat blocks, which materialise per member / per pass when the interpreter activates them (their own
-- row is created, Pending). Called by StartProcedure for the root and by the interpreter for each foreach member
-- (@IterationKey = the member's entity id, @IncludeRoot = 0) and each repeat pass (@Pass, @IncludeRoot = 0).
-- Every row starts Pending; the interpreter sets states (SetBlockState / SetStepState). The document is the pinned
-- version's canonical text; blocks are matched by path and kind (an id-less inner sequence shares its parent's path).
CREATE PROCEDURE [process].[MaterialiseBlock]
    @ProcedureInstanceEntityId UNIQUEIDENTIFIER,
    @BlockPath NVARCHAR(400),
    @BlockKind NVARCHAR(20),
    @ParentBlockInstanceEntityId UNIQUEIDENTIFIER = NULL,
    @IterationKey NVARCHAR(100) = NULL,
    @Pass INT = 1,
    @MemberSubjectKind NVARCHAR(40) = NULL,
    @MemberSubjectEntityId UNIQUEIDENTIFIER = NULL,
    @IncludeRoot BIT = 1,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @RootEntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @Created INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;

    DECLARE @doc NVARCHAR(MAX), @version UNIQUEIDENTIFIER;
    SELECT @version = i.[DefinitionVersionRowId], @doc = dv.[PayloadText]
    FROM [process].[ProcedureInstance] i JOIN [config].[DefinitionVersion] dv ON dv.[RowId] = i.[DefinitionVersionRowId]
    WHERE i.[EntityId] = @ProcedureInstanceEntityId AND i.[IsDeleted] = 0;
    IF @doc IS NULL THROW 50143, N'process.MaterialiseBlock: no live procedure instance with that id.', 1;

    SELECT BlockJson, Kind, BlockId, BlockPath, SortKey INTO #t FROM [process].[fProcedureBlocks](@doc);
    DECLARE @rootSort NVARCHAR(400);
    SELECT TOP (1) @rootSort = SortKey FROM #t WHERE BlockPath = @BlockPath AND Kind = @BlockKind ORDER BY SortKey;
    IF @rootSort IS NULL THROW 50144, N'process.MaterialiseBlock: the document has no such block (path and kind).', 1;

    -- the rows to create: the root (optionally) and its descendants, minus anything inside a nested foreach/repeat body
    SELECT t.*, NEWID() AS EntityId,
           CASE WHEN LEN(t.SortKey) > 3 THEN LEFT(t.SortKey, LEN(t.SortKey) - 4) ELSE NULL END AS ParentSort
    INTO #m
    FROM #t t
    WHERE (t.SortKey = @rootSort AND @IncludeRoot = 1) OR t.SortKey LIKE @rootSort + N'.%'
      AND NOT EXISTS (SELECT 1 FROM #t f WHERE f.Kind IN (N'foreach', N'repeat') AND f.SortKey <> @rootSort
                      AND f.SortKey LIKE @rootSort + N'.%' AND t.SortKey LIKE f.SortKey + N'.%');

    BEGIN TRANSACTION;
    INSERT [process].[BlockInstanceRegistry] ([EntityId]) SELECT EntityId FROM #m;
    INSERT [process].[BlockInstance] ([EntityId], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt],
        [ProcedureInstanceEntityId], [ParentBlockInstanceEntityId], [BlockPath], [BlockKind], [IterationKey], [Pass], [MemberSubjectKind], [MemberSubjectEntityId], [State])
    SELECT m.EntityId, @ActorId, @now, @ActorId, @now,
        @ProcedureInstanceEntityId, ISNULL(p.EntityId, @ParentBlockInstanceEntityId), m.BlockPath, m.Kind, @IterationKey, @Pass, @MemberSubjectKind, @MemberSubjectEntityId, N'Pending'
    FROM #m m LEFT JOIN #m p ON p.SortKey = m.ParentSort
    ORDER BY m.SortKey;

    -- one Pending step instance per step block, assigned the projected role
    SELECT NEWID() AS StepEntityId, m.EntityId AS BlockEntityId, m.BlockId, ps.[RoleCode]
    INTO #s
    FROM #m m LEFT JOIN [process].[ProcedureStep] ps ON ps.[DefinitionVersionRowId] = @version AND ps.[StepId] = m.BlockId AND ps.[IsDeleted] = 0
    WHERE m.Kind = N'step';
    IF EXISTS (SELECT 1 FROM #s WHERE RoleCode IS NULL) THROW 50145, N'process.MaterialiseBlock: a step has no projected role (the version was not projected).', 1;
    INSERT [process].[StepInstanceRegistry] ([EntityId]) SELECT StepEntityId FROM #s;
    INSERT [process].[StepInstance] ([EntityId], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt], [BlockInstanceEntityId], [StepId], [State], [AssignedRoleCode])
    SELECT StepEntityId, @ActorId, @now, @ActorId, @now, BlockEntityId, BlockId, N'Pending', RoleCode FROM #s;

    SELECT @RootEntityId = EntityId FROM #m WHERE SortKey = @rootSort;
    SET @Created = (SELECT COUNT(*) FROM #m);
    COMMIT TRANSACTION;
END;
GO
