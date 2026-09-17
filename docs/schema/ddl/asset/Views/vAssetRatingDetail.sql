-- #171 (2026-09-16): a primary asset's ratings as the screens read them — the rating rows current now, with the asset they
-- belong to named. The generated asset.vAssetRating carries the columns alone; this adds the name so the ratings panel and
-- the PRC-023 working can be read without a second query. Hand-written read model, base table in the current-row form (#169).
-- Hand-entered until the ratings connector exists (the owner, 2026-09-16: "make room for the given values in our
-- application… create the connector later") — SourceSystem says which, Source names the document.
CREATE VIEW [asset].[vAssetRatingDetail] AS
SELECT r.[EntityId]                 AS [RatingEntityId],   -- not EntityId: the read scope is the asset's (AssetEntityId), see Catalog.SubjectOf
       r.[AssetEntityId],
       a.[Name]                     AS [AssetName],
       r.[RatingKind],
       r.[Season],
       r.[Amperes],
       r.[Source],
       r.[SourceSystem],
       r.[Notes],
       r.[ValidFrom],
       r.[RowSeq]
FROM [asset].[AssetRating] r
LEFT JOIN [asset].[Asset] a ON a.[EntityId] = r.[AssetEntityId] AND a.[ValidTo] IS NULL AND a.[IsDeleted] = 0
WHERE r.[ValidTo] IS NULL AND r.[IsDeleted] = 0;
GO
GRANT SELECT ON [asset].[vAssetRatingDetail] TO [app_execute];
GO
