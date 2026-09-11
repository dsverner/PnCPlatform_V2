-- Hand-written read model. SCHEMA-DESIGN §5; PLATFORM-ARCHITECTURE §2.3, §3.4.
--
-- The evidence for classifying a station, one row per station.
--
-- Why this exists: six of the thirteen migrated PRC-005 obligation rules are BES and six are non-BES,
-- so `station.classification.BesStatus` is the first thing any rule scope tests — and on 2026-09-09
-- only 5 of 231 stations carried one. Every other station evaluated to Indeterminate, which meant the
-- whole rule set could not run. See `.planning/COMPLIANCE-ENGINE-COMPARISON.md`.
--
-- The evidence itself is real and already migrated: the legacy relay register carried a per-record
-- `Bulk_Power_Element` bit, loaded here as the `bulk_power_element` characteristic on 11,717 assets
-- (2,384 true). This view rolls that up to the station a device is placed at, so a person classifying
-- a station sees how many of its devices the old register called bulk-power elements before deciding.
--
-- It deliberately does NOT decide. A station with 24 bulk-power devices out of 940 may or may not be a
-- BES station; that is a regulatory judgement, and `asset.Classification` records who made it and
-- when. A classification derived by rule instead has to cite a Program.ClassificationDerivation, which
-- the table's own CHECK enforces.
--
-- Placements sit on device positions now, not on stations, so the walk climbs up to four ancestors:
-- DevicePosition → Panel → Building → Station. `DevicesWithEvidence` is the count that reached this
-- station, so a station showing 0 has no evidence rather than evidence of nothing.
CREATE VIEW [asset].[vStationClassificationEvidence] AS
WITH [Bes] AS (
    SELECT v.[HostEntityId] AS [AssetEntityId], v.[BooleanValue] AS [IsBulkPower]
    FROM [asset].[vCharacteristicValue] v
    JOIN [config].[vCharacteristicDefinition] cd ON cd.[RowId] = v.[CharacteristicDefinitionRowId]
    WHERE cd.[CharacteristicKey] = N'bulk_power_element'
),
[Node] AS (
    SELECT [EntityId], [ParentEntityId], [NodeTypeCode], [Name], [SubtypeCode] FROM [location].[vNode]
),
[Placed] AS (
    SELECT p.[AssetEntityId],
           COALESCE(s4.[EntityId], s3.[EntityId], s2.[EntityId], s1.[EntityId]) AS [StationEntityId]
    FROM [asset].[vPlacement] p
    LEFT JOIN [Node] a1 ON a1.[EntityId] = p.[NodeEntityId]
    LEFT JOIN [Node] a2 ON a2.[EntityId] = a1.[ParentEntityId]
    LEFT JOIN [Node] a3 ON a3.[EntityId] = a2.[ParentEntityId]
    LEFT JOIN [Node] a4 ON a4.[EntityId] = a3.[ParentEntityId]
    LEFT JOIN [Node] s1 ON s1.[EntityId] = a1.[EntityId] AND s1.[NodeTypeCode] = N'Station'
    LEFT JOIN [Node] s2 ON s2.[EntityId] = a2.[EntityId] AND s2.[NodeTypeCode] = N'Station'
    LEFT JOIN [Node] s3 ON s3.[EntityId] = a3.[EntityId] AND s3.[NodeTypeCode] = N'Station'
    LEFT JOIN [Node] s4 ON s4.[EntityId] = a4.[EntityId] AND s4.[NodeTypeCode] = N'Station'
),
[Roll] AS (
    SELECT pl.[StationEntityId],
           SUM(CASE WHEN b.[IsBulkPower] = 1 THEN 1 ELSE 0 END) AS [BulkPowerDevices],
           SUM(CASE WHEN b.[IsBulkPower] = 0 THEN 1 ELSE 0 END) AS [OtherDevices]
    FROM [Placed] pl
    JOIN [Bes] b ON b.[AssetEntityId] = pl.[AssetEntityId]
    WHERE pl.[StationEntityId] IS NOT NULL
    GROUP BY pl.[StationEntityId]
)
SELECT n.[EntityId]                              AS [StationEntityId],
       n.[Name]                                  AS [StationName],
       n.[SubtypeCode]                           AS [StationSubtype],
       ISNULL(r.[BulkPowerDevices], 0)           AS [BulkPowerDevices],
       ISNULL(r.[OtherDevices], 0)               AS [OtherDevices],
       ISNULL(r.[BulkPowerDevices], 0) + ISNULL(r.[OtherDevices], 0) AS [DevicesWithEvidence],
       (SELECT COUNT(*) FROM [asset].[vPlacement] p2
        WHERE p2.[NodeEntityId] = n.[EntityId])  AS [PlacedDirectlyHere],
       bes.[ClassificationValue]                 AS [BesStatus],
       bes.[Basis]                               AS [BesBasis],
       bes.[DeterminedAt]                        AS [BesDeterminedAt],
       npcc.[ClassificationValue]                AS [NpccBulkPowerSystem],
       cip.[ClassificationValue]                 AS [CipImpactRating]
FROM [Node] n
LEFT JOIN [Roll] r ON r.[StationEntityId] = n.[EntityId]
OUTER APPLY (SELECT TOP 1 c.[ClassificationValue], c.[Basis], c.[DeterminedAt]
             FROM [asset].[vClassification] c
             WHERE c.[SubjectEntityId] = n.[EntityId] AND c.[ClassificationKindCode] = N'BesStatus'
             ORDER BY c.[DeterminedAt] DESC) bes
OUTER APPLY (SELECT TOP 1 c.[ClassificationValue]
             FROM [asset].[vClassification] c
             WHERE c.[SubjectEntityId] = n.[EntityId] AND c.[ClassificationKindCode] = N'NpccBulkPowerSystem'
             ORDER BY c.[DeterminedAt] DESC) npcc
OUTER APPLY (SELECT TOP 1 c.[ClassificationValue]
             FROM [asset].[vClassification] c
             WHERE c.[SubjectEntityId] = n.[EntityId] AND c.[ClassificationKindCode] = N'CipImpactRating'
             ORDER BY c.[DeterminedAt] DESC) cip
WHERE n.[NodeTypeCode] = N'Station';
GO
GRANT SELECT ON [asset].[vStationClassificationEvidence] TO [app_execute];
GO
