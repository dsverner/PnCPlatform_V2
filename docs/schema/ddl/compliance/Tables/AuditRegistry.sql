-- Registry of compliance.Audit identities (SCHEMA-DESIGN §0.3, decision 67): one row per thing, for life.
-- Foreign keys that mean "the thing" reference this table; "the fact version" references RowId.
CREATE TABLE [compliance].[AuditRegistry] (
    [EntityId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [PK_AuditRegistry] PRIMARY KEY CLUSTERED,
    [CreatedAt] DATETIMEOFFSET(7) NOT NULL CONSTRAINT [DF_AuditRegistry_CreatedAt] DEFAULT SYSDATETIMEOFFSET()
);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Registry',
    @level0type = N'SCHEMA', @level0name = N'compliance', @level1type = N'TABLE', @level1name = N'AuditRegistry';
GO
