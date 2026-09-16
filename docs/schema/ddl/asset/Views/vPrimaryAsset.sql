-- #170 (2026-09-16): the primary assets — the non-device assets of the Primary class — with their terminals (the station a
-- transformer, bus or breaker stands at; the two stations a line joins — asset.AssetTerminal), the stations their protecting
-- schemes sit at (a cross-check: a scheme protecting a line from a station that is not one of its terminals is a data error),
-- and their applicability classifications summarised; for the scheme's "protects" chooser, the primary-asset record and the
-- device sheet's "protects … via …" line. Hand-written read model: base tables in the current-row form (#169).
CREATE VIEW [asset].[vPrimaryAsset] AS
SELECT a.[EntityId],
       a.[Name],
       a.[AssetTypeCode],
       t.[Name]                     AS [AssetTypeName],
       a.[Status],
       a.[VoltageClassCode],
       a.[Notes],
       t1.[StationNodeEntityId]     AS [Terminal1NodeEntityId],
       t1.[StationName]             AS [Terminal1StationName],
       t2.[StationNodeEntityId]     AS [Terminal2NodeEntityId],
       t2.[StationName]             AS [Terminal2StationName],
       [Stations] = CASE WHEN t1.[StationName] IS NULL THEN t2.[StationName] WHEN t2.[StationName] IS NULL THEN t1.[StationName] ELSE CONCAT(t1.[StationName], N' – ', t2.[StationName]) END,
       pf.[ProtectedFrom],
       cls.[Classifications],
       a.[RowSeq]
FROM [asset].[Asset] a
JOIN [ref].[AssetType] t ON t.[AssetTypeCode] = a.[AssetTypeCode] AND t.[AssetClassCode] = N'Primary' AND t.[IsDevice] = 0
OUTER APPLY (SELECT TOP (1) at.[StationNodeEntityId], n.[Name] AS [StationName]
             FROM [asset].[AssetTerminal] at JOIN [location].[Node] n ON n.[EntityId] = at.[StationNodeEntityId] AND n.[ValidTo] IS NULL AND n.[IsDeleted] = 0
             WHERE at.[ValidTo] IS NULL AND at.[IsDeleted] = 0 AND at.[AssetEntityId] = a.[EntityId] AND at.[TerminalNo] = 1 ORDER BY at.[RowSeq] DESC) t1
OUTER APPLY (SELECT TOP (1) at.[StationNodeEntityId], n.[Name] AS [StationName]
             FROM [asset].[AssetTerminal] at JOIN [location].[Node] n ON n.[EntityId] = at.[StationNodeEntityId] AND n.[ValidTo] IS NULL AND n.[IsDeleted] = 0
             WHERE at.[ValidTo] IS NULL AND at.[IsDeleted] = 0 AND at.[AssetEntityId] = a.[EntityId] AND at.[TerminalNo] = 2 ORDER BY at.[RowSeq] DESC) t2
OUTER APPLY (SELECT STRING_AGG(CONCAT(c.[ClassificationKindCode], N'=', c.[ClassificationValue]), N'; ') WITHIN GROUP (ORDER BY c.[ClassificationKindCode]) AS [Classifications]
             FROM [asset].[Classification] c
             WHERE c.[ValidTo] IS NULL AND c.[IsDeleted] = 0 AND c.[SubjectKind] = N'Asset' AND c.[SubjectEntityId] = a.[EntityId]) cls
-- the stations of the schemes that protect it (their device members' positions, up the tree to the Station; Node.Path is the
-- ancestors' chain, the node's own id excluded)
OUTER APPLY (SELECT STRING_AGG(x.[StationName], N', ') WITHIN GROUP (ORDER BY x.[StationName]) AS [ProtectedFrom]
             FROM (SELECT DISTINCT stn.[Name] AS [StationName]
                   FROM [scheme].[SchemeProtects] sp
                   JOIN [scheme].[SchemeMember] sm ON sm.[SchemeEntityId] = sp.[SchemeEntityId] AND sm.[ValidTo] IS NULL AND sm.[IsDeleted] = 0 AND sm.[MemberKind] = N'Asset'
                   JOIN [asset].[Placement] pl ON pl.[AssetEntityId] = sm.[MemberEntityId] AND pl.[ValidTo] IS NULL AND pl.[IsDeleted] = 0 AND pl.[NodeEntityId] IS NOT NULL
                   JOIN [location].[Node] pos ON pos.[EntityId] = pl.[NodeEntityId] AND pos.[ValidTo] IS NULL AND pos.[IsDeleted] = 0
                   JOIN [location].[Node] stn ON stn.[NodeTypeCode] = N'Station' AND stn.[ValidTo] IS NULL AND stn.[IsDeleted] = 0 AND pos.[Path] LIKE stn.[Path] + CONVERT(NVARCHAR(36), stn.[EntityId]) + N'/%'
                   WHERE sp.[PrimaryAssetEntityId] = a.[EntityId] AND sp.[ValidTo] IS NULL AND sp.[IsDeleted] = 0) x) pf
WHERE a.[ValidTo] IS NULL AND a.[IsDeleted] = 0;
GO
GRANT SELECT ON [asset].[vPrimaryAsset] TO [app_execute];
GO
