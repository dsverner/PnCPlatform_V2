-- Registry of asset.AssetTerminal identities (SCHEMA-DESIGN §0.3, decision 67): one row per thing, for life.
CREATE TABLE [asset].[AssetTerminalRegistry] (
    [EntityId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [PK_AssetTerminalRegistry] PRIMARY KEY CLUSTERED,
    [CreatedAt] DATETIMEOFFSET(7) NOT NULL CONSTRAINT [DF_AssetTerminalRegistry_CreatedAt] DEFAULT SYSDATETIMEOFFSET()
);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Registry',
    @level0type = N'SCHEMA', @level0name = N'asset', @level1type = N'TABLE', @level1name = N'AssetTerminalRegistry';
GO
