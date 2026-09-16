-- #170 (2026-09-16): a scheme and the station it sits at — its device members' positions, up the location tree to the Station
-- (Node.Path is the ancestors' chain, the node's own id excluded). One row per scheme and station (a scheme whose devices
-- sit at two stations shows twice — a data finding). Hand-written read model, base tables in the current-row form (#169).
CREATE VIEW [scheme].[vSchemeStation] AS
SELECT DISTINCT sc.[EntityId] AS [SchemeEntityId], sc.[Name] AS [SchemeName], sc.[Status] AS [SchemeStatus],
       stn.[EntityId] AS [StationNodeEntityId], stn.[Name] AS [StationName]
FROM [scheme].[Scheme] sc
JOIN [scheme].[SchemeMember] sm ON sm.[SchemeEntityId] = sc.[EntityId] AND sm.[ValidTo] IS NULL AND sm.[IsDeleted] = 0 AND sm.[MemberKind] = N'Asset'
JOIN [asset].[Placement] pl ON pl.[AssetEntityId] = sm.[MemberEntityId] AND pl.[ValidTo] IS NULL AND pl.[IsDeleted] = 0 AND pl.[NodeEntityId] IS NOT NULL
JOIN [location].[Node] pos ON pos.[EntityId] = pl.[NodeEntityId] AND pos.[ValidTo] IS NULL AND pos.[IsDeleted] = 0
JOIN [location].[Node] stn ON stn.[NodeTypeCode] = N'Station' AND stn.[ValidTo] IS NULL AND stn.[IsDeleted] = 0 AND pos.[Path] LIKE stn.[Path] + CONVERT(NVARCHAR(36), stn.[EntityId]) + N'/%'
WHERE sc.[ValidTo] IS NULL AND sc.[IsDeleted] = 0;
GO
GRANT SELECT ON [scheme].[vSchemeStation] TO [app_execute];
GO
