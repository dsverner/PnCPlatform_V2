-- Registry of asset.WindingTap identities (SCHEMA-DESIGN §0.3, decision 67): one row per thing, for life.
-- Foreign keys that mean "the thing" reference this table; "the fact version" references RowId.
CREATE TABLE [asset].[WindingTapRegistry] (
    [EntityId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [PK_WindingTapRegistry] PRIMARY KEY CLUSTERED,
    [CreatedAt] DATETIMEOFFSET(7) NOT NULL CONSTRAINT [DF_WindingTapRegistry_CreatedAt] DEFAULT SYSDATETIMEOFFSET()
);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Registry',
    @level0type = N'SCHEMA', @level0name = N'asset', @level1type = N'TABLE', @level1name = N'WindingTapRegistry';
GO
