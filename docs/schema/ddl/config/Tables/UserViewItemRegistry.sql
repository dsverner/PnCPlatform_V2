-- Registry of config.UserViewItem identities (SCHEMA-DESIGN §0.3, decision 67): one row per thing, for life.
-- Foreign keys that mean "the thing" reference this table; "the fact version" references RowId.
CREATE TABLE [config].[UserViewItemRegistry] (
    [EntityId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [PK_UserViewItemRegistry] PRIMARY KEY CLUSTERED,
    [CreatedAt] DATETIMEOFFSET(7) NOT NULL CONSTRAINT [DF_UserViewItemRegistry_CreatedAt] DEFAULT SYSDATETIMEOFFSET()
);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Registry',
    @level0type = N'SCHEMA', @level0name = N'config', @level1type = N'TABLE', @level1name = N'UserViewItemRegistry';
GO
