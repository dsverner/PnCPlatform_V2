-- SCHEMA-DESIGN §15.1, §15.3 (182, 184). The Program.BackupPolicy version in force, read by the
-- SQL Agent job (agent_backup) to perform backups and by the application (app_execute) to show it.
-- The payload's fields (schedules, destination by reference, retention, encryption, filegroup
-- treatment, verification, rehearsal cadence, TargetRpoMinutes, TargetRtoMinutes) are the
-- definition's JSON; this view does not interpret them.
CREATE VIEW [config].[vEffectiveBackupPolicy] AS
SELECT d.[DefinitionKey], d.[Name], v.[RowId] AS [VersionRowId], v.[VersionNumber], v.[EffectiveFrom], v.[EffectiveTo],
       v.[ApprovedBy], v.[ApprovedAt], v.[PayloadText], v.[PayloadHash]
FROM [config].[Definition] d
JOIN [config].[DefinitionVersion] v ON v.[DefinitionEntityId] = d.[EntityId] AND v.[IsDeleted] = 0
WHERE d.[DefinitionKind] = N'Program.BackupPolicy' AND d.[IsDeleted] = 0
  AND v.[Status] = N'Effective'
  AND v.[EffectiveFrom] <= SYSDATETIMEOFFSET()
  AND (v.[EffectiveTo] IS NULL OR v.[EffectiveTo] > SYSDATETIMEOFFSET());
GO
GRANT SELECT ON [config].[vEffectiveBackupPolicy] TO [agent_backup];
GO
GRANT SELECT ON [config].[vEffectiveBackupPolicy] TO [app_execute];
GO
