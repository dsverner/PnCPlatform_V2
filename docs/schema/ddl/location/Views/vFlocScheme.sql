-- Hand-written read model (W6, decisions #57, #127). Browse the FLOC view by scheme: one row per (device position, scheme)
-- pair — a position belongs to a scheme through the protection functions commissioned under it (scheme.SchemeMember of
-- kind ProtectionFunction, the same walk scheme.vSchemeExpanded does). Filter ?SchemeEntityId= for the positions of a
-- scheme, ?NodeEntityId= for the schemes of a position. Subject column NodeEntityId (it precedes SchemeEntityId in the
-- dispatcher's preference list), so the read is scoped by the grant's subtree.
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
             FROM [location].[vNode] pf JOIN [scheme].[vSchemeMember] sm ON sm.[MemberKind] = N'ProtectionFunction' AND sm.[MemberEntityId] = pf.[EntityId]
             WHERE pf.[ParentEntityId] = f.[NodeEntityId] AND pf.[NodeTypeCode] = N'ProtectionFunction'
             GROUP BY sm.[SchemeEntityId]) x
JOIN [scheme].[vScheme] s ON s.[EntityId] = x.[SchemeEntityId];
GO
GRANT SELECT ON [location].[vFlocScheme] TO [app_execute];
GO
