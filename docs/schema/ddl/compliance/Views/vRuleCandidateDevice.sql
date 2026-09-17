-- #171 (2026-09-16). The devices a rule run has anything to say about: those that carry a classification of their own
-- (the BES Cyber Asset flag, external routable connectivity) and those whose scheme protects something classified — the
-- rest have no fact any scope can turn true. compliance.fRuleSubjects narrows nothing (it returns every device on the
-- estate, 6 673 of them); the evaluator reads this instead when no subject is named.
-- Hand-written read model; the device join is the one fRuleSubjects uses (asset.vAsset × device.vDevice).
CREATE VIEW [compliance].[vRuleCandidateDevice] AS
SELECT a.[EntityId] AS [DeviceEntityId], a.[Name]
FROM [asset].[vAsset] a
JOIN [device].[vDevice] d ON d.[EntityId] = a.[EntityId]
WHERE EXISTS (SELECT 1 FROM [asset].[Classification] c
              WHERE c.[SubjectKind] = N'Asset' AND c.[SubjectEntityId] = a.[EntityId]
                AND c.[ValidTo] IS NULL AND c.[IsDeleted] = 0)
   OR EXISTS (SELECT 1 FROM [compliance].[fDeviceProtects](a.[EntityId], SYSDATETIMEOFFSET()) p);
GO
GRANT SELECT ON [compliance].[vRuleCandidateDevice] TO [app_execute];
GO
