-- Registry of process.InstanceVersionSet identities (SCHEMA-DESIGN §0.3, decision 67): one row per pinned callee version, for life.
CREATE TABLE [process].[InstanceVersionSetRegistry] (
    [EntityId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [PK_InstanceVersionSetRegistry] PRIMARY KEY CLUSTERED,
    [CreatedAt] DATETIMEOFFSET(7) NOT NULL CONSTRAINT [DF_InstanceVersionSetRegistry_CreatedAt] DEFAULT SYSDATETIMEOFFSET()
);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Registry',
    @level0type = N'SCHEMA', @level0name = N'process', @level1type = N'TABLE', @level1name = N'InstanceVersionSetRegistry';
GO
