-- SCHEMA-DESIGN §7.6 (122). Class AppendOnly. The row versions of every in-service configuration file,
-- condition and scheme membership as-of the event, captured when the operation is raised (PROCEDURES.md
-- #13), so a later correction never changes what was recorded. SubjectRowId is a fact version (RowId).
CREATE TABLE [scheme].[ProtectionOperationSnapshot] (
    [SnapshotId]         BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_ProtectionOperationSnapshot] PRIMARY KEY CLUSTERED,
    [OperationEntityId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_ProtectionOperationSnapshot_Operation] REFERENCES [scheme].[ProtectionOperationRegistry] ([EntityId]),
    [SubjectKind]        NVARCHAR(40)     NOT NULL CONSTRAINT [CK_ProtectionOperationSnapshot_Kind] CHECK ([SubjectKind] IN (N'ConfigurationFileRevision', N'ProtectionCondition', N'SchemeMember')),
    [SubjectRowId]       UNIQUEIDENTIFIER NOT NULL,
    [CapturedAt]         DATETIMEOFFSET(7) NOT NULL CONSTRAINT [DF_ProtectionOperationSnapshot_CapturedAt] DEFAULT SYSDATETIMEOFFSET()
);
GO
CREATE INDEX [IX_ProtectionOperationSnapshot_Operation] ON [scheme].[ProtectionOperationSnapshot] ([OperationEntityId]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'scheme', @level1type = N'TABLE', @level1name = N'ProtectionOperationSnapshot';
GO
