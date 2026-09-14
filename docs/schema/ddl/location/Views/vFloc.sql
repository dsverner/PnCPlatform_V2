-- Hand-written read model (W6, decisions #57, #127). The legacy Location / Protected Asset / Protection Function view as
-- a projection of the FLOC tree (FR-7.2): one row per device position (DevicePosition, MeteringPosition,
-- NetworkSwitchPosition) with its panel and station, the device installed there now (asset.Placement Installed — at most
-- one, UX_Placement_InstalledAtNode), its model and firmware, the protection functions commissioned under the position
-- (ANSI codes, principal first) and the schemes those functions belong to. Browse by station, panel, model or asset type
-- = an equality filter on this view; by scheme = location.vFlocScheme; the tree itself = location.vNodeTree.
-- The station is found by hopping ParentEntityId (Path holds ancestors only, #94): panel, then up to three more levels
-- (Building / Room / Station — the allowed parents of Seed_ref_LocationNodeTypeParent.sql).
-- Subject column NodeEntityId = the position (read scope by the Node family: the grant's subtree). The installed asset is
-- InstalledAssetEntityId on purpose: a column named AssetEntityId would be picked as the subject and an empty position
-- (NULL) would vanish from every read, Global grants included.
-- Correlated lookups read the base tables with the current-row predicate in the filtered indexes' own form (ValidTo IS NULL AND IsDeleted = 0): an OUTER APPLY ... TOP (1) against a
-- generated current view (ROW_NUMBER over the entity) is evaluated over the whole table per outer row — 26 s a page on the
-- migrated estate, measured in W7 — where the same lookup on the base table seeks. The joins to the current views stay.
CREATE VIEW [location].[vFloc] AS
SELECT dp.[RowSeq],
       dp.[EntityId]                AS [NodeEntityId],
       dp.[NodeTypeCode]            AS [PositionTypeCode],
       dp.[Name]                    AS [PositionName],
       dp.[SubtypeCode],
       dp.[Path], dp.[Depth], dp.[SiblingOrder],
       pnl.[EntityId]               AS [PanelNodeEntityId],
       pnl.[Name]                   AS [PanelName],
       slot.[KeyValue]              AS [PanelSlot],
       st.[StationEntityId]         AS [StationNodeEntityId],
       st.[StationName],
       stno.[KeyValue]              AS [StationNumber],
       pl.[PlacementEntityId]       AS [InstalledPlacementEntityId],
       pl.[AssetEntityId]           AS [InstalledAssetEntityId],
       a.[Name]                     AS [InstalledAssetName],
       a.[AssetTypeCode],
       a.[Status]                   AS [AssetStatus],
       a.[VoltageClassCode],
       m.[ModelId], m.[ModelCode], m.[ModelName], m.[Technology],
       mfe.[Name]                   AS [ManufacturerName],
       fw.[VersionString]           AS [FirmwareVersion],
       pl.[PlacedFrom],
       fn.[Functions],
       ISNULL(fn.[FunctionCount], 0) AS [FunctionCount],
       sch.[SchemeNames],
       nfl.[NodeFunctionLabels]
FROM [location].[vNode] dp
LEFT JOIN [location].[vNode] pnl ON pnl.[EntityId] = dp.[ParentEntityId]
LEFT JOIN [location].[vNode] h2  ON h2.[EntityId]  = pnl.[ParentEntityId]
LEFT JOIN [location].[vNode] h3  ON h3.[EntityId]  = h2.[ParentEntityId]
LEFT JOIN [location].[vNode] h4  ON h4.[EntityId]  = h3.[ParentEntityId]
OUTER APPLY (SELECT TOP (1) x.[StationEntityId], x.[StationName]
             FROM (VALUES (1, pnl.[EntityId], pnl.[NodeTypeCode], pnl.[Name]), (2, h2.[EntityId], h2.[NodeTypeCode], h2.[Name]),
                          (3, h3.[EntityId], h3.[NodeTypeCode], h3.[Name]), (4, h4.[EntityId], h4.[NodeTypeCode], h4.[Name])) x ([o], [StationEntityId], [T], [StationName])
             WHERE x.[T] = N'Station' ORDER BY x.[o]) st
OUTER APPLY (SELECT TOP (1) k.[KeyValue] FROM [location].[AlternateKey] k WHERE k.[ValidTo] IS NULL AND k.[IsDeleted] = 0 AND k.[SubjectEntityId] = st.[StationEntityId] AND k.[KeyKindCode] = N'StationNumber' ORDER BY k.[IsPrimaryLabel] DESC, k.[RowSeq]) stno
OUTER APPLY (SELECT TOP (1) k.[KeyValue] FROM [location].[AlternateKey] k WHERE k.[ValidTo] IS NULL AND k.[IsDeleted] = 0 AND k.[SubjectEntityId] = pnl.[EntityId] AND k.[KeyKindCode] = N'PanelSlot' ORDER BY k.[IsPrimaryLabel] DESC, k.[RowSeq]) slot
OUTER APPLY (SELECT TOP (1) p.[EntityId] AS [PlacementEntityId], p.[AssetEntityId], p.[ValidFrom] AS [PlacedFrom]
             FROM [asset].[Placement] p WHERE p.[ValidTo] IS NULL AND p.[IsDeleted] = 0 AND p.[NodeEntityId] = dp.[EntityId] AND p.[PlacementKind] = N'Installed' ORDER BY p.[ValidFrom] DESC) pl
LEFT JOIN [asset].[vAsset] a ON a.[EntityId] = pl.[AssetEntityId]
LEFT JOIN [device].[vDevice] dv ON dv.[EntityId] = a.[EntityId]
LEFT JOIN [ref].[vModel] m ON m.[ModelId] = a.[ModelId]
LEFT JOIN [ref].[vManufacturer] mf ON mf.[ManufacturerId] = m.[ManufacturerId]
LEFT JOIN [party].[vEntity] mfe ON mfe.[EntityId] = mf.[EntityEntityId]
LEFT JOIN [ref].[vFirmwareVersion] fw ON fw.[FirmwareVersionId] = dv.[CurrentFirmwareVersionId]
OUTER APPLY (SELECT STRING_AGG(f.[AnsiCode], N', ') WITHIN GROUP (ORDER BY f.[IsPrincipal] DESC, f.[AnsiCode]) AS [Functions], COUNT(*) AS [FunctionCount]
             FROM [location].[Node] pf JOIN [scheme].[CommissionedFunction] f ON f.[ProtectionFunctionNodeEntityId] = pf.[EntityId]
             WHERE pf.[ValidTo] IS NULL AND pf.[IsDeleted] = 0 AND f.[ValidTo] IS NULL AND f.[IsDeleted] = 0 AND pf.[ParentEntityId] = dp.[EntityId] AND pf.[NodeTypeCode] = N'ProtectionFunction') fn
OUTER APPLY (SELECT STRING_AGG(s.[Name], N'; ') WITHIN GROUP (ORDER BY s.[Name]) AS [SchemeNames]
             FROM (SELECT DISTINCT sm.[SchemeEntityId]
                   FROM [location].[Node] pf JOIN [scheme].[SchemeMember] sm ON sm.[MemberKind] = N'ProtectionFunction' AND sm.[MemberEntityId] = pf.[EntityId]
                   WHERE pf.[ValidTo] IS NULL AND pf.[IsDeleted] = 0 AND sm.[ValidTo] IS NULL AND sm.[IsDeleted] = 0 AND pf.[ParentEntityId] = dp.[EntityId] AND pf.[NodeTypeCode] = N'ProtectionFunction') x
             -- W8 (#158): the base table with the current-row predicate, not the windowed vScheme — evaluated per position, the
             -- windowed view took the whole read from ~1 s to 11 s once the migration raised 1 769 schemes (2026-09-14)
             JOIN [scheme].[Scheme] s ON s.[EntityId] = x.[SchemeEntityId] AND s.[ValidTo] IS NULL AND s.[IsDeleted] = 0) sch
OUTER APPLY (SELECT STRING_AGG(nf.[FunctionLabel], N'; ') AS [NodeFunctionLabels] FROM [location].[NodeFunction] nf WHERE nf.[ValidTo] IS NULL AND nf.[IsDeleted] = 0 AND nf.[NodeEntityId] = dp.[EntityId]) nfl
WHERE dp.[NodeTypeCode] IN (N'DevicePosition', N'MeteringPosition', N'NetworkSwitchPosition');
GO
GRANT SELECT ON [location].[vFloc] TO [app_execute];
GO
