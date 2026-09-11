-- SCHEMA-DESIGN §13.1 (187). The one way to say where a layer node is. Checks: the anchor exists for its
-- kind (Structure / Node = a location node of that type; RouteStep = a route step); when a line scope is
-- given, a Structure anchor must be a node on that line's route and a RouteStep anchor must belong to that
-- line's route (unresolved beats nearest-neighbour: an anchor that cannot be verified is refused, never
-- guessed); one primary endpoint per (node, line) — a new primary demotes the prior one in the same
-- transaction. Writes through the generated LayerNodeEndpoint_Add / _Revise.
CREATE PROCEDURE [network].[AddLayerNodeEndpoint]
    @LayerNodeEntityId UNIQUEIDENTIFIER,
    @AnchorKind NVARCHAR(40),                  -- Structure, RouteStep, Node
    @AnchorEntityId UNIQUEIDENTIFIER,
    @LineAssetEntityId UNIQUEIDENTIFIER = NULL,
    @IsPrimary BIT = 0,
    @SnapMethod NVARCHAR(20) = N'Manual',      -- Manual, Reconciled, Imported
    @Location GEOGRAPHY = NULL,
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
    SET @ValidFrom = ISNULL(@ValidFrom, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM [network].[vLayerNode] WHERE [EntityId] = @LayerNodeEntityId)
        THROW 50360, N'network.AddLayerNodeEndpoint: the layer node is not current.', 1;
    IF @AnchorKind NOT IN (N'Structure', N'RouteStep', N'Node')
        THROW 50361, N'network.AddLayerNodeEndpoint: AnchorKind is Structure, RouteStep or Node (§13.1).', 1;

    DECLARE @ok BIT = 0, @route UNIQUEIDENTIFIER;
    IF @LineAssetEntityId IS NOT NULL
    BEGIN
        SELECT @route = [EntityId] FROM [location].[vRoute] WHERE [OwnerAssetEntityId] = @LineAssetEntityId AND [RouteKind] = N'Line';
        IF @route IS NULL THROW 50362, N'network.AddLayerNodeEndpoint: the scoped line has no route; the endpoint cannot be verified against it.', 1;
    END;
    IF @AnchorKind = N'Structure'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [location].[vNode] WHERE [EntityId] = @AnchorEntityId AND [NodeTypeCode] = N'Structure')
            THROW 50363, N'network.AddLayerNodeEndpoint: the anchor is not a current Structure node.', 1;
        SET @ok = CASE WHEN @route IS NULL OR EXISTS (SELECT 1 FROM [location].[vRouteStep] WHERE [RouteEntityId] = @route AND [NodeEntityId] = @AnchorEntityId) THEN 1 ELSE 0 END;
    END
    ELSE IF @AnchorKind = N'RouteStep'
    BEGIN
        DECLARE @stepRoute UNIQUEIDENTIFIER = (SELECT [RouteEntityId] FROM [location].[vRouteStep] WHERE [EntityId] = @AnchorEntityId);
        IF @stepRoute IS NULL THROW 50363, N'network.AddLayerNodeEndpoint: the anchor is not a current route step.', 1;
        SET @ok = CASE WHEN @route IS NULL OR @stepRoute = @route THEN 1 ELSE 0 END;
    END
    ELSE
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [location].[vNode] WHERE [EntityId] = @AnchorEntityId)
            THROW 50363, N'network.AddLayerNodeEndpoint: the anchor is not a current location node.', 1;
        SET @ok = 1;    -- a station or equipment position is not on a route; the line scope records intent only
    END;
    IF @ok = 0 THROW 50364, N'network.AddLayerNodeEndpoint: the anchor is not on the scoped line''s route; an endpoint that cannot be verified is refused, not guessed (§13.1).', 1;

    BEGIN TRANSACTION;
    IF @IsPrimary = 1
    BEGIN
        -- demote the prior primary for this (node, line): a new fact version through _Revise
        DECLARE @pe UNIQUEIDENTIFIER, @pk NVARCHAR(40), @pa UNIQUEIDENTIFIER, @pm NVARCHAR(20), @pl GEOGRAPHY, @pn NVARCHAR(MAX);
        SELECT @pe = [EntityId], @pk = [AnchorKind], @pa = [AnchorEntityId], @pm = [SnapMethod], @pl = [Location], @pn = [Notes]
        FROM [network].[vLayerNodeEndpoint]
        WHERE [LayerNodeEntityId] = @LayerNodeEntityId AND [IsPrimary] = 1
          AND ISNULL([LineAssetEntityId], '00000000-0000-0000-0000-000000000000') = ISNULL(@LineAssetEntityId, '00000000-0000-0000-0000-000000000000');
        IF @pe IS NOT NULL
            EXEC [network].[LayerNodeEndpoint_Revise] @EntityId = @pe, @LayerNodeEntityId = @LayerNodeEntityId, @AnchorKind = @pk, @AnchorEntityId = @pa,
                 @LineAssetEntityId = @LineAssetEntityId, @IsPrimary = 0, @SnapMethod = @pm, @Location = @pl, @Notes = @pn,
                 @ValidFrom = @ValidFrom, @ValidFromQuality = @ValidFromQuality, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId;
    END;
    EXEC [network].[LayerNodeEndpoint_Add] @LayerNodeEntityId = @LayerNodeEntityId, @AnchorKind = @AnchorKind, @AnchorEntityId = @AnchorEntityId,
         @LineAssetEntityId = @LineAssetEntityId, @IsPrimary = @IsPrimary, @SnapMethod = @SnapMethod, @Location = @Location, @Notes = @Notes,
         @ValidFrom = @ValidFrom, @ValidFromQuality = @ValidFromQuality, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId,
         @EntityId = @EntityId OUTPUT, @RowId = @RowId OUTPUT;
    COMMIT TRANSACTION;
END;
GO
