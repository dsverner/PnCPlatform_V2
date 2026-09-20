-- #214 (2026-09-20): the evaluation requests — pending first, then the most recent served — with what changed, who changed
-- it and the pass that answered. The Compliance area's Evaluation screen reads this; the smoke waits on it (IsPending).
-- Named so because the generator owns vEvaluationRequest as the table's own view. SubjectEntityId here is the thing that
-- changed (a device, a primary asset, a node, a scheme) — a scoped reader sees the requests about their own subjects.
CREATE VIEW [compliance].[vEvaluationQueue] AS
SELECT r.[RequestId],
       r.[SubjectKind],
       r.[SubjectEntityId],
       COALESCE(a.[Name], n.[Name], sc.[Name], CASE WHEN r.[SubjectKind] = N'All' THEN N'every candidate device' END) AS [SubjectName],
       r.[Reason],
       r.[RequestedAt],
       r.[ActorId],
       COALESCE(p.[DisplayName], ac.[SystemName]) AS [RequestedByName],
       CONVERT(BIT, CASE WHEN r.[ProcessedAt] IS NULL THEN 1 ELSE 0 END) AS [IsPending],
       r.[ProcessedAt],
       r.[RunId],
       r.[DevicesFound],
       run.[Trigger]      AS [RunTrigger],
       run.[StartedAt]    AS [RunStartedAt],
       run.[CompletedAt]  AS [RunCompletedAt],
       run.[InstancesOpened], run.[InstancesClosed], run.[InstancesUnchanged]
FROM [compliance].[EvaluationRequest] r
LEFT JOIN [personnel].[Actor] ac ON ac.[ActorId] = r.[ActorId]
LEFT JOIN [personnel].[Person] p ON p.[EntityId] = ac.[PersonEntityId] AND p.[ValidTo] IS NULL AND p.[IsDeleted] = 0
LEFT JOIN [asset].[Asset] a ON a.[EntityId] = r.[SubjectEntityId] AND a.[ValidTo] IS NULL AND a.[IsDeleted] = 0 AND r.[SubjectKind] IN (N'Device', N'Asset')
LEFT JOIN [location].[Node] n ON n.[EntityId] = r.[SubjectEntityId] AND n.[ValidTo] IS NULL AND n.[IsDeleted] = 0 AND r.[SubjectKind] = N'Node'
LEFT JOIN [scheme].[Scheme] sc ON sc.[EntityId] = r.[SubjectEntityId] AND sc.[ValidTo] IS NULL AND sc.[IsDeleted] = 0 AND r.[SubjectKind] = N'Scheme'
LEFT JOIN [compliance].[RuleEvaluationRun] run ON run.[RunId] = r.[RunId];
GO
GRANT SELECT ON [compliance].[vEvaluationQueue] TO [app_execute];
GO
