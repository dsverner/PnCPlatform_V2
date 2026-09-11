-- Hand-written read model. SCHEMA-DESIGN §5; PLATFORM-ARCHITECTURE §2.3, §3.4.
--
-- One row per obligation rule, with the state of its versions: which is Effective, whether a Draft is
-- waiting, and whether it has a scope the engine can actually read.
--
-- Why a view: the client was deriving this by paging `config.vDefinitionVersion`, which holds 1,618
-- rows across every definition kind. The dispatcher clamps a page to 500, so the answer was drawn
-- from an arbitrary third of the table and a rule's real status was often simply absent — the Run
-- button stayed disabled with no error to show for it. Found on DEV 2026-09-09.
--
-- `HasScope` is deliberately JSON_QUERY rather than JSON_VALUE, matching what RunRuleEffective and
-- RunRulePreview do: they read the canonical node, and JSON_QUERY returns NULL for a scalar. A rule
-- whose scope was stored as text therefore reads as having none — which is exactly the truth, since
-- the engine cannot see it either.
CREATE VIEW [compliance].[vObligationRule] AS
SELECT d.[EntityId]                         AS [DefinitionEntityId],
       d.[DefinitionKey],
       d.[Name],
       d.[Description],
       eff.[RowId]                          AS [EffectiveVersionRowId],
       eff.[VersionNumber]                  AS [EffectiveVersionNumber],
       eff.[EffectiveFrom],
       drafts.[RowId]                        AS [DraftVersionRowId],
       drafts.[VersionNumber]                AS [DraftVersionNumber],
       CASE WHEN eff.[RowId] IS NOT NULL THEN CONVERT(BIT, 1) ELSE CONVERT(BIT, 0) END AS [IsEffective],
       CASE WHEN JSON_QUERY(eff.[PayloadText], '$.scope') IS NOT NULL
            THEN CONVERT(BIT, 1) ELSE CONVERT(BIT, 0) END                              AS [EffectiveHasScope],
       JSON_VALUE(COALESCE(eff.[PayloadText], drafts.[PayloadText]), '$.scopeText')     AS [ScopeText],
       JSON_VALUE(COALESCE(eff.[PayloadText], drafts.[PayloadText]), '$.cadenceText')   AS [CadenceText],
       -- The requirement the rule is for. A rule exists *for* a requirement — PRC-005 P1 is
       -- "microprocessor relays every six years" and the rule is how the platform knows which devices
       -- that is — so the screen hangs rules off the requirement rather than listing them apart from
       -- it. The payload names it either by entity id or by standard/version/number, and
       -- fResolveRequirement turns either into the id. Added 2026-09-10 after the owner pointed out
       -- that selecting a requirement changed nothing on screen.
       [compliance].[fResolveRequirement](COALESCE(eff.[PayloadText], drafts.[PayloadText])) AS [RequirementEntityId],
       (SELECT COUNT(*) FROM [compliance].[vObligationInstance] i
        WHERE i.[RuleDefinitionVersionRowId] = eff.[RowId])                             AS [OpenInstances]
FROM [config].[vDefinition] d
OUTER APPLY (SELECT TOP 1 v.[RowId], v.[VersionNumber], v.[EffectiveFrom], v.[PayloadText]
             FROM [config].[vDefinitionVersion] v
             WHERE v.[DefinitionEntityId] = d.[EntityId] AND v.[Status] = N'Effective'
             ORDER BY v.[VersionNumber] DESC) eff
OUTER APPLY (SELECT TOP 1 v.[RowId], v.[VersionNumber], v.[PayloadText]
             FROM [config].[vDefinitionVersion] v
             WHERE v.[DefinitionEntityId] = d.[EntityId] AND v.[Status] = N'Draft'
             ORDER BY v.[VersionNumber] DESC) drafts
WHERE d.[DefinitionKind] = N'Program.ObligationRule';
GO
GRANT SELECT ON [compliance].[vObligationRule] TO [app_execute];
GO
