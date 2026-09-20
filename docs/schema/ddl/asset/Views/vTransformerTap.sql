-- #213 (2026-09-20) (named vTransformerTap: the generator owns vWindingTap as the table's current view): a secondary winding's taps — terminals, ratio (as text and as a number: "1200:5" reads 240), and
-- whether the wires are landed on it (the winding's TapInUseEntityId). Keyed TapEntityId, not EntityId, for the reason
-- #212 found: the API scopes a view's EntityId as the family of its base table, so a tap's id would be checked as an
-- asset's; AssetEntityId carries the scope. Hand-written; base tables in the current-row form (#169).
CREATE VIEW [asset].[vTransformerTap] AS
SELECT t.[EntityId]           AS [TapEntityId],
       t.[RowId],
       t.[WindingEntityId],
       w.[AssetEntityId],
       w.[Code]               AS [WindingCode],
       t.[TapNo],
       t.[Terminals],
       t.[Ratio]              AS [RatioText],
       CASE WHEN r.[Primary] IS NOT NULL AND r.[Secondary] IS NOT NULL AND r.[Secondary] <> 0 THEN r.[Primary] / r.[Secondary] END AS [Ratio],
       CONVERT(BIT, CASE WHEN w.[TapInUseEntityId] = t.[EntityId] THEN 1 ELSE 0 END) AS [IsInUse],
       t.[Notes],
       t.[ValidFrom],
       t.[CreatedBy], t.[CreatedAt], t.[ModifiedBy], t.[ModifiedAt]
FROM [asset].[WindingTap] t
JOIN [asset].[InstrumentWinding] w ON w.[EntityId] = t.[WindingEntityId] AND w.[ValidTo] IS NULL AND w.[IsDeleted] = 0
OUTER APPLY (SELECT TRY_CONVERT(DECIMAL(18,4), LTRIM(RTRIM(LEFT(x.[T], x.[P] - 1))))      AS [Primary],
                    TRY_CONVERT(DECIMAL(18,4), LTRIM(RTRIM(SUBSTRING(x.[T], x.[P] + 1, 40)))) AS [Secondary]
             FROM (SELECT REPLACE(REPLACE(t.[Ratio], N'-', N':'), N'/', N':') AS [T]) y
             CROSS APPLY (SELECT y.[T], CHARINDEX(N':', y.[T]) AS [P]) x
             WHERE x.[P] > 1) r
WHERE t.[ValidTo] IS NULL AND t.[IsDeleted] = 0;
GO
GRANT SELECT ON [asset].[vTransformerTap] TO [app_execute];
GO
