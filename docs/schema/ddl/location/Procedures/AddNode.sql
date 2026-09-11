-- SCHEMA-DESIGN §3.1, §3.2 (decisions 80, 81); PROCEDURES.md #4.
-- Adds a node under a parent: refuses a type not allowed under the parent's type
-- (ref.LocationNodeTypeParent), refuses a subtype outside the type's enumeration list, and
-- computes Path / Depth from the parent (Path = the parent's Path + the parent's EntityId + '/';
-- a Region's Path is '/'). Writes through the generated location.Node_Add.
CREATE PROCEDURE [location].[AddNode]
    @NodeTypeCode NVARCHAR(40),
    @ParentEntityId UNIQUEIDENTIFIER = NULL,
    @Name NVARCHAR(200),
    @SubtypeCode NVARCHAR(40) = NULL,
    @SiblingOrder INT = 0,
    @Location GEOGRAPHY = NULL,
    @Extent GEOGRAPHY = NULL,
    @RegionSplitOfEntityId UNIQUEIDENTIFIER = NULL,
    @Notes NVARCHAR(MAX) = NULL,
    @ValidFrom DATETIMEOFFSET(7) = NULL,
    @ValidFromQuality TINYINT = 0,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,
    @EntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @RowId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM [ref].[LocationNodeType] WHERE [NodeTypeCode] = @NodeTypeCode AND [IsActive] = 1)
        THROW 50200, N'location.AddNode: unknown or inactive node type.', 1;

    -- A root type is one no other type may sit above: it has no row in ref.LocationNodeTypeParent as
    -- a child. That was Region alone until 2026-09-09, when Owner was added above Division and the
    -- test had to stop naming a type. Region is still rootable while the stations hang from it, and
    -- stops being so when they are re-parented onto their division (MIGRATION-FLOC-PLAN §10).
    DECLARE @isRoot BIT = CASE WHEN EXISTS (SELECT 1 FROM [ref].[LocationNodeTypeParent]
                                            WHERE [ChildNodeTypeCode] = @NodeTypeCode AND [IsActive] = 1)
                               THEN 0 ELSE 1 END;
    DECLARE @path NVARCHAR(900), @depth TINYINT;
    IF @isRoot = 1 AND @ParentEntityId IS NULL
    BEGIN
        SELECT @path = N'/', @depth = 0;
    END
    ELSE
    BEGIN
        IF @ParentEntityId IS NULL THROW 50202, N'location.AddNode: this node type has an allowed parent, so a parent is required (§3.2).', 1;
        DECLARE @parentType NVARCHAR(40), @parentPath NVARCHAR(900), @parentDepth TINYINT;
        SELECT @parentType = [NodeTypeCode], @parentPath = [Path], @parentDepth = [Depth]
        FROM [location].[vNode] WHERE [EntityId] = @ParentEntityId;
        IF @parentType IS NULL THROW 50203, N'location.AddNode: the parent is not a current node.', 1;
        IF NOT EXISTS (SELECT 1 FROM [ref].[LocationNodeTypeParent]
                       WHERE [ChildNodeTypeCode] = @NodeTypeCode AND [ParentNodeTypeCode] = @parentType AND [IsActive] = 1)
        BEGIN
            DECLARE @msg NVARCHAR(400) = CONCAT(N'location.AddNode: node type ', @NodeTypeCode, N' is not allowed under ', @parentType, N' (ref.LocationNodeTypeParent, §3.1).');
            THROW 50204, @msg, 1;
        END;
        IF LEN(@parentPath) + 38 > 900 THROW 50205, N'location.AddNode: the materialised path would exceed 900 characters.', 1;
        SELECT @path = CONCAT(@parentPath, CONVERT(NVARCHAR(36), @ParentEntityId), N'/'), @depth = @parentDepth + 1;
    END;

    -- subtype must be a value of the type's enumeration list when one is attached (§3.1)
    IF @SubtypeCode IS NOT NULL
    BEGIN
        DECLARE @listVersion UNIQUEIDENTIFIER;
        SELECT @listVersion = [SubtypeListDefinitionRowId] FROM [ref].[LocationNodeType] WHERE [NodeTypeCode] = @NodeTypeCode;
        IF @listVersion IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [config].[EnumerationValue]
                                                    WHERE [DefinitionVersionRowId] = @listVersion AND [ValueCode] = @SubtypeCode AND [IsDeleted] = 0)
        BEGIN
            DECLARE @msg2 NVARCHAR(400) = CONCAT(N'location.AddNode: subtype ', @SubtypeCode, N' is not in the enumeration attached to ', @NodeTypeCode, N'.');
            THROW 50206, @msg2, 1;
        END;
    END;

    EXEC [location].[Node_Add]
        @NodeTypeCode = @NodeTypeCode, @ParentEntityId = @ParentEntityId, @Path = @path, @Depth = @depth,
        @SiblingOrder = @SiblingOrder, @Name = @Name, @SubtypeCode = @SubtypeCode, @Location = @Location, @Extent = @Extent,
        @RegionSplitOfEntityId = @RegionSplitOfEntityId, @Notes = @Notes,
        @ValidFrom = @ValidFrom, @ValidFromQuality = @ValidFromQuality, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId,
        @EntityId = @EntityId OUTPUT, @RowId = @RowId OUTPUT;
END;
GO
