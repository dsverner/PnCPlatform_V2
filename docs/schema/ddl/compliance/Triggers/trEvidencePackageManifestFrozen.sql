-- SCHEMA-DESIGN §12.7 (decision 167); PROCEDURES.md #24. The manifest of an approved package is
-- read-only: no row may be appended to it after approval (the table is append-only, so an insert
-- is the only write to refuse).
CREATE TRIGGER [compliance].[trEvidencePackageManifestFrozen] ON [compliance].[EvidencePackageManifest]
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted i JOIN [compliance].[EvidencePackage] p ON p.[EntityId] = i.[PackageEntityId]
               WHERE p.[IsDeleted] = 0 AND p.[ApprovedAt] IS NOT NULL)
        THROW 50354, N'compliance.EvidencePackageManifest: the manifest of an approved evidence package is read-only (§12.7).', 1;
END;
GO
