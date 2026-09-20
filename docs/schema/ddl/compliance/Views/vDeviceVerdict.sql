-- #214 (2026-09-20): a device's standing verdicts — one row per effective rule (applies / does not apply / undetermined /
-- could not be evaluated, with the reason and the reads) and per classification derivation (the value and why). Keyed
-- DeviceEntityId so the API scopes it as the device (Asset family). The rule's standard, requirement and evidence note ride
-- along so the Compliance tab needs one read. Joins the rule, requirement and standard read models (small, device-scoped;
-- the #169 base-table rule is for the estate-wide lists).
CREATE VIEW [compliance].[vDeviceVerdict] AS
SELECT v.[SubjectEntityId]        AS [DeviceEntityId],
       v.[VerdictKind],
       d.[DefinitionKey]          AS [RuleKey],
       d.[Name]                   AS [RuleName],
       dv.[VersionNumber],
       v.[Result],
       v.[Reason],
       v.[ReadsJson],
       v.[Error],
       v.[SinceAt],
       v.[SinceRunId],
       q.[RequirementNumber],
       q.[Title]                  AS [RequirementTitle],
       sv.[StandardCode],
       sv.[VersionLabel]          AS [StandardVersion],
       r.[EvidenceNote],
       r.[CadenceText],
       CASE WHEN v.[VerdictKind] = N'Derivation' THEN JSON_VALUE(dv.[PayloadText], '$.kind') END AS [DerivationKind]
FROM [compliance].[SubjectVerdict] v
JOIN [config].[Definition] d ON d.[EntityId] = v.[DefinitionEntityId] AND d.[IsDeleted] = 0
JOIN [config].[DefinitionVersion] dv ON dv.[RowId] = v.[VersionRowId]
LEFT JOIN [compliance].[vObligationRule] r ON r.[DefinitionEntityId] = v.[DefinitionEntityId] AND v.[VerdictKind] = N'Rule'
LEFT JOIN [compliance].[vRequirement] q ON q.[EntityId] = r.[RequirementEntityId]
LEFT JOIN [compliance].[vStandardVersion] sv ON sv.[RowId] = q.[StandardVersionRowId]
WHERE v.[SubjectKind] = N'Device' AND v.[IsActive] = 1;
GO
GRANT SELECT ON [compliance].[vDeviceVerdict] TO [app_execute];
GO
