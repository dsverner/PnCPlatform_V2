-- Registry of asset.AssetRating identities (SCHEMA-DESIGN §0.3, decision 67): one row per thing, for life.
CREATE TABLE [asset].[AssetRatingRegistry] (
    [EntityId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [PK_AssetRatingRegistry] PRIMARY KEY CLUSTERED,
    [CreatedAt] DATETIMEOFFSET(7) NOT NULL CONSTRAINT [DF_AssetRatingRegistry_CreatedAt] DEFAULT SYSDATETIMEOFFSET()
);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Registry',
    @level0type = N'SCHEMA', @level0name = N'asset', @level1type = N'TABLE', @level1name = N'AssetRatingRegistry';
GO
