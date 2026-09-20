-- #208 (2026-09-20): a scheme's analog inputs — the relay-side endpoints its sources feed — with how many transformers feed
-- each (two or more on a current input are paralleled: the owner, "they will always be connected in parallel"), the ratios
-- they carry (the distinct numbers, so the record's Analog inputs tab can say whether paralleled CTs agree with each other
-- and with the relay's CTR), and whether any is not in service. Hand-written; base tables in the current-row form (#169).
CREATE VIEW [scheme].[vSchemeInput] AS
SELECT ai.[EntityId],
       ai.[RowId],
       ai.[SchemeEntityId],
       ai.[InputCode],
       ai.[InputKind],
       ai.[Notes],
       ISNULL(m.[SourceCount], 0)     AS [SourceCount],
       CONVERT(BIT, CASE WHEN ISNULL(m.[SourceCount], 0) >= 2 THEN 1 ELSE 0 END) AS [IsParallel],
       m.[Ratios],                    -- the distinct ratio numbers of the transformers on the input, as text: "240" or "240; 160"
       m.[DistinctRatios],
       m.[Transformers],
       ai.[ValidFrom],
       ai.[CreatedBy], ai.[CreatedAt], ai.[ModifiedBy], ai.[ModifiedAt]
FROM [scheme].[AnalogInput] ai
OUTER APPLY (SELECT COUNT(*) AS [SourceCount],
                    COUNT(DISTINCT src.[Ratio]) AS [DistinctRatios],
                    STRING_AGG(CONVERT(NVARCHAR(40), src.[Ratio]), N'; ') WITHIN GROUP (ORDER BY src.[AssetName]) AS [Ratios],
                    STRING_AGG(src.[AssetName], N'; ') WITHIN GROUP (ORDER BY src.[AssetName]) AS [Transformers]
             FROM [scheme].[vSchemeSource] src
             WHERE src.[AnalogInputEntityId] = ai.[EntityId]) m
WHERE ai.[ValidTo] IS NULL AND ai.[IsDeleted] = 0;
GO
GRANT SELECT ON [scheme].[vSchemeInput] TO [app_execute];
GO
