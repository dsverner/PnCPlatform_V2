-- SCHEMA-DESIGN §1.2. One row per migrated fact version: which run, which source key, which
-- target EntityId and RowId. Class AppendOnly.
CREATE TABLE [migration].[Provenance] (
    [ProvenanceId]    BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_Provenance] PRIMARY KEY CLUSTERED,
    [RunId]           UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Provenance_Run] REFERENCES [migration].[Run] ([RunId]),
    [TargetSchema]    SYSNAME           NOT NULL,
    [TargetTable]     SYSNAME           NOT NULL,
    [TargetEntityId]  UNIQUEIDENTIFIER  NULL,
    [TargetRowId]     UNIQUEIDENTIFIER  NULL,
    [SourceKey]       NVARCHAR(400)     NOT NULL,
    [SourceRowHash]   BINARY(32)        NULL,
    [Notes]           NVARCHAR(MAX)     NULL
);
GO
CREATE INDEX [IX_Provenance_Run] ON [migration].[Provenance] ([RunId]);
GO
CREATE INDEX [IX_Provenance_Target] ON [migration].[Provenance] ([TargetRowId]);
GO
CREATE INDEX [IX_Provenance_Source] ON [migration].[Provenance] ([TargetSchema], [TargetTable], [SourceKey]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'migration', @level1type = N'TABLE', @level1name = N'Provenance';
GO
