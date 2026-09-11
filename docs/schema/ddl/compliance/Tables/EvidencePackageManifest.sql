-- SCHEMA-DESIGN §12.7 (167): every row version and file the package contains, so it reproduces.
CREATE TABLE [compliance].[EvidencePackageManifest] (
    [ManifestId]         BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_EvidencePackageManifest] PRIMARY KEY CLUSTERED,
    [PackageEntityId]    UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_EvidencePackageManifest_Package] REFERENCES [compliance].[EvidencePackageRegistry] ([EntityId]),
    [ItemKind]           NVARCHAR(40)     NOT NULL CONSTRAINT [CK_EvidencePackageManifest_ItemKind] CHECK ([ItemKind] IN (N'ObligationInstance', N'Record', N'EvidenceLink', N'Assertion', N'ConfigurationFileRevision', N'File', N'DefinitionVersion')),
    [ItemRowId]          UNIQUEIDENTIFIER NOT NULL,
    [FileSha256]         BINARY(32)       NULL
);
GO
CREATE INDEX [IX_EvidencePackageManifest_Package] ON [compliance].[EvidencePackageManifest] ([PackageEntityId]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'compliance', @level1type = N'TABLE', @level1name = N'EvidencePackageManifest';
GO
