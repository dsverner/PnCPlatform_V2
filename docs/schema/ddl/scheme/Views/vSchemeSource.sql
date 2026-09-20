-- #201 (2026-09-19): a scheme's instrument-transformer sources — its SchemeMember rows of role CtSource or VtSource whose
-- member is an asset — with the transformer's name, type and ratio in use (the CT_Template / VT_Template characteristic),
-- and that ratio read as a number so a relay's CTR / PTR / SPTR can be checked against it: "1200:5", "1200-5" and "1200/5"
-- all read 240. The record's Analog inputs tab and the transformer page read it.
-- #206 (2026-09-20): the SyncVtSource role (the single-phase PT feeding a 25's sync input) is a source too; Phases, whether
-- the transformer is placed yet, and the member's Notes (the connection note a person writes: "two CTs paralleled",
-- "secondary winding S2") come with each row.
-- Hand-written; base tables in the current-row form (#169).
CREATE VIEW [scheme].[vSchemeSource] AS
SELECT sm.[SchemeEntityId],
       sm.[EntityId]           AS [MemberEntityId],
       sm.[MemberRoleCode],
       sm.[IsInService],
       a.[EntityId]            AS [AssetEntityId],
       a.[Name]                AS [AssetName],
       a.[AssetTypeCode],
       a.[Status]              AS [AssetStatus],
       ru.[TextValue]          AS [RatioInUse],
       CASE WHEN r.[Primary] IS NOT NULL AND r.[Secondary] IS NOT NULL AND r.[Secondary] <> 0 THEN r.[Primary] / r.[Secondary] END AS [Ratio],
       ph.[IntegerValue]       AS [Phases],
       CONVERT(BIT, CASE WHEN pl.[NodeEntityId] IS NULL THEN 0 ELSE 1 END) AS [IsPlaced],
       sm.[Notes]
FROM [scheme].[SchemeMember] sm
JOIN [asset].[Asset] a ON a.[EntityId] = sm.[MemberEntityId] AND a.[ValidTo] IS NULL AND a.[IsDeleted] = 0
OUTER APPLY (SELECT TOP (1) cv.[TextValue] FROM [asset].[CharacteristicValue] cv
             JOIN [config].[CharacteristicDefinition] cd ON cd.[RowId] = cv.[CharacteristicDefinitionRowId] AND cd.[CharacteristicKey] = N'RatioInUse'
             WHERE cv.[HostEntityId] = a.[EntityId] AND cv.[ValidTo] IS NULL AND cv.[IsDeleted] = 0
             ORDER BY cv.[RowSeq] DESC) ru
OUTER APPLY (SELECT TOP (1) cv.[IntegerValue] FROM [asset].[CharacteristicValue] cv
             JOIN [config].[CharacteristicDefinition] cd ON cd.[RowId] = cv.[CharacteristicDefinitionRowId] AND cd.[CharacteristicKey] = N'Phases'
             WHERE cv.[HostEntityId] = a.[EntityId] AND cv.[ValidTo] IS NULL AND cv.[IsDeleted] = 0
             ORDER BY cv.[RowSeq] DESC) ph
OUTER APPLY (SELECT TOP (1) p.[NodeEntityId] FROM [asset].[Placement] p
             WHERE p.[AssetEntityId] = a.[EntityId] AND p.[NodeEntityId] IS NOT NULL AND p.[ValidTo] IS NULL AND p.[IsDeleted] = 0
             ORDER BY p.[RowSeq] DESC) pl
OUTER APPLY (SELECT TRY_CONVERT(DECIMAL(18,4), LTRIM(RTRIM(LEFT(x.[T], x.[P] - 1))))      AS [Primary],
                    TRY_CONVERT(DECIMAL(18,4), LTRIM(RTRIM(SUBSTRING(x.[T], x.[P] + 1, 40)))) AS [Secondary]
             FROM (SELECT REPLACE(REPLACE(ru.[TextValue], N'-', N':'), N'/', N':') AS [T]) y
             CROSS APPLY (SELECT y.[T], CHARINDEX(N':', y.[T]) AS [P]) x
             WHERE x.[P] > 1) r
WHERE sm.[MemberKind] = N'Asset' AND sm.[MemberRoleCode] IN (N'CtSource', N'VtSource', N'SyncVtSource')
  AND sm.[ValidTo] IS NULL AND sm.[IsDeleted] = 0;
GO
GRANT SELECT ON [scheme].[vSchemeSource] TO [app_execute];
GO
