-- SCHEMA-DESIGN §3.1, §3.2 (decisions 80, 81); PROCEDURES.md #4.
-- Re-parents a node: refuses a parent type the node's type is not allowed under, refuses a move
-- into the node's own subtree, and rewrites Path / Depth for the node and every descendant, each
-- as a new fact version through location.Node_Revise (the prior version is closed at @ValidFrom).
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

    DECLARE @type NVARCHAR(40), @oldPath NVARCHAR(900), @oldDepth TINYINT;
    SELECT @type = [NodeTypeCode], @oldPath = [Path], @oldDepth = [Depth] FROM [location].[vNode] WHERE [EntityId] = @EntityId;
    IF @type IS NULL THROW 50207, N'location.MoveNode: the node is not a current node.', 1;
    IF NOT EXISTS (SELECT 1 FROM [ref].[LocationNodeTypeParent] WHERE [ChildNodeTypeCode] = @type AND [IsActive] = 1)
        THROW 50201, N'location.MoveNode: this node type has no allowed parent, so it cannot be moved (§3.2).', 1;

    DECLARE @parentType NVARCHAR(40), @parentPath NVARCHAR(900), @parentDepth TINYINT;
    SELECT @parentType = [NodeTypeCode], @parentPath = [Path], @parentDepth = [Depth] FROM [location].[vNode] WHERE [EntityId] = @NewParentEntityId;
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

    BEGIN TRANSACTION;
    -- the node itself; other columns carried forward from the current version
    DECLARE @sib INT, @name NVARCHAR(200), @sub NVARCHAR(40), @loc GEOGRAPHY, @ext GEOGRAPHY, @split UNIQUEIDENTIFIER, @notes NVARCHAR(MAX);
    SELECT @sib = [SiblingOrder], @name = [Name], @sub = [SubtypeCode], @loc = [Location], @ext = [Extent], @split = [RegionSplitOfEntityId], @notes = [Notes]
    FROM [location].[vNode] WHERE [EntityId] = @EntityId;
    EXEC [location].[Node_Revise]
        @EntityId = @EntityId, @NodeTypeCode = @type, @ParentEntityId = @NewParentEntityId, @Path = @newPath, @Depth = @newDepth,
        @SiblingOrder = @sib, @Name = @name, @SubtypeCode = @sub, @Location = @loc, @Extent = @ext, @RegionSplitOfEntityId = @split, @Notes = @notes,
        @WorkRequestEntityId = @WorkRequestEntityId,
        @ValidFrom = @ValidFrom, @ValidFromQuality = @ValidFromQuality, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @RowId = @RowId OUTPUT;
    IF @SiblingOrder IS NOT NULL AND @SiblingOrder <> @sib
        UPDATE [location].[Node] SET [SiblingOrder] = @SiblingOrder WHERE [RowId] = @RowId;

    -- descendants, shallowest first: the old prefix is replaced by the new one
    DECLARE @newSelfPrefix NVARCHAR(900) = CONCAT(@newPath, CONVERT(NVARCHAR(36), @EntityId), N'/');
    DECLARE @dEntity UNIQUEIDENTIFIER, @dType NVARCHAR(40), @dParent UNIQUEIDENTIFIER, @dPath NVARCHAR(900), @dDepth TINYINT;
    DECLARE @dSib INT, @dName NVARCHAR(200), @dSub NVARCHAR(40), @dLoc GEOGRAPHY, @dExt GEOGRAPHY, @dSplit UNIQUEIDENTIFIER, @dNotes NVARCHAR(MAX);
    DECLARE descendants CURSOR LOCAL FAST_FORWARD FOR
        SELECT [EntityId], [NodeTypeCode], [ParentEntityId], [Path], [Depth], [SiblingOrder], [Name], [SubtypeCode], [Location], [Extent], [RegionSplitOfEntityId], [Notes]
        FROM [location].[vNode] WHERE [Path] LIKE @selfPrefix + N'%' ORDER BY [Depth], [SiblingOrder];
    OPEN descendants;
    FETCH NEXT FROM descendants INTO @dEntity, @dType, @dParent, @dPath, @dDepth, @dSib, @dName, @dSub, @dLoc, @dExt, @dSplit, @dNotes;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @rewritten NVARCHAR(900) = CONCAT(@newSelfPrefix, SUBSTRING(@dPath, LEN(@selfPrefix) + 1, 900));
        DECLARE @rewrittenDepth INT = @dDepth - @oldDepth + @newDepth;
        EXEC [location].[Node_Revise]
            @EntityId = @dEntity, @NodeTypeCode = @dType, @ParentEntityId = @dParent, @Path = @rewritten, @Depth = @rewrittenDepth,
            @SiblingOrder = @dSib, @Name = @dName, @SubtypeCode = @dSub, @Location = @dLoc, @Extent = @dExt, @RegionSplitOfEntityId = @dSplit, @Notes = @dNotes,
            @WorkRequestEntityId = @WorkRequestEntityId,
            @ValidFrom = @ValidFrom, @ValidFromQuality = @ValidFromQuality, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId;
        FETCH NEXT FROM descendants INTO @dEntity, @dType, @dParent, @dPath, @dDepth, @dSib, @dName, @dSub, @dLoc, @dExt, @dSplit, @dNotes;
    END;
    CLOSE descendants; DEALLOCATE descendants;
    COMMIT TRANSACTION;
END;
GO
