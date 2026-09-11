-- SCHEMA-DESIGN §8.3 (127). Hand-written: the design names IsInServiceUnapproved as a computed column of
-- ConfigurationFile, but it needs Revision.Status (another table), so it is computed here. In service
-- while the revision is not approved is the transient discrepancy state that raises a finding.
CREATE VIEW [document].[vConfigurationFileStatus] AS
SELECT cf.[RevisionRowId], cf.[DeviceEntityId], cf.[FileKind], cf.[CaptureKind],
       cf.[InServiceFrom], cf.[InServiceTo],
       r.[DocumentEntityId], r.[RevisionLabel], r.[Status] AS [RevisionStatus],
       IsInService = CASE WHEN cf.[InServiceFrom] IS NOT NULL AND cf.[InServiceFrom] <= SYSDATETIMEOFFSET()
                               AND (cf.[InServiceTo] IS NULL OR cf.[InServiceTo] > SYSDATETIMEOFFSET()) THEN 1 ELSE 0 END,
       IsInServiceUnapproved = CASE WHEN cf.[InServiceFrom] IS NOT NULL AND cf.[InServiceFrom] <= SYSDATETIMEOFFSET()
                               AND (cf.[InServiceTo] IS NULL OR cf.[InServiceTo] > SYSDATETIMEOFFSET())
                               AND r.[Status] NOT IN (N'Approved', N'Issued') THEN 1 ELSE 0 END
FROM [document].[vConfigurationFile] cf
JOIN [document].[vRevision] r ON r.[RowId] = cf.[RevisionRowId];
GO
GRANT SELECT ON [document].[vConfigurationFileStatus] TO [app_execute];
GO
