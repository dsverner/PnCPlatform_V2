-- Hand-written read model (W6, decisions #57, #127). Browse the FLOC view by scheme: one row per (device position, scheme)
-- pair — a position belongs to a scheme through the RELAY placed there, which the scheme names as an Asset member (#181;
-- until then it walked the protection-function nodes under the position). Filter ?SchemeEntityId= for the positions of a
-- scheme, ?NodeEntityId= for the schemes of a position. Subject column NodeEntityId (it precedes SchemeEntityId in the
-- dispatcher's preference list), so the read is scoped by the grant's subtree.
-- Correlated lookups read the base tables with the current-row predicate in the filtered indexes' own form (ValidTo IS NULL AND IsDeleted = 0): an OUTER APPLY ... TOP (1) against a
-- generated current view (ROW_NUMBER over the entity) is evaluated over the whole table per outer row — 26 s a page on the
-- migrated estate, measured in W7 — where the same lookup on the base table seeks. The joins to the current views stay.
CREATE VIEW [location].[vFlocScheme] AS
SELECT f.[RowSeq],
       f.[NodeEntityId],
       x.[SchemeEntityId],
       s.[Name]                     AS [SchemeName],
       s.[Status]                   AS [SchemeStatus],
       s.[SystemDesignation],
       x.[MemberRoleCodes],
       x.[FunctionCount]            AS [MemberFunctionCount],
       f.[PositionTypeCode], f.[PositionName],
       f.[PanelNodeEntityId], f.[PanelName],
       f.[StationNodeEntityId], f.[StationName], f.[StationNumber],
       f.[InstalledAssetEntityId], f.[InstalledAssetName], f.[AssetTypeCode], f.[ModelCode], f.[ModelName], f.[ManufacturerName],
       f.[Functions]
FROM [location].[vFloc] f
CROSS APPLY (SELECT sm.[SchemeEntityId], STRING_AGG(sm.[MemberRoleCode], N', ') WITHIN GROUP (ORDER BY sm.[MemberRoleCode]) AS [MemberRoleCodes], COUNT(*) AS [FunctionCount]
             FROM [asset].[Placement] pf JOIN [scheme].[SchemeMember] sm ON sm.[MemberKind] = N'Asset' AND sm.[MemberEntityId] = pf.[AssetEntityId]   -- #181: through the relay placed there
             WHERE pf.[ValidTo] IS NULL AND pf.[IsDeleted] = 0 AND sm.[ValidTo] IS NULL AND sm.[IsDeleted] = 0 AND pf.[NodeEntityId] = f.[NodeEntityId]
             GROUP BY sm.[SchemeEntityId]) x
JOIN [scheme].[vScheme] s ON s.[EntityId] = x.[SchemeEntityId];
GO
GRANT SELECT ON [location].[vFlocScheme] TO [app_execute];
GO
