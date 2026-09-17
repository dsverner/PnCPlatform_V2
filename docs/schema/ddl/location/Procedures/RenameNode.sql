-- #174 (2026-09-17): rename a location node, or change its subtype or notes, from the location page. The generated
-- [location].[Node_Revise] takes every column including Path and Depth, which a client must not compute — a wrong Path
-- silently detaches a subtree from every scoped read (security.fReadableSubjects matches on Path). This procedure keeps
-- the node where it is and changes only what a person may name: the name, the subtype and the notes. Moving a node is
-- [location].[MoveNode]'s job, which recomputes the Path of the node and of everything under it.
-- The subtype is checked the way [location].[AddNode] checks it: against the type's enumeration list when it has one.
-- Over HTTP: Node.Modify on the node.
CREATE PROCEDURE [location].[RenameNode]
    @EntityId UNIQUEIDENTIFIER,
    @Name NVARCHAR(200),
    @SubtypeCode NVARCHAR(40) = NULL,
    @Notes NVARCHAR(MAX) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    SET @Name = NULLIF(LTRIM(RTRIM(@Name)), N'');
    IF @Name IS NULL THROW 50210, N'location.RenameNode: a node needs a name.', 1;

    DECLARE @typeCode NVARCHAR(40), @parent UNIQUEIDENTIFIER, @path NVARCHAR(900), @depth TINYINT, @order INT,
            @loc GEOGRAPHY, @extent GEOGRAPHY, @split UNIQUEIDENTIFIER, @wr UNIQUEIDENTIFIER;
    SELECT TOP (1) @typeCode = [NodeTypeCode], @parent = [ParentEntityId], @path = [Path], @depth = [Depth], @order = [SiblingOrder],
                   @loc = [Location], @extent = [Extent], @split = [RegionSplitOfEntityId], @wr = [WorkRequestEntityId]
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

    EXEC [location].[Node_Revise] @EntityId = @EntityId, @NodeTypeCode = @typeCode, @ParentEntityId = @parent, @Path = @path, @Depth = @depth,
         @SiblingOrder = @order, @Name = @Name, @SubtypeCode = @SubtypeCode, @Location = @loc, @Extent = @extent,
         @RegionSplitOfEntityId = @split, @WorkRequestEntityId = @wr, @Notes = @Notes, @ActorId = @ActorId;
END;
GO
GRANT EXECUTE ON [location].[RenameNode] TO [app_execute];
GO
