-- PROCEDURE-ENGINE §6 (#41; W4, decision #116). The migration list is derived, never stored: every running or held
-- instance whose version set pins a version of a procedure that now has a newer Effective version (directly or as a
-- callee), and that has no InstanceMigration ruling for that newer version yet. Until ruled on, the instance continues
-- on its pinned version and shows here as awaiting a version ruling. A ruling is process.InstanceMigration_Add.
CREATE VIEW [process].[vMigrationList] AS
SELECT i.[EntityId] AS [ProcedureInstanceEntityId], i.[SubjectKind], i.[SubjectEntityId], i.[WorkRequestEntityId], i.[State], i.[StartedAt],
       vs.[CalleeKey], vs.[DefinitionVersionRowId] AS [PinnedVersionRowId], pinned.[VersionNumber] AS [PinnedVersionNumber],
       cur.[RowId] AS [CurrentVersionRowId], cur.[VersionNumber] AS [CurrentVersionNumber], cur.[EffectiveFrom] AS [CurrentEffectiveFrom],
       CASE WHEN vs.[CalleeKey] = rootdef.[DefinitionKey] THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS [IsRootProcedure]
FROM [process].[ProcedureInstance] i
JOIN [process].[InstanceVersionSet] vs ON vs.[ProcedureInstanceEntityId] = i.[EntityId] AND vs.[IsDeleted] = 0
JOIN [config].[DefinitionVersion] pinned ON pinned.[RowId] = vs.[DefinitionVersionRowId]
JOIN [config].[DefinitionVersion] rootv ON rootv.[RowId] = i.[DefinitionVersionRowId]
JOIN [config].[Definition] rootdef ON rootdef.[EntityId] = rootv.[DefinitionEntityId]
JOIN [config].[DefinitionVersion] cur ON cur.[DefinitionEntityId] = pinned.[DefinitionEntityId] AND cur.[IsDeleted] = 0 AND cur.[Status] = N'Effective'
     AND cur.[VersionNumber] > pinned.[VersionNumber]
WHERE i.[IsDeleted] = 0 AND i.[State] IN (N'Running', N'Held')
  AND NOT EXISTS (SELECT 1 FROM [process].[InstanceMigration] m WHERE m.[ProcedureInstanceEntityId] = i.[EntityId] AND m.[ToDefinitionVersionRowId] = cur.[RowId] AND m.[IsDeleted] = 0);
GO
GRANT SELECT ON [process].[vMigrationList] TO [app_execute];
GO
