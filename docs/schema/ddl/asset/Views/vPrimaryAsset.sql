-- #170 (2026-09-16): the primary assets — the non-device assets of the Primary class — with the station they are placed at
-- and their applicability classifications summarised, for the scheme's "protects" chooser, the primary-asset record and the
-- device sheet's "protects … via …" line. Hand-written read model: base tables in the current-row form (#169), no
-- generated current view of a large table.
CREATE VIEW [asset].[vPrimaryAsset] AS
SELECT a.[EntityId],
       a.[Name],
       a.[AssetTypeCode],
       t.[Name]                     AS [AssetTypeName],
       a.[Status],
       a.[VoltageClassCode],
       a.[Notes],
       st.[StationNodeEntityId],
       st.[StationName],
       cls.[Classifications],
       a.[RowSeq]
FROM [asset].[Asset] a
JOIN [ref].[AssetType] t ON t.[AssetTypeCode] = a.[AssetTypeCode] AND t.[AssetClassCode] = N'Primary' AND t.[IsDevice] = 0
OUTER APPLY (SELECT TOP (1) n.[EntityId] AS [StationNodeEntityId], n.[Name] AS [StationName]
             FROM [asset].[Placement] p JOIN [location].[Node] n ON n.[EntityId] = p.[NodeEntityId] AND n.[ValidTo] IS NULL AND n.[IsDeleted] = 0
             WHERE p.[ValidTo] IS NULL AND p.[IsDeleted] = 0 AND p.[AssetEntityId] = a.[EntityId] AND p.[NodeEntityId] IS NOT NULL
             ORDER BY p.[RowSeq] DESC) st
OUTER APPLY (SELECT STRING_AGG(CONCAT(c.[ClassificationKindCode], N'=', c.[ClassificationValue]), N'; ') WITHIN GROUP (ORDER BY c.[ClassificationKindCode]) AS [Classifications]
             FROM [asset].[Classification] c
             WHERE c.[ValidTo] IS NULL AND c.[IsDeleted] = 0 AND c.[SubjectKind] = N'Asset' AND c.[SubjectEntityId] = a.[EntityId]) cls
WHERE a.[ValidTo] IS NULL AND a.[IsDeleted] = 0;
GO
GRANT SELECT ON [asset].[vPrimaryAsset] TO [app_execute];
GO
