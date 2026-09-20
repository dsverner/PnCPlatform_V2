-- #214 (2026-09-20): when a device was last evaluated and by which pass — "Evaluated 16:43 · hourly pass" on its Compliance
-- tab. Keyed DeviceEntityId (scoped as the device). The run's own row gives the trigger and its counts.
CREATE VIEW [compliance].[vDeviceEvaluation] AS
SELECT e.[SubjectEntityId]  AS [DeviceEntityId],
       e.[LastEvaluatedAt],
       e.[LastTrigger],
       e.[LastRunId],
       e.[RulesEvaluated],
       r.[StartedAt]         AS [RunStartedAt],
       r.[CompletedAt]       AS [RunCompletedAt],
       r.[SubjectsScoped]    AS [RunSubjectsScoped],
       r.[Notes]             AS [RunNotes]
FROM [compliance].[SubjectEvaluation] e
JOIN [compliance].[RuleEvaluationRun] r ON r.[RunId] = e.[LastRunId]
WHERE e.[SubjectKind] = N'Device' AND e.[IsActive] = 1;
GO
GRANT SELECT ON [compliance].[vDeviceEvaluation] TO [app_execute];
GO
