-- SCHEMA-DESIGN §12.5 (165), decision 54: the fact versions a derivation read — the reverse walk an auditor makes.
CREATE TABLE [compliance].[ObligationInstanceFact] (
    [ObligationInstanceFactId] BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_ObligationInstanceFact] PRIMARY KEY CLUSTERED,
    [ObligationInstanceRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_ObligationInstanceFact_Instance] REFERENCES [compliance].[ObligationInstance] ([RowId]),
    [FactName]           NVARCHAR(200)    NOT NULL,
    [SourceRowId]        UNIQUEIDENTIFIER NULL,
    [ValueAsRead]        NVARCHAR(400)    NULL
);
GO
CREATE INDEX [IX_ObligationInstanceFact_Instance] ON [compliance].[ObligationInstanceFact] ([ObligationInstanceRowId]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'compliance', @level1type = N'TABLE', @level1name = N'ObligationInstanceFact';
GO
