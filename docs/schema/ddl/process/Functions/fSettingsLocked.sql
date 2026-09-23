-- #231 (2026-09-23): whether a configuration-file revision's settings are fixed because its settings-issue package is in a
-- state that locks its content (process.fStateLocksContent — the settings are on the relay). Read by process.SetParsedSetting
-- (and through it every edit: a direct edit, RebaseDraft, the rationale apply) and by RebaseDraft up front. The package and its
-- lifecycle are found as document.vSettingsRecord finds them. A revision in no package (a migrated outstanding record) is not locked.
CREATE FUNCTION [process].[fSettingsLocked] (@RevisionRowId UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN (
    SELECT CAST(CASE WHEN EXISTS (
        SELECT 1 FROM [document].[SettingsIssuePackageItem] it
        CROSS APPLY (SELECT TOP (1) lc.[CurrentState], lc.[WorkflowDefinitionVersionRowId] FROM [process].[WorkflowInstance] lc
                     WHERE lc.[IsDeleted] = 0 AND lc.[SubjectKind] = N'SettingsIssuePackage' AND lc.[SubjectEntityId] = it.[PackageRevisionRowId] ORDER BY lc.[RowSeq] DESC) lc
        CROSS APPLY [process].[fStateLocksContent](lc.[WorkflowDefinitionVersionRowId], lc.[CurrentState]) lk
        WHERE it.[ConfigurationFileRevisionRowId] = @RevisionRowId AND it.[IsDeleted] = 0 AND it.[ValidTo] IS NULL AND lk.[Locked] = 1)
    THEN 1 ELSE 0 END AS BIT) AS [Locked]
);
GO
