-- #171 (2026-09-16). What a device protects, in one row: the scheme it belongs to, the primary asset that scheme protects,
-- and the terminal end the protection sits at. The device.protects.* facts (compliance.vFactCatalogue) are read through it,
-- so the rule is stated once here rather than once per fact.
--   device → scheme   the device's own scheme.SchemeMember row (MemberKind Asset) first, else the membership of a
--                     ProtectionFunction node under its Installed placement — the rule document.vSettingsRecord uses
--                     for the grid's scheme column (lines 114-127 there).
--   scheme → asset    the current scheme.SchemeProtects link, the Primary zone first, then by the asset's name. A scheme
--                     that protects nothing yields no row at all, which the facts read as Unknown — never a guess.
--   terminal end      SchemeProtects.AssetTerminalEntityId when the link names one (#170: a line's two ends have their own
--                     schemes); when it does not, the asset's terminal at the scheme's own station (scheme.vSchemeStation,
--                     which reads current rows — not @at — as asset.vAssetTerminalDetail does for the same match).
--                     When neither names an end and the asset has exactly one current terminal (a capacitor, a reactor, a
--                     line entered with one end so far), that terminal is the end — there is no other.
-- Inline TVF: one row or none.
CREATE FUNCTION [compliance].[fDeviceProtects] (@deviceEntityId UNIQUEIDENTIFIER, @at DATETIMEOFFSET(7))
RETURNS TABLE AS RETURN
SELECT TOP (1)
       sch.[SchemeEntityId],
       sp.[PrimaryAssetEntityId],
       pa.[Name]                    AS [PrimaryAssetName],
       sp.[ZoneRole],
       tm.[AssetTerminalEntityId],
       tm.[StationNodeEntityId],
       tm.[VoltageClassCode],
       vc.[NominalKv],
       tm.[BusAssetEntityId]
FROM (SELECT @deviceEntityId AS [DeviceEntityId]) d
OUTER APPLY (SELECT TOP (1) p.[NodeEntityId] FROM [asset].[Placement] p
             WHERE p.[AssetEntityId] = d.[DeviceEntityId] AND p.[PlacementKind] = N'Installed' AND p.[IsDeleted] = 0
               AND p.[ValidFrom] <= @at AND (p.[ValidTo] IS NULL OR p.[ValidTo] > @at)
             ORDER BY p.[ValidFrom] DESC, p.[RowSeq] DESC) pl
OUTER APPLY (SELECT TOP (1) sm.[SchemeEntityId] FROM [scheme].[SchemeMember] sm
             WHERE sm.[MemberKind] = N'Asset' AND sm.[MemberEntityId] = d.[DeviceEntityId] AND sm.[IsDeleted] = 0
               AND sm.[ValidFrom] <= @at AND (sm.[ValidTo] IS NULL OR sm.[ValidTo] > @at)
             ORDER BY sm.[RowSeq]) sma
OUTER APPLY (SELECT TOP (1) sm.[SchemeEntityId] FROM [location].[Node] pf
             JOIN [scheme].[SchemeMember] sm ON sm.[MemberKind] = N'ProtectionFunction' AND sm.[MemberEntityId] = pf.[EntityId]
                  AND sm.[IsDeleted] = 0 AND sm.[ValidFrom] <= @at AND (sm.[ValidTo] IS NULL OR sm.[ValidTo] > @at)
             WHERE sma.[SchemeEntityId] IS NULL AND pf.[ParentEntityId] = pl.[NodeEntityId] AND pf.[NodeTypeCode] = N'ProtectionFunction'
               AND pf.[ValidTo] IS NULL AND pf.[IsDeleted] = 0
             ORDER BY sm.[RowSeq]) smf
CROSS APPLY (VALUES (COALESCE(sma.[SchemeEntityId], smf.[SchemeEntityId]))) sch ([SchemeEntityId])
OUTER APPLY (SELECT TOP (1) x.[PrimaryAssetEntityId], x.[ZoneRole], x.[AssetTerminalEntityId]
             FROM [scheme].[SchemeProtects] x
             OUTER APPLY (SELECT TOP (1) a.[Name] FROM [asset].[Asset] a
                          WHERE a.[EntityId] = x.[PrimaryAssetEntityId] AND a.[IsDeleted] = 0
                            AND a.[ValidFrom] <= @at AND (a.[ValidTo] IS NULL OR a.[ValidTo] > @at)
                          ORDER BY a.[ValidFrom] DESC, a.[RowSeq] DESC) xa
             WHERE x.[SchemeEntityId] = sch.[SchemeEntityId] AND x.[IsDeleted] = 0
               AND x.[ValidFrom] <= @at AND (x.[ValidTo] IS NULL OR x.[ValidTo] > @at)
             ORDER BY CASE WHEN x.[ZoneRole] = N'Primary' THEN 0 ELSE 1 END, xa.[Name], x.[RowSeq]) sp
OUTER APPLY (SELECT TOP (1) a.[Name] FROM [asset].[Asset] a
             WHERE a.[EntityId] = sp.[PrimaryAssetEntityId] AND a.[IsDeleted] = 0
               AND a.[ValidFrom] <= @at AND (a.[ValidTo] IS NULL OR a.[ValidTo] > @at)
             ORDER BY a.[ValidFrom] DESC, a.[RowSeq] DESC) pa
OUTER APPLY (SELECT TOP (1) t.[EntityId] AS [AssetTerminalEntityId], t.[StationNodeEntityId], t.[VoltageClassCode], t.[BusAssetEntityId]
             FROM [asset].[AssetTerminal] t
             WHERE t.[EntityId] = sp.[AssetTerminalEntityId] AND t.[IsDeleted] = 0
               AND t.[ValidFrom] <= @at AND (t.[ValidTo] IS NULL OR t.[ValidTo] > @at)
             ORDER BY t.[ValidFrom] DESC, t.[RowSeq] DESC) t1
OUTER APPLY (SELECT TOP (1) t.[EntityId] AS [AssetTerminalEntityId], t.[StationNodeEntityId], t.[VoltageClassCode], t.[BusAssetEntityId]
             FROM [asset].[AssetTerminal] t
             WHERE sp.[AssetTerminalEntityId] IS NULL AND t.[AssetEntityId] = sp.[PrimaryAssetEntityId] AND t.[IsDeleted] = 0
               AND t.[ValidFrom] <= @at AND (t.[ValidTo] IS NULL OR t.[ValidTo] > @at)
               AND EXISTS (SELECT 1 FROM [scheme].[vSchemeStation] ss
                           WHERE ss.[SchemeEntityId] = sch.[SchemeEntityId] AND ss.[StationNodeEntityId] = t.[StationNodeEntityId])
             ORDER BY t.[TerminalNo], t.[ValidFrom] DESC, t.[RowSeq] DESC) t2
OUTER APPLY (SELECT t.[EntityId] AS [AssetTerminalEntityId], t.[StationNodeEntityId], t.[VoltageClassCode], t.[BusAssetEntityId]
             FROM [asset].[AssetTerminal] t
             WHERE t1.[AssetTerminalEntityId] IS NULL AND t2.[AssetTerminalEntityId] IS NULL
               AND t.[AssetEntityId] = sp.[PrimaryAssetEntityId] AND t.[IsDeleted] = 0
               AND t.[ValidFrom] <= @at AND (t.[ValidTo] IS NULL OR t.[ValidTo] > @at)
               AND NOT EXISTS (SELECT 1 FROM [asset].[AssetTerminal] o
                               WHERE o.[AssetEntityId] = sp.[PrimaryAssetEntityId] AND o.[IsDeleted] = 0 AND o.[EntityId] <> t.[EntityId]
                                 AND o.[ValidFrom] <= @at AND (o.[ValidTo] IS NULL OR o.[ValidTo] > @at))) t3
CROSS APPLY (VALUES (COALESCE(t1.[AssetTerminalEntityId], t2.[AssetTerminalEntityId], t3.[AssetTerminalEntityId]),
                     COALESCE(t1.[StationNodeEntityId],   t2.[StationNodeEntityId],   t3.[StationNodeEntityId]),
                     COALESCE(t1.[VoltageClassCode],      t2.[VoltageClassCode],      t3.[VoltageClassCode]),
                     COALESCE(t1.[BusAssetEntityId],      t2.[BusAssetEntityId],      t3.[BusAssetEntityId])))
            tm ([AssetTerminalEntityId], [StationNodeEntityId], [VoltageClassCode], [BusAssetEntityId])
OUTER APPLY (SELECT TOP (1) v.[NominalKv] FROM [ref].[VoltageClass] v WHERE v.[VoltageClassCode] = tm.[VoltageClassCode]) vc
WHERE sp.[PrimaryAssetEntityId] IS NOT NULL;
GO
