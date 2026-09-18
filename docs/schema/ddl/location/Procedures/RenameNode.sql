-- #174 (2026-09-17): rename a location node, or change its code, subtype or notes, from the location page. The generated
-- [location].[Node_Revise] takes every column including Path and Depth, which a client must not compute — a wrong Path
-- silently detaches a subtree from every scoped read (security.fReadableSubjects matches on Path). This procedure keeps
-- the node where it is and changes only what a person may name: the name, the code, the subtype and the notes. Moving a
-- node is [location].[MoveNode]'s job, which recomputes the Path of the node and of everything under it.
-- The subtype is checked the way [location].[AddNode] checks it: against the type's enumeration list when it has one.
--
-- #175 (2026-09-17): @Code. Omitted (NULL) KEEPS the node's existing code — the screens already call this procedure to
-- save Name, Subtype and Notes without touching the code, and src/PnC.Api/Data/SqlSession.cs treats a JSON null as a
-- parameter not given, so a client cannot send NULL. An EMPTY or all-whitespace string CLEARS it. The difference is
-- invisible from outside, which is why it is written down here. Anything else is checked by location.AssertNodeCode.
--
-- When the code actually changes, the FLOC of the node AND of every descendant is rewritten, because a descendant's
-- FLOC is composed from this one. The rewrite recomputes each chain through location.fComposeFloc rather than swapping
-- one text prefix for another: under that rule a chain RESTARTS at an uncoded node, so a descendant's FLOC need not
-- begin with this node's old FLOC at all (and until a code is set anywhere, there is no old prefix to match). The
-- platform never invents a missing segment — withdraw Y230's code and its transformer reads T3, not TN-4403-T3.
-- The descendants' rows are updated in place rather than versioned: FlocCode is derived, like Path, and nothing about
-- a descendant itself changed; system versioning still records it, and [location].[MoveNode] already updates in place
-- for the same kind of reason. A move is a fact about each node, so MoveNode versions its subtree; a code change here
-- is not.
-- Over HTTP: Node.Modify on the node.
CREATE PROCEDURE [location].[RenameNode]
    @EntityId UNIQUEIDENTIFIER,
    @Name NVARCHAR(200),
    @SubtypeCode NVARCHAR(40) = NULL,
    @Notes NVARCHAR(MAX) = NULL,
    @Code NVARCHAR(40) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    SET @Name = NULLIF(LTRIM(RTRIM(@Name)), N'');
    IF @Name IS NULL THROW 50210, N'location.RenameNode: a node needs a name.', 1;

    DECLARE @typeCode NVARCHAR(40), @parent UNIQUEIDENTIFIER, @path NVARCHAR(900), @depth TINYINT, @order INT,
            @loc GEOGRAPHY, @extent GEOGRAPHY, @split UNIQUEIDENTIFIER, @wr UNIQUEIDENTIFIER,
            @oldCode NVARCHAR(40), @oldFloc NVARCHAR(400);
    SELECT TOP (1) @typeCode = [NodeTypeCode], @parent = [ParentEntityId], @path = [Path], @depth = [Depth], @order = [SiblingOrder],
                   @loc = [Location], @extent = [Extent], @split = [RegionSplitOfEntityId], @wr = [WorkRequestEntityId],
                   @oldCode = [Code], @oldFloc = [FlocCode]
    FROM [location].[Node]
    WHERE [EntityId] = @EntityId AND [ValidTo] IS NULL AND [IsDeleted] = 0
    ORDER BY [RowSeq] DESC;
    IF @typeCode IS NULL THROW 50211, N'location.RenameNode: the node is not a current node.', 1;

    SET @SubtypeCode = NULLIF(LTRIM(RTRIM(@SubtypeCode)), N'');
    IF @SubtypeCode IS NOT NULL
    BEGIN
        DECLARE @listVersion UNIQUEIDENTIFIER =
            (SELECT TOP (1) dv.[RowId] FROM [ref].[LocationNodeType] t
             JOIN [config].[DefinitionVersion] dv ON dv.[RowId] = t.[SubtypeListDefinitionRowId] AND dv.[IsDeleted] = 0
             WHERE t.[NodeTypeCode] = @typeCode);
        IF @listVersion IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [config].[EnumerationValue]
                                                    WHERE [DefinitionVersionRowId] = @listVersion AND [ValueCode] = @SubtypeCode AND [IsDeleted] = 0)
        BEGIN
            DECLARE @m NVARCHAR(400) = N'location.RenameNode: ' + @SubtypeCode + N' is not a subtype of a ' + @typeCode + N'.';
            THROW 50212, @m, 1;
        END
    END

    -- #175: omitted keeps, empty clears, anything else is checked and then set
    DECLARE @newCode NVARCHAR(40) = @oldCode, @newFloc NVARCHAR(400) = @oldFloc, @codeChanged BIT = 0;
    IF @Code IS NOT NULL
    BEGIN
        EXEC [location].[AssertNodeCode] @Caller = N'location.RenameNode', @Code = @Code OUTPUT, @ParentEntityId = @parent, @SelfEntityId = @EntityId, @NodeTypeCode = @typeCode;
        SET @newCode = NULLIF(@Code, N'');
        -- NULL-safe comparison: INTERSECT treats two NULLs as equal, which is what "the code did not change" means
        IF NOT EXISTS (SELECT @newCode INTERSECT SELECT @oldCode) SET @codeChanged = 1;
        IF @codeChanged = 1
        BEGIN
            DECLARE @parentFloc NVARCHAR(400) =
                (SELECT TOP (1) [FlocCode] FROM [location].[Node]
                 WHERE [EntityId] = @parent AND [ValidTo] IS NULL AND [IsDeleted] = 0 ORDER BY [RowSeq] DESC);
            SET @newFloc = [location].[fComposeFloc](@parentFloc, @newCode);
        END
    END

    BEGIN TRANSACTION;
    EXEC [location].[Node_Revise] @EntityId = @EntityId, @NodeTypeCode = @typeCode, @ParentEntityId = @parent, @Path = @path, @Depth = @depth,
         @SiblingOrder = @order, @Name = @Name, @SubtypeCode = @SubtypeCode, @Location = @loc, @Extent = @extent,
         @RegionSplitOfEntityId = @split, @WorkRequestEntityId = @wr, @Notes = @Notes,
         @Code = @newCode, @FlocCode = @newFloc, @ActorId = @ActorId;

    IF @codeChanged = 1
    BEGIN
        -- the subtree, scoped by the Path prefix so IX_Node_Path seeks it (#172), then each chain recomputed
        DECLARE @selfPrefix NVARCHAR(900) = CONCAT(@path, CONVERT(NVARCHAR(36), @EntityId), N'/');
        DECLARE @subtree TABLE ([EntityId] UNIQUEIDENTIFIER PRIMARY KEY, [ParentEntityId] UNIQUEIDENTIFIER, [Code] NVARCHAR(40));
        INSERT @subtree ([EntityId], [ParentEntityId], [Code])
        SELECT [EntityId], [ParentEntityId], [Code] FROM [location].[Node]
        WHERE [ValidTo] IS NULL AND [IsDeleted] = 0 AND [Path] LIKE @selfPrefix + N'%';

        WITH chain AS (
            SELECT [EntityId] = @EntityId, [FlocCode] = CAST(@newFloc AS NVARCHAR(400))
            UNION ALL
            SELECT s.[EntityId], [location].[fComposeFloc](c.[FlocCode], s.[Code])
            FROM @subtree s JOIN chain c ON c.[EntityId] = s.[ParentEntityId])
        UPDATE n SET [FlocCode] = c.[FlocCode], [ModifiedBy] = @ActorId, [ModifiedAt] = @now
        FROM [location].[Node] n JOIN chain c ON c.[EntityId] = n.[EntityId]
        WHERE n.[ValidTo] IS NULL AND n.[IsDeleted] = 0 AND n.[EntityId] <> @EntityId
        OPTION (MAXRECURSION 0);
    END
    COMMIT TRANSACTION;
END;
GO
GRANT EXECUTE ON [location].[RenameNode] TO [app_execute];
GO
