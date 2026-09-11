-- SCHEMA-DESIGN §13.1 (188). A layer branch's physical path, derived and never stored: the route steps of
-- the branch's line between the from-node's and the to-node's primary endpoints scoped to that line
-- (a Structure anchor resolves to that structure's step; a RouteStep anchor is the step). One row per
-- step, in walking order (either direction along the route). A branch whose line or either endpoint is
-- unresolved yields no rows — unresolved beats nearest-neighbour (Phase57 tombstone).
CREATE VIEW [network].[vLayerBranchPath] AS
WITH ends AS (
    SELECT b.[EntityId] AS [LayerBranchEntityId], b.[LineAssetEntityId], r.[EntityId] AS [RouteEntityId],
           fs.[Sequence] AS [FromSequence], ts.[Sequence] AS [ToSequence]
    FROM [network].[vLayerBranch] b
    JOIN [location].[vRoute] r ON r.[OwnerAssetEntityId] = b.[LineAssetEntityId] AND r.[RouteKind] = N'Line'
    JOIN [network].[vLayerNodeEndpoint] fe ON fe.[LayerNodeEntityId] = b.[FromNodeEntityId] AND fe.[IsPrimary] = 1 AND fe.[LineAssetEntityId] = b.[LineAssetEntityId]
    JOIN [network].[vLayerNodeEndpoint] te ON te.[LayerNodeEntityId] = b.[ToNodeEntityId]   AND te.[IsPrimary] = 1 AND te.[LineAssetEntityId] = b.[LineAssetEntityId]
    JOIN [location].[vRouteStep] fs ON fs.[RouteEntityId] = r.[EntityId]
         AND ((fe.[AnchorKind] = N'Structure' AND fs.[NodeEntityId] = fe.[AnchorEntityId]) OR (fe.[AnchorKind] = N'RouteStep' AND fs.[EntityId] = fe.[AnchorEntityId]))
    JOIN [location].[vRouteStep] ts ON ts.[RouteEntityId] = r.[EntityId]
         AND ((te.[AnchorKind] = N'Structure' AND ts.[NodeEntityId] = te.[AnchorEntityId]) OR (te.[AnchorKind] = N'RouteStep' AND ts.[EntityId] = te.[AnchorEntityId]))
)
SELECT e.[LayerBranchEntityId], e.[LineAssetEntityId], e.[RouteEntityId],
       [WalkOrder] = ROW_NUMBER() OVER (PARTITION BY e.[LayerBranchEntityId] ORDER BY CASE WHEN e.[FromSequence] <= e.[ToSequence] THEN s.[Sequence] ELSE -s.[Sequence] END),
       s.[EntityId] AS [RouteStepEntityId], s.[RowId] AS [RouteStepRowId], s.[Sequence], s.[NodeEntityId]
FROM ends e
JOIN [location].[vRouteStep] s ON s.[RouteEntityId] = e.[RouteEntityId]
     AND s.[Sequence] BETWEEN CASE WHEN e.[FromSequence] <= e.[ToSequence] THEN e.[FromSequence] ELSE e.[ToSequence] END
                          AND CASE WHEN e.[FromSequence] <= e.[ToSequence] THEN e.[ToSequence] ELSE e.[FromSequence] END;
GO
GRANT SELECT ON [network].[vLayerBranchPath] TO [app_execute];
GO
