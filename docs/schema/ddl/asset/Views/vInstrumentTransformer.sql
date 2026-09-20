-- #201 (2026-09-19): the instrument transformers as equipment — one row per asset of an instrument-transformer type
-- (CT, VT, the auxiliaries, the CVT, the CCPD, the metering unit): identity, serial, where it is placed and the station
-- that is in, the ratio in use (its CT_Template / VT_Template characteristic), and the schemes it feeds
-- (scheme.SchemeMember rows with role CtSource or VtSource). The list screen and the equipment page read it.
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
       a.[Notes],
       sn.[KeyValue]                AS [SerialNumber],
       pl.[NodeEntityId],
       n.[Name]                     AS [NodeName],
       n.[NodeTypeCode],
       pl.[PlacementKind],
       st.[EntityId]                AS [StationNodeEntityId],
       st.[Name]                    AS [StationName],
       ru.[TextValue]               AS [RatioInUse],
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
-- the station is found inside the placement subquery: location.Node carries a GEOGRAPHY column named Location, and with a
-- Node alias in scope SQL Server reads [location].[fStationOf] as that column's method (Msg 209, found on the first deploy)
OUTER APPLY (SELECT TOP (1) p.[NodeEntityId], p.[PlacementKind], [location].[fStationOf](p.[NodeEntityId]) AS [StationId] FROM [asset].[Placement] p
             WHERE p.[AssetEntityId] = a.[EntityId] AND p.[ValidTo] IS NULL AND p.[IsDeleted] = 0
             ORDER BY CASE p.[PlacementKind] WHEN N'Installed' THEN 0 ELSE 1 END, p.[RowSeq] DESC) pl
LEFT JOIN [location].[Node] n ON n.[EntityId] = pl.[NodeEntityId] AND n.[ValidTo] IS NULL AND n.[IsDeleted] = 0
LEFT JOIN [location].[Node] st ON st.[EntityId] = pl.[StationId] AND st.[ValidTo] IS NULL AND st.[IsDeleted] = 0
OUTER APPLY (SELECT TOP (1) cv.[TextValue] FROM [asset].[CharacteristicValue] cv
             JOIN [config].[CharacteristicDefinition] cd ON cd.[RowId] = cv.[CharacteristicDefinitionRowId] AND cd.[CharacteristicKey] = N'RatioInUse'
             WHERE cv.[HostEntityId] = a.[EntityId] AND cv.[ValidTo] IS NULL AND cv.[IsDeleted] = 0
             ORDER BY cv.[RowSeq] DESC) ru
OUTER APPLY (SELECT COUNT(*) AS [FeedsCount],
                    STRING_AGG(sc.[Name] + N' (' + sm.[MemberRoleCode] + N')', N'; ') WITHIN GROUP (ORDER BY sc.[Name]) AS [FeedsSchemes]
             FROM [scheme].[SchemeMember] sm
             JOIN [scheme].[Scheme] sc ON sc.[EntityId] = sm.[SchemeEntityId] AND sc.[ValidTo] IS NULL AND sc.[IsDeleted] = 0
             WHERE sm.[MemberKind] = N'Asset' AND sm.[MemberEntityId] = a.[EntityId] AND sm.[MemberRoleCode] IN (N'CtSource', N'VtSource')
               AND sm.[ValidTo] IS NULL AND sm.[IsDeleted] = 0) feeds
WHERE a.[ValidTo] IS NULL AND a.[IsDeleted] = 0;
GO
GRANT SELECT ON [asset].[vInstrumentTransformer] TO [app_execute];
GO
