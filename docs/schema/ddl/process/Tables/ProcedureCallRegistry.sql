-- Registry of process.ProcedureCall identities (SCHEMA-DESIGN §0.3, decision 67): one row per projected call, for life.
CREATE TABLE [process].[ProcedureCallRegistry] (
    [EntityId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [PK_ProcedureCallRegistry] PRIMARY KEY CLUSTERED,
    [CreatedAt] DATETIMEOFFSET(7) NOT NULL CONSTRAINT [DF_ProcedureCallRegistry_CreatedAt] DEFAULT SYSDATETIMEOFFSET()
);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Registry',
    @level0type = N'SCHEMA', @level0name = N'process', @level1type = N'TABLE', @level1name = N'ProcedureCallRegistry';
GO
