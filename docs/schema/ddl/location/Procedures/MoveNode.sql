-- SCHEMA-DESIGN §3.1, §3.2 (decisions 80, 81); PROCEDURES.md #4.
-- Re-parents a node: refuses a parent type the node's type is not allowed under, refuses a move
-- into the node's own subtree, and rewrites Path / Depth for the node and every descendant, each
-- as a new fact version through location.Node_Revise (the prior version is closed at @ValidFrom).
--
-- #175 (2026-09-17): FlocCode is recomputed for the moved node and its whole subtree beside Path and Depth, because a
-- node's FLOC is composed from its parent's and the parent has just changed. Each chain is recomputed through
-- location.fComposeFloc rather than swapping one text prefix for another: under that rule a chain RESTARTS at an
-- uncoded node, so a descendant's FLOC need not begin with the moved node's old FLOC at all. The platform never
-- invents a missing segment.
-- Code itself is carried forward unchanged — a move does not rename anything. It has to be passed explicitly: the
-- generated Node_Revise defaults @Code to NULL, so a move that did not name it would silently wipe every code in the
-- subtree, and the damage would surface only much later as a wrong tag read off a screen.
CREATE PROCEDURE [location].[MoveNode]
    @EntityId UNIQUEIDENTIFIER,
    @NewParentEntityId UNIQUEIDENTIFIER,
    @SiblingOrder INT = NULL,                 -- NULL keeps the current value
    @ValidFrom DATETIMEOFFSET(7) = NULL,
    @ValidFromQuality TINYINT = 0,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,
    @WorkRequestEntityId UNIQUEIDENTIFIER = NULL,   -- the job this move was done under
    @RowId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ValidFrom = ISNULL(@ValidFrom, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;

    DECLARE @type NVARCHAR(40), @oldPath NVARCHAR(900), @oldDepth TINYINT, @ownCode NVARCHAR(40);
    SELECT @type = [NodeTypeCode], @oldPath = [Path], @oldDepth = [Depth], @ownCode = [Code] FROM [location].[vNode] WHERE [EntityId] = @EntityId;
    IF @type IS NULL THROW 50207, N'location.MoveNode: the node is not a current node.', 1;
    IF NOT EXISTS (SELECT 1 FROM [ref].[LocationNodeTypeParent] WHERE [ChildNodeTypeCode] = @type AND [IsActive] = 1)
        THROW 50201, N'location.MoveNode: this node type has no allowed parent, so it cannot be moved (§3.2).', 1;

    DECLARE @parentType NVARCHAR(40), @parentPath NVARCHAR(900), @parentDepth TINYINT, @parentFloc NVARCHAR(400);
    SELECT @parentType = [NodeTypeCode], @parentPath = [Path], @parentDepth = [Depth], @parentFloc = [FlocCode] FROM [location].[vNode] WHERE [EntityId] = @NewParentEntityId;
    IF @parentType IS NULL THROW 50203, N'location.MoveNode: the parent is not a current node.', 1;
    IF NOT EXISTS (SELECT 1 FROM [ref].[LocationNodeTypeParent]
                   WHERE [ChildNodeTypeCode] = @type AND [ParentNodeTypeCode] = @parentType AND [IsActive] = 1)
    BEGIN
        DECLARE @msg NVARCHAR(400) = CONCAT(N'location.MoveNode: node type ', @type, N' is not allowed under ', @parentType, N' (ref.LocationNodeTypeParent, §3.1).');
        THROW 50204, @msg, 1;
    END;
    DECLARE @selfPrefix NVARCHAR(900) = CONCAT(@oldPath, CONVERT(NVARCHAR(36), @EntityId), N'/');
    IF @NewParentEntityId = @EntityId OR @parentPath LIKE @selfPrefix + N'%'
        THROW 50208, N'location.MoveNode: a node cannot be moved under itself or its own descendant.', 1;

    DECLARE @newPath NVARCHAR(900) = CONCAT(@parentPath, CONVERT(NVARCHAR(36), @NewParentEntityId), N'/');
    DECLARE @newDepth INT = @parentDepth + 1;
    DECLARE @maxDescendantDepth INT = (SELECT ISNULL(MAX([Depth]), @oldDepth) FROM [location].[vNode] WHERE [Path] LIKE @selfPrefix + N'%');
    IF @newDepth + (@maxDescendantDepth - @oldDepth) > 255 THROW 50205, N'location.MoveNode: the subtree would exceed the maximum depth.', 1;
    IF LEN(@newPath) + (SELECT ISNULL(MAX(LEN([Path])), LEN(@selfPrefix)) FROM [location].[vNode] WHERE [Path] LIKE @selfPrefix + N'%') - LEN(@selfPrefix) + 38 > 900
        THROW 50205, N'location.MoveNode: a materialised path in the subtree would exceed 900 characters.', 1;

    -- #175: the subtree's new FLOCs, worked out before anything is written. The subtree is scoped by the Path prefix
    -- so IX_Node_Path seeks it (#172); the chain is then recomputed node by node from the moved node's new FLOC.
    DECLARE @newFloc NVARCHAR(400) = [location].[fComposeFloc](@parentFloc, @ownCode);
    DECLARE @subtree TABLE ([EntityId] UNIQUEIDENTIFIER PRIMARY KEY, [ParentEntityId] UNIQUEIDENTIFIER, [Code] NVARCHAR(40));
    INSERT @subtree ([EntityId], [ParentEntityId], [Code])
    SELECT [EntityId], [ParentEntityId], [Code] FROM [location].[Node]
    WHERE [ValidTo] IS NULL AND [IsDeleted] = 0 AND [Path] LIKE @selfPrefix + N'%';
    DECLARE @flocs TABLE ([EntityId] UNIQUEIDENTIFIER PRIMARY KEY, [FlocCode] NVARCHAR(400));
    WITH chain AS (
        SELECT [EntityId] = @EntityId, [FlocCode] = CAST(@newFloc AS NVARCHAR(400))
        UNION ALL
        SELECT s.[EntityId], [location].[fComposeFloc](c.[FlocCode], s.[Code])
        FROM @subtree s JOIN chain c ON c.[EntityId] = s.[ParentEntityId])
    INSERT @flocs ([EntityId], [FlocCode]) SELECT [EntityId], [FlocCode] FROM chain OPTION (MAXRECURSION 0);

    BEGIN TRANSACTION;
    -- the node itself; other columns carried forward from the current version
    DECLARE @sib INT, @name NVARCHAR(200), @sub NVARCHAR(40), @loc GEOGRAPHY, @ext GEOGRAPHY, @split UNIQUEIDENTIFIER, @notes NVARCHAR(MAX);
    SELECT @sib = [SiblingOrder], @name = [Name], @sub = [SubtypeCode], @loc = [Location], @ext = [Extent], @split = [RegionSplitOfEntityId], @notes = [Notes]
    FROM [location].[vNode] WHERE [EntityId] = @EntityId;
    EXEC [location].[Node_Revise]
        @EntityId = @EntityId, @NodeTypeCode = @type, @ParentEntityId = @NewParentEntityId, @Path = @newPath, @Depth = @newDepth,
        @SiblingOrder = @sib, @Name = @name, @SubtypeCode = @sub, @Location = @loc, @Extent = @ext, @RegionSplitOfEntityId = @split, @Notes = @notes,
        @Code = @ownCode, @FlocCode = @newFloc,
        @WorkRequestEntityId = @WorkRequestEntityId,
        @ValidFrom = @ValidFrom, @ValidFromQuality = @ValidFromQuality, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @RowId = @RowId OUTPUT;
    IF @SiblingOrder IS NOT NULL AND @SiblingOrder <> @sib
        UPDATE [location].[Node] SET [SiblingOrder] = @SiblingOrder WHERE [RowId] = @RowId;

    -- descendants, shallowest first: the old prefix is replaced by the new one
    DECLARE @newSelfPrefix NVARCHAR(900) = CONCAT(@newPath, CONVERT(NVARCHAR(36), @EntityId), N'/');
    DECLARE @dEntity UNIQUEIDENTIFIER, @dType NVARCHAR(40), @dParent UNIQUEIDENTIFIER, @dPath NVARCHAR(900), @dDepth TINYINT;
    DECLARE @dSib INT, @dName NVARCHAR(200), @dSub NVARCHAR(40), @dLoc GEOGRAPHY, @dExt GEOGRAPHY, @dSplit UNIQUEIDENTIFIER, @dNotes NVARCHAR(MAX), @dCode NVARCHAR(40);
    DECLARE descendants CURSOR LOCAL FAST_FORWARD FOR
        SELECT [EntityId], [NodeTypeCode], [ParentEntityId], [Path], [Depth], [SiblingOrder], [Name], [SubtypeCode], [Location], [Extent], [RegionSplitOfEntityId], [Notes], [Code]
        FROM [location].[vNode] WHERE [Path] LIKE @selfPrefix + N'%' ORDER BY [Depth], [SiblingOrder];
    OPEN descendants;
    FETCH NEXT FROM descendants INTO @dEntity, @dType, @dParent, @dPath, @dDepth, @dSib, @dName, @dSub, @dLoc, @dExt, @dSplit, @dNotes, @dCode;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @rewritten NVARCHAR(900) = CONCAT(@newSelfPrefix, SUBSTRING(@dPath, LEN(@selfPrefix) + 1, 900));
        DECLARE @rewrittenDepth INT = @dDepth - @oldDepth + @newDepth;
        DECLARE @dFloc NVARCHAR(400) = (SELECT [FlocCode] FROM @flocs WHERE [EntityId] = @dEntity);
        EXEC [location].[Node_Revise]
            @EntityId = @dEntity, @NodeTypeCode = @dType, @ParentEntityId = @dParent, @Path = @rewritten, @Depth = @rewrittenDepth,
            @SiblingOrder = @dSib, @Name = @dName, @SubtypeCode = @dSub, @Location = @dLoc, @Extent = @dExt, @RegionSplitOfEntityId = @dSplit, @Notes = @dNotes,
            @Code = @dCode, @FlocCode = @dFloc,
            @WorkRequestEntityId = @WorkRequestEntityId,
            @ValidFrom = @ValidFrom, @ValidFromQuality = @ValidFromQuality, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId;
        FETCH NEXT FROM descendants INTO @dEntity, @dType, @dParent, @dPath, @dDepth, @dSib, @dName, @dSub, @dLoc, @dExt, @dSplit, @dNotes, @dCode;
    END;
    CLOSE descendants; DEALLOCATE descendants;
    COMMIT TRANSACTION;
END;
GO
