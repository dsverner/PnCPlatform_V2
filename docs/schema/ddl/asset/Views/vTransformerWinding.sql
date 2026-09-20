-- #212 (2026-09-20): an instrument transformer's secondary windings, each with its ratio read as a number ("1200:5",
-- "1200-5" and "1200/5" all read 240, the scheme.vSchemeSource way) and what uses it — the scheme and analog input of every
-- source membership that names the winding ("2103 B-PROT · Current 1"), or nothing. (named vTransformerWinding: the generator owns vInstrumentWinding as the table's current view). The transformer page's Secondary
-- windings panel reads it. Hand-written; base tables in the current-row form (#169).
CREATE VIEW [asset].[vTransformerWinding] AS
SELECT w.[EntityId]             AS [WindingEntityId],   -- not EntityId: the API would scope the row as an asset id (Catalog.SubjectColumns) — the transformer's AssetEntityId is the subject
       w.[RowId],
       w.[AssetEntityId],
       a.[Name]                AS [AssetName],
       w.[WindingNo],
       w.[Code],
       w.[Purpose],
       w.[RatioTaps],
       w.[RatioInUse],
       CASE WHEN r.[Primary] IS NOT NULL AND r.[Secondary] IS NOT NULL AND r.[Secondary] <> 0 THEN r.[Primary] / r.[Secondary] END AS [Ratio],
       w.[AccuracyClass],
       w.[RatedBurden],
       w.[KneePointVoltageV],
       w.[RatedSecondary],
       w.[Connection],
       w.[Notes],
       w.[TapInUseEntityId],   -- #213
       tp.[Terminals]          AS [TapInUseTerminals],
       ISNULL(tc.[N], 0)       AS [TapCount],
       ISNULL(u.[UseCount], 0) AS [UseCount],
       u.[UsedBy],
       w.[ValidFrom],
       w.[CreatedBy], w.[CreatedAt], w.[ModifiedBy], w.[ModifiedAt]
FROM [asset].[InstrumentWinding] w
JOIN [asset].[Asset] a ON a.[EntityId] = w.[AssetEntityId] AND a.[ValidTo] IS NULL AND a.[IsDeleted] = 0
OUTER APPLY (SELECT TRY_CONVERT(DECIMAL(18,4), LTRIM(RTRIM(LEFT(x.[T], x.[P] - 1))))      AS [Primary],
                    TRY_CONVERT(DECIMAL(18,4), LTRIM(RTRIM(SUBSTRING(x.[T], x.[P] + 1, 40)))) AS [Secondary]
             FROM (SELECT REPLACE(REPLACE(w.[RatioInUse], N'-', N':'), N'/', N':') AS [T]) y
             CROSS APPLY (SELECT y.[T], CHARINDEX(N':', y.[T]) AS [P]) x
             WHERE x.[P] > 1) r
LEFT JOIN [asset].[WindingTap] tp ON tp.[EntityId] = w.[TapInUseEntityId] AND tp.[ValidTo] IS NULL AND tp.[IsDeleted] = 0
OUTER APPLY (SELECT COUNT(*) AS [N] FROM [asset].[WindingTap] x WHERE x.[WindingEntityId] = w.[EntityId] AND x.[ValidTo] IS NULL AND x.[IsDeleted] = 0) tc
OUTER APPLY (SELECT COUNT(*) AS [UseCount],
                    STRING_AGG(sc.[Name] + ISNULL(N' · ' + ai.[InputCode], N''), N'; ') WITHIN GROUP (ORDER BY sc.[Name]) AS [UsedBy]
             FROM [scheme].[SchemeMember] sm
             JOIN [scheme].[Scheme] sc ON sc.[EntityId] = sm.[SchemeEntityId] AND sc.[ValidTo] IS NULL AND sc.[IsDeleted] = 0
             LEFT JOIN [scheme].[AnalogInput] ai ON ai.[EntityId] = sm.[AnalogInputEntityId] AND ai.[ValidTo] IS NULL AND ai.[IsDeleted] = 0
             WHERE sm.[WindingEntityId] = w.[EntityId] AND sm.[ValidTo] IS NULL AND sm.[IsDeleted] = 0) u
WHERE w.[ValidTo] IS NULL AND w.[IsDeleted] = 0;
GO
GRANT SELECT ON [asset].[vTransformerWinding] TO [app_execute];
GO
