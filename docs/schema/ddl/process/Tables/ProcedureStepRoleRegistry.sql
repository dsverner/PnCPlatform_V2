-- Registry of process.ProcedureStepRole identities (SCHEMA-DESIGN §0.3, decision 67): one row per projected step role, for life.
CREATE TABLE [process].[ProcedureStepRoleRegistry] (
    [EntityId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [PK_ProcedureStepRoleRegistry] PRIMARY KEY CLUSTERED,
    [CreatedAt] DATETIMEOFFSET(7) NOT NULL CONSTRAINT [DF_ProcedureStepRoleRegistry_CreatedAt] DEFAULT SYSDATETIMEOFFSET()
);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Registry',
    @level0type = N'SCHEMA', @level0name = N'process', @level1type = N'TABLE', @level1name = N'ProcedureStepRoleRegistry';
GO
