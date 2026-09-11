-- SCHEMA-DESIGN §3.3 (decision 81); PROCEDURES.md #4 (segment from/to maintenance).
-- Records that a linear node (Geometry = Linear: Raceway, RightOfWay) touches a point node at a
-- sequence position, then re-links the linear node's segments: the segments under the linear node,
-- in SiblingOrder, lie between consecutive touch points in Sequence order (the i-th segment runs
-- from the i-th adjacency to the (i+1)-th). A segment whose from/to changed gets a new fact version
-- through location.Segment_Revise. Implementation choice (recorded in STEPS.md step 3): the design
-- says the procedure maintains from/to when adjacency changes; the pairing rule by order is ours.
CREATE PROCEDURE [location].[AddAdjacency]
    @LinearNodeEntityId UNIQUEIDENTIFIER,
    @TouchedNodeEntityId UNIQUEIDENTIFIER,
    @Sequence INT,
    @Chainage DECIMAL(12,3) = NULL,
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
    SET @ValidFrom = ISNULL(@ValidFrom, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;

    IF NOT EXISTS (SELECT 1 FROM [location].[vNode] n JOIN [ref].[LocationNodeType] t ON t.[NodeTypeCode] = n.[NodeTypeCode]
                   WHERE n.[EntityId] = @LinearNodeEntityId AND t.[Geometry] = N'Linear')
        THROW 50209, N'location.AddAdjacency: the linear node must be a current node of a Linear type (§3.3).', 1;
    IF NOT EXISTS (SELECT 1 FROM [location].[vNode] WHERE [EntityId] = @TouchedNodeEntityId)
        THROW 50203, N'location.AddAdjacency: the touched node is not a current node.', 1;
    IF EXISTS (SELECT 1 FROM [location].[vAdjacency] WHERE [LinearNodeEntityId] = @LinearNodeEntityId AND [Sequence] = @Sequence)
        THROW 50210, N'location.AddAdjacency: the linear node already has a touch point at that sequence.', 1;

    BEGIN TRANSACTION;
    EXEC [location].[Adjacency_Add]
        @LinearNodeEntityId = @LinearNodeEntityId, @TouchedNodeEntityId = @TouchedNodeEntityId, @Sequence = @Sequence, @Chainage = @Chainage,
        @ValidFrom = @ValidFrom, @ValidFromQuality = @ValidFromQuality, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId,
        @EntityId = @EntityId OUTPUT, @RowId = @RowId OUTPUT;

    -- re-link segments between consecutive touch points
    DECLARE @pairs TABLE ([Ordinal] INT, [FromRowId] UNIQUEIDENTIFIER, [ToRowId] UNIQUEIDENTIFIER);
    INSERT @pairs
    SELECT ROW_NUMBER() OVER (ORDER BY a.[Sequence]), a.[RowId], LEAD(a.[RowId]) OVER (ORDER BY a.[Sequence])
    FROM [location].[vAdjacency] a WHERE a.[LinearNodeEntityId] = @LinearNodeEntityId;

    DECLARE @segEntity UNIQUEIDENTIFIER, @from UNIQUEIDENTIFIER, @to UNIQUEIDENTIFIER, @len DECIMAL(12,3);
    DECLARE segs CURSOR LOCAL FAST_FORWARD FOR
        SELECT s.[EntityId], p.[FromRowId], p.[ToRowId], s.[Length]
        FROM (SELECT s.*, ROW_NUMBER() OVER (ORDER BY n.[SiblingOrder], n.[Name]) AS [Ordinal]
              FROM [location].[vSegment] s JOIN [location].[vNode] n ON n.[EntityId] = s.[EntityId]
              WHERE n.[ParentEntityId] = @LinearNodeEntityId) s
        JOIN @pairs p ON p.[Ordinal] = s.[Ordinal]
        WHERE p.[ToRowId] IS NOT NULL
          AND (ISNULL(s.[FromAdjacencyRowId], '00000000-0000-0000-0000-000000000000') <> p.[FromRowId]
            OR ISNULL(s.[ToAdjacencyRowId],   '00000000-0000-0000-0000-000000000000') <> p.[ToRowId]);
    OPEN segs;
    FETCH NEXT FROM segs INTO @segEntity, @from, @to, @len;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC [location].[Segment_Revise] @EntityId = @segEntity, @FromAdjacencyRowId = @from, @ToAdjacencyRowId = @to, @Length = @len,
                                         @ValidFrom = @ValidFrom, @ValidFromQuality = @ValidFromQuality, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId;
        FETCH NEXT FROM segs INTO @segEntity, @from, @to, @len;
    END;
    CLOSE segs; DEALLOCATE segs;
    COMMIT TRANSACTION;
END;
GO
