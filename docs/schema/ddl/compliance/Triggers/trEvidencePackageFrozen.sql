-- SCHEMA-DESIGN §12.7 (decision 167); PROCEDURES.md #24. Once ApprovedAt is set the package is
-- read-only: any later change to the row — including a soft delete — is refused. A correction is a
-- new package citing the old. The trigger is the only way to stop the generated _Update / _SoftDelete.
CREATE TRIGGER [compliance].[trEvidencePackageFrozen] ON [compliance].[EvidencePackage]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM deleted WHERE [ApprovedAt] IS NOT NULL)
        THROW 50353, N'compliance.EvidencePackage: an approved evidence package is read-only; a correction is a new package citing the old (§12.7).', 1;
END;
GO
