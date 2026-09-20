-- #201 (2026-09-19): what feeds a scheme — its members with role CtSource or VtSource, the instrument transformer each
-- is, and its ratio in use read as a number (1200:5 → 240; 2000:1 → 2000; "1200-5" and "1200/5" read too, since that is
-- how the legacy record wrote them; NULL when the text is not two numbers). The record's Analog inputs tab reads this
-- beside the relay's CTR / PTR / SPTR and says whether they agree. Hand-written; base tables in the current-row form.
CREATE VIEW [scheme].[vSchemeSource] AS
SELECT sm.[SchemeEntityId],
       sm.[EntityId]           AS [MemberEntityId],
       sm.[MemberRoleCode],
       sm.[IsInService],
       a.[EntityId]            AS [AssetEntityId],
       a.[Name]                AS [AssetName],
       a.[AssetTypeCode],
       ru.[TextValue]          AS [RatioInUse],
       CASE WHEN r.[Primary] IS NOT NULL AND r.[Secondary] IS NOT NULL AND r.[Secondary] <> 0 THEN r.[Primary] / r.[Secondary] END AS [Ratio],
       sm.[Notes]
FROM [scheme].[SchemeMember] sm
JOIN [asset].[Asset] a ON a.[EntityId] = sm.[MemberEntityId] AND a.[ValidTo] IS NULL AND a.[IsDeleted] = 0
OUTER APPLY (SELECT TOP (1) cv.[TextValue] FROM [asset].[CharacteristicValue] cv
             JOIN [config].[CharacteristicDefinition] cd ON cd.[RowId] = cv.[CharacteristicDefinitionRowId] AND cd.[CharacteristicKey] = N'RatioInUse'
             WHERE cv.[HostEntityId] = a.[EntityId] AND cv.[ValidTo] IS NULL AND cv.[IsDeleted] = 0
             ORDER BY cv.[RowSeq] DESC) ru
OUTER APPLY (SELECT TRY_CONVERT(DECIMAL(18,4), LTRIM(RTRIM(LEFT(x.[T], x.[P] - 1))))      AS [Primary],
                    TRY_CONVERT(DECIMAL(18,4), LTRIM(RTRIM(SUBSTRING(x.[T], x.[P] + 1, 40)))) AS [Secondary]
             FROM (SELECT REPLACE(REPLACE(ru.[TextValue], N'-', N':'), N'/', N':') AS [T]) y
             CROSS APPLY (SELECT y.[T], CHARINDEX(N':', y.[T]) AS [P]) x
             WHERE x.[P] > 1) r
WHERE sm.[MemberKind] = N'Asset' AND sm.[MemberRoleCode] IN (N'CtSource', N'VtSource')
  AND sm.[ValidTo] IS NULL AND sm.[IsDeleted] = 0;
GO
GRANT SELECT ON [scheme].[vSchemeSource] TO [app_execute];
GO
