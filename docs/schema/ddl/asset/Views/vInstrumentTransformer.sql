-- #201 (2026-09-19): the instrument transformers as equipment — one row per asset of an instrument-transformer type
-- (CT, VT, the auxiliaries, the CVT, the CCPD, the metering unit): identity, serial, where it is placed and the station
-- that is in, the ratio in use (its CT_Template / VT_Template characteristic), and the schemes it feeds
-- (scheme.SchemeMember rows with role CtSource, VtSource or SyncVtSource). The list screen and the equipment page read it.
-- #206 (2026-09-20): a transformer made by the migration rule stands unplaced until a person places it (no migrated station
-- has a yard), so the station falls back to the station of a scheme it feeds (through that scheme's placed device members),
-- IsPlaced says which it was, Phases (3 for a set, 1 for a sync PT) is read beside the ratio, and MigrationSource is the
-- rule's own key on the asset (asset.AlternateKey kind MigrationSource) — null for one a person made.
-- Hand-written; base tables in the current-row form (#169); the station by location.fStationOf.
CREATE VIEW [asset].[vInstrumentTransformer] AS
SELECT a.[EntityId],
       a.[RowId],
       a.[Name],
       a.[AssetTypeCode],
       t.[Name]                     AS [AssetTypeName],
       t.[AssetClassCode],
       a.[Status],
       a.[VoltageClassCode],
       a.[ModelId],
       m.[ModelCode],
       a.[ManufacturerEntityId],
       a.[CommissionedAt],
       a.[RetiredAt],
       a.[Notes],
       sn.[KeyValue]                AS [SerialNumber],
       pl.[NodeEntityId],
       n.[Name]                     AS [NodeName],
       n.[NodeTypeCode],
       pl.[PlacementKind],
       CONVERT(BIT, CASE WHEN pl.[NodeEntityId] IS NULL THEN 0 ELSE 1 END) AS [IsPlaced],
       COALESCE(st.[EntityId], fst.[EntityId]) AS [StationNodeEntityId],
       COALESCE(st.[Name], fst.[Name])         AS [StationName],
       CASE WHEN st.[EntityId] IS NOT NULL THEN N'placement' WHEN fst.[EntityId] IS NOT NULL THEN N'scheme' END AS [StationSource],
       ru.[TextValue]               AS [RatioInUse],
       ph.[IntegerValue]            AS [Phases],
       mk.[KeyValue]                AS [MigrationSource],
       feeds.[FeedsSchemes],
       ISNULL(feeds.[FeedsCount], 0) AS [FeedsCount],
       a.[ValidFrom],
       a.[CreatedBy], a.[CreatedAt], a.[ModifiedBy], a.[ModifiedAt]
FROM [asset].[Asset] a
JOIN [ref].[AssetType] t ON t.[AssetTypeCode] = a.[AssetTypeCode]
  AND t.[AssetTypeCode] IN (N'CT', N'VT', N'CT_AUX', N'VT_AUX', N'COUPLING_CAPACITOR_VT', N'CCPD', N'METERING_UNIT')
LEFT JOIN [ref].[Model] m ON m.[ModelId] = a.[ModelId]
OUTER APPLY (SELECT TOP (1) k.[KeyValue] FROM [asset].[AlternateKey] k
             WHERE k.[SubjectEntityId] = a.[EntityId] AND k.[KeyKindCode] = N'SerialNumber' AND k.[ValidTo] IS NULL AND k.[IsDeleted] = 0
             ORDER BY k.[IsPrimaryLabel] DESC, k.[RowSeq] DESC) sn
OUTER APPLY (SELECT TOP (1) k.[KeyValue] FROM [asset].[AlternateKey] k
             WHERE k.[SubjectEntityId] = a.[EntityId] AND k.[KeyKindCode] = N'MigrationSource' AND k.[ValidTo] IS NULL AND k.[IsDeleted] = 0
             ORDER BY k.[RowSeq] DESC) mk
-- the station is found inside the placement subquery: location.Node carries a GEOGRAPHY column named Location, and with a
-- Node alias in scope SQL Server reads [location].[fStationOf] as that column's method (Msg 209, found on the first deploy)
OUTER APPLY (SELECT TOP (1) p.[NodeEntityId], p.[PlacementKind], [location].[fStationOf](p.[NodeEntityId]) AS [StationId] FROM [asset].[Placement] p
             WHERE p.[AssetEntityId] = a.[EntityId] AND p.[ValidTo] IS NULL AND p.[IsDeleted] = 0
             ORDER BY CASE p.[PlacementKind] WHEN N'Installed' THEN 0 ELSE 1 END, p.[RowSeq] DESC) pl
-- #206: unplaced, the station of a scheme it feeds — read through a placed device member of that scheme (the same walk
-- scheme.vSchemeStation makes). This APPLY stands BEFORE the Node joins below and calls fStationOf in a derived table with
-- no Node alias in scope, for the Msg 209 reason above
OUTER APPLY (SELECT TOP (1) sid.[StationId]
             FROM [scheme].[SchemeMember] me
             JOIN [scheme].[SchemeMember] other ON other.[SchemeEntityId] = me.[SchemeEntityId] AND other.[MemberKind] = N'Asset' AND other.[MemberEntityId] <> a.[EntityId]
                                              AND other.[ValidTo] IS NULL AND other.[IsDeleted] = 0
             JOIN [asset].[Placement] p2 ON p2.[AssetEntityId] = other.[MemberEntityId] AND p2.[NodeEntityId] IS NOT NULL AND p2.[ValidTo] IS NULL AND p2.[IsDeleted] = 0
             CROSS APPLY (SELECT [location].[fStationOf](p2.[NodeEntityId]) AS [StationId]) sid
             WHERE pl.[NodeEntityId] IS NULL AND me.[MemberKind] = N'Asset' AND me.[MemberEntityId] = a.[EntityId]
               AND me.[MemberRoleCode] IN (N'CtSource', N'VtSource', N'SyncVtSource') AND me.[ValidTo] IS NULL AND me.[IsDeleted] = 0
               AND sid.[StationId] IS NOT NULL
             ORDER BY me.[RowSeq]) fsid
LEFT JOIN [location].[Node] n ON n.[EntityId] = pl.[NodeEntityId] AND n.[ValidTo] IS NULL AND n.[IsDeleted] = 0
LEFT JOIN [location].[Node] st ON st.[EntityId] = pl.[StationId] AND st.[ValidTo] IS NULL AND st.[IsDeleted] = 0
LEFT JOIN [location].[Node] fst ON fst.[EntityId] = fsid.[StationId] AND fst.[ValidTo] IS NULL AND fst.[IsDeleted] = 0
OUTER APPLY (SELECT TOP (1) cv.[TextValue] FROM [asset].[CharacteristicValue] cv
             JOIN [config].[CharacteristicDefinition] cd ON cd.[RowId] = cv.[CharacteristicDefinitionRowId] AND cd.[CharacteristicKey] = N'RatioInUse'
             WHERE cv.[HostEntityId] = a.[EntityId] AND cv.[ValidTo] IS NULL AND cv.[IsDeleted] = 0
             ORDER BY cv.[RowSeq] DESC) ru
OUTER APPLY (SELECT TOP (1) cv.[IntegerValue] FROM [asset].[CharacteristicValue] cv
             JOIN [config].[CharacteristicDefinition] cd ON cd.[RowId] = cv.[CharacteristicDefinitionRowId] AND cd.[CharacteristicKey] = N'Phases'
             WHERE cv.[HostEntityId] = a.[EntityId] AND cv.[ValidTo] IS NULL AND cv.[IsDeleted] = 0
             ORDER BY cv.[RowSeq] DESC) ph
OUTER APPLY (SELECT COUNT(*) AS [FeedsCount],
                    STRING_AGG(sc.[Name] + N' (' + sm.[MemberRoleCode] + N')', N'; ') WITHIN GROUP (ORDER BY sc.[Name]) AS [FeedsSchemes]
             FROM [scheme].[SchemeMember] sm
             JOIN [scheme].[Scheme] sc ON sc.[EntityId] = sm.[SchemeEntityId] AND sc.[ValidTo] IS NULL AND sc.[IsDeleted] = 0
             WHERE sm.[MemberKind] = N'Asset' AND sm.[MemberEntityId] = a.[EntityId] AND sm.[MemberRoleCode] IN (N'CtSource', N'VtSource', N'SyncVtSource')
               AND sm.[ValidTo] IS NULL AND sm.[IsDeleted] = 0) feeds
WHERE a.[ValidTo] IS NULL AND a.[IsDeleted] = 0;
GO
GRANT SELECT ON [asset].[vInstrumentTransformer] TO [app_execute];
GO
