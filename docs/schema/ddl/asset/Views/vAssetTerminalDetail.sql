-- #170 (2026-09-16): a primary asset's terminals with what the screens need at each end — the station, the voltage, the bus the
-- terminal connects to and that bus's NPCC declaration (the A-10 test is a bus test: the BPS status is the bus's, the line or
-- transformer inherits it at that end — the owner), and the schemes protecting the asset from this end: those linked to the
-- terminal explicitly (SchemeProtects.AssetTerminalEntityId) or, when the link names no terminal, those whose station is this
-- terminal's. Hand-written read model, base tables in the current-row form (#169).
CREATE VIEW [asset].[vAssetTerminalDetail] AS
SELECT t.[EntityId]                 AS [TerminalEntityId],   -- not EntityId: the read scope is the asset's (AssetEntityId), see Catalog.SubjectOf
       t.[AssetEntityId],
       t.[TerminalNo],
       t.[StationNodeEntityId],
       stn.[Name]                   AS [StationName],
       t.[VoltageClassCode],
       t.[BusAssetEntityId],
       bus.[Name]                   AS [BusName],
       busNpcc.[ClassificationValue] AS [BusNpcc],
       sch.[Schemes],
       sch.[SchemeCount],
       t.[Notes],
       t.[RowSeq]
FROM [asset].[AssetTerminal] t
LEFT JOIN [location].[Node] stn ON stn.[EntityId] = t.[StationNodeEntityId] AND stn.[ValidTo] IS NULL AND stn.[IsDeleted] = 0
OUTER APPLY (SELECT TOP (1) a.[Name] FROM [asset].[Asset] a WHERE a.[EntityId] = t.[BusAssetEntityId] AND a.[ValidTo] IS NULL AND a.[IsDeleted] = 0 ORDER BY a.[RowSeq] DESC) bus
OUTER APPLY (SELECT TOP (1) c.[ClassificationValue] FROM [asset].[Classification] c
             WHERE c.[SubjectKind] = N'Asset' AND c.[SubjectEntityId] = t.[BusAssetEntityId] AND c.[ClassificationKindCode] = N'NpccBulkPowerSystem' AND c.[ValidTo] IS NULL AND c.[IsDeleted] = 0
             ORDER BY c.[RowSeq] DESC) busNpcc
OUTER APPLY (SELECT COUNT(*) AS [SchemeCount], STRING_AGG(x.[SchemeName], N', ') WITHIN GROUP (ORDER BY x.[SchemeName]) AS [Schemes]
             FROM (SELECT DISTINCT sc.[Name] AS [SchemeName]
                   FROM [scheme].[SchemeProtects] sp
                   JOIN [scheme].[Scheme] sc ON sc.[EntityId] = sp.[SchemeEntityId] AND sc.[ValidTo] IS NULL AND sc.[IsDeleted] = 0
                   WHERE sp.[PrimaryAssetEntityId] = t.[AssetEntityId] AND sp.[ValidTo] IS NULL AND sp.[IsDeleted] = 0
                     AND (sp.[AssetTerminalEntityId] = t.[EntityId]
                          OR (sp.[AssetTerminalEntityId] IS NULL AND EXISTS (SELECT 1 FROM [scheme].[vSchemeStation] ss WHERE ss.[SchemeEntityId] = sp.[SchemeEntityId] AND ss.[StationNodeEntityId] = t.[StationNodeEntityId])))) x) sch
WHERE t.[ValidTo] IS NULL AND t.[IsDeleted] = 0;
GO
GRANT SELECT ON [asset].[vAssetTerminalDetail] TO [app_execute];
GO
