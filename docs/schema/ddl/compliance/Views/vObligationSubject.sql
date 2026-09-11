-- Hand-written read model. SCHEMA-DESIGN §5, §12.5; PLATFORM-ARCHITECTURE §2.3, §3.4.
--
-- Everything on an obligation board EXCEPT when it is due — the names, the requirement, the work and
-- the evidence — for one live obligation per row.
--
-- Why this exists beside compliance.vObligationBoard: rule evaluation moved into the application
-- (.planning/CALCULATION-ENGINE-DESIGN.md §6), and a view cannot call an evaluator that has left the
-- database. vObligationBoard derives DueAt through fObligationDue and so cannot outlive it. This view
-- is the same read model with the derivation taken out and RuleDefinitionVersionRowId carried through
-- instead, which is all the application needs to derive due itself — measured at 0.02 ms per row over
-- 2,481 obligations on DEV, because every obligation of one rule shares one cadence.
--
-- §12.5 is unchanged and deliberately so: "due is derived, never stored". What moves is where the
-- derivation runs, not whether it is a column.
--
-- Subject naming spans kinds, so the name is coalesced across the four subject kinds that
-- compliance.fRuleSubjects can return. A subject whose name cannot be resolved shows its kind and id
-- rather than an empty cell — an obligation with no visible subject is worse than an ugly one.
--
-- Only Open and Satisfied appear, which is the population vObligationBoard carried: an obligation that
-- is NotApplicable or Superseded is history, and Exception is somebody's open decision with a clock of
-- its own (§12.8).
CREATE VIEW [compliance].[vObligationSubject] AS
SELECT i.[RowId],
       i.[EntityId],
       i.[SubjectKind],
       i.[SubjectEntityId],
       COALESCE(a.[Name], n.[Name], s.[Name], p.[DisplayName],
                i.[SubjectKind] + N' ' + CONVERT(NVARCHAR(36), i.[SubjectEntityId])) AS [SubjectName],
       i.[RuleDefinitionVersionRowId],
       d.[DefinitionKey]                           AS [RuleDefinitionKey],
       d.[Name]                                    AS [RuleName],
       i.[RequirementEntityId],
       r.[RequirementNumber],
       r.[SubRequirement],
       r.[Title]                                   AS [RequirementTitle],
       sv.[StandardCode],
       sv.[VersionLabel]                           AS [StandardVersion],
       i.[PeriodStartAt],
       i.[PeriodEndAt],
       i.[Status],
       i.[RaisedWorkRequestEntityId],
       w.[Title]                                   AS [WorkRequestTitle],
       w.[PlannedStartAt]                          AS [WorkPlannedStartAt],
       w.[ActualEndAt]                             AS [WorkCompletedAt],
       -- Evidence judged against this obligation, across every revision of it.
       --
       -- EvidenceLink pins to a RowId, which is right: it records which *state* of the instance was
       -- judged. But an instance is revised into a new row whenever the engine changes its status, so
       -- counting on RowId made evidence vanish from the board at the moment it took effect — the run
       -- that turned an obligation Satisfied created a new row, and the link stayed on the old one.
       -- Seen on DEV 2026-09-09. The board therefore counts across the entity's whole history.
       (SELECT COUNT(*) FROM [compliance].[vEvidenceLink] el
        JOIN [compliance].[ObligationInstance] oi ON oi.[RowId] = el.[ObligationInstanceRowId]
        WHERE oi.[EntityId] = i.[EntityId])                        AS [EvidenceCount],
       (SELECT TOP 1 el.[Sufficiency] FROM [compliance].[vEvidenceLink] el
        JOIN [compliance].[ObligationInstance] oi ON oi.[RowId] = el.[ObligationInstanceRowId]
        WHERE oi.[EntityId] = i.[EntityId]
        ORDER BY CASE el.[Sufficiency] WHEN N'Sufficient' THEN 1 WHEN N'Partial' THEN 2 ELSE 3 END,
                 el.[JudgedAt] DESC)                               AS [BestSufficiency]
FROM [compliance].[vObligationInstance] i
JOIN [config].[DefinitionVersion] dvr ON dvr.[RowId] = i.[RuleDefinitionVersionRowId]
JOIN [config].[Definition] d ON d.[EntityId] = dvr.[DefinitionEntityId]
LEFT JOIN [compliance].[vRequirement] r ON r.[EntityId] = i.[RequirementEntityId]
LEFT JOIN [compliance].[vStandardVersion] sv ON sv.[RowId] = r.[StandardVersionRowId]
LEFT JOIN [work].[vWorkRequest] w ON w.[EntityId] = i.[RaisedWorkRequestEntityId]
LEFT JOIN [asset].[vAsset] a ON a.[EntityId] = i.[SubjectEntityId]
LEFT JOIN [location].[vNode] n ON n.[EntityId] = i.[SubjectEntityId]
LEFT JOIN [scheme].[vScheme] s ON s.[EntityId] = i.[SubjectEntityId]
LEFT JOIN [personnel].[vPerson] p ON p.[EntityId] = i.[SubjectEntityId]
WHERE i.[Status] IN (N'Open', N'Satisfied');
GO
GRANT SELECT ON [compliance].[vObligationSubject] TO [app_execute];
GO
