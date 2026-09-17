-- #171 (2026-09-16): the station a node belongs to — the node itself when it is a Station, otherwise the nearest Station
-- ancestor. Node.Path holds the ancestors' chain but not the node's own id (#94), so the walk hops ParentEntityId, up to
-- four levels, exactly as document.vSettingsRecord does for a device's position (position → panel → up to three more).
-- Current rows only (ValidTo IS NULL AND IsDeleted = 0, the filtered indexes' own form). NULL when no Station is reached.
CREATE FUNCTION [location].[fStationOf] (@nodeEntityId UNIQUEIDENTIFIER)
RETURNS UNIQUEIDENTIFIER
AS
BEGIN
    IF @nodeEntityId IS NULL RETURN NULL;
    DECLARE @station UNIQUEIDENTIFIER;
    SELECT TOP (1) @station = x.[EntityId]
    FROM (SELECT 0 AS [Level], n0.[EntityId], n0.[NodeTypeCode] FROM [location].[Node] n0
          WHERE n0.[EntityId] = @nodeEntityId AND n0.[ValidTo] IS NULL AND n0.[IsDeleted] = 0
          UNION ALL
          SELECT 1, n1.[EntityId], n1.[NodeTypeCode] FROM [location].[Node] n0
          JOIN [location].[Node] n1 ON n1.[EntityId] = n0.[ParentEntityId] AND n1.[ValidTo] IS NULL AND n1.[IsDeleted] = 0
          WHERE n0.[EntityId] = @nodeEntityId AND n0.[ValidTo] IS NULL AND n0.[IsDeleted] = 0
          UNION ALL
          SELECT 2, n2.[EntityId], n2.[NodeTypeCode] FROM [location].[Node] n0
          JOIN [location].[Node] n1 ON n1.[EntityId] = n0.[ParentEntityId] AND n1.[ValidTo] IS NULL AND n1.[IsDeleted] = 0
          JOIN [location].[Node] n2 ON n2.[EntityId] = n1.[ParentEntityId] AND n2.[ValidTo] IS NULL AND n2.[IsDeleted] = 0
          WHERE n0.[EntityId] = @nodeEntityId AND n0.[ValidTo] IS NULL AND n0.[IsDeleted] = 0
          UNION ALL
          SELECT 3, n3.[EntityId], n3.[NodeTypeCode] FROM [location].[Node] n0
          JOIN [location].[Node] n1 ON n1.[EntityId] = n0.[ParentEntityId] AND n1.[ValidTo] IS NULL AND n1.[IsDeleted] = 0
          JOIN [location].[Node] n2 ON n2.[EntityId] = n1.[ParentEntityId] AND n2.[ValidTo] IS NULL AND n2.[IsDeleted] = 0
          JOIN [location].[Node] n3 ON n3.[EntityId] = n2.[ParentEntityId] AND n3.[ValidTo] IS NULL AND n3.[IsDeleted] = 0
          WHERE n0.[EntityId] = @nodeEntityId AND n0.[ValidTo] IS NULL AND n0.[IsDeleted] = 0
          UNION ALL
          SELECT 4, n4.[EntityId], n4.[NodeTypeCode] FROM [location].[Node] n0
          JOIN [location].[Node] n1 ON n1.[EntityId] = n0.[ParentEntityId] AND n1.[ValidTo] IS NULL AND n1.[IsDeleted] = 0
          JOIN [location].[Node] n2 ON n2.[EntityId] = n1.[ParentEntityId] AND n2.[ValidTo] IS NULL AND n2.[IsDeleted] = 0
          JOIN [location].[Node] n3 ON n3.[EntityId] = n2.[ParentEntityId] AND n3.[ValidTo] IS NULL AND n3.[IsDeleted] = 0
          JOIN [location].[Node] n4 ON n4.[EntityId] = n3.[ParentEntityId] AND n4.[ValidTo] IS NULL AND n4.[IsDeleted] = 0
          WHERE n0.[EntityId] = @nodeEntityId AND n0.[ValidTo] IS NULL AND n0.[IsDeleted] = 0) x
    WHERE x.[NodeTypeCode] = N'Station'
    ORDER BY x.[Level];
    RETURN @station;
END;
GO
