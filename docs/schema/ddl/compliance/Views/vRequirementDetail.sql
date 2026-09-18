-- #185 (2026-09-18): every requirement of every standard, with its standard beside it — what the Compliance menu lists.
--
-- The owner, on the compliance panels the device template carried: "compliance is really a function of it's own,
-- outside of the template. That is PRC-023 will be compulsory, no matter what physical device we are implementing...
-- we need to find a better home for this information." This is that home's read: a standard, its version in force,
-- and each requirement's number, title, summary and evidence guidance, so Directory 4's 23 criteria and A-10 sit under
-- Compliance for every device type rather than on one model's template.
--
-- Base tables in the current-row form (#169): Standard (reference), StandardVersion and Requirement (valid-time).
CREATE VIEW [compliance].[vRequirementDetail]
AS
SELECT s.[StandardCode],
       s.[Family],
       s.[Subject],
       sv.[RowId]              AS [StandardVersionRowId],
       sv.[VersionLabel],
       sv.[EffectiveFrom],
       sv.[TextReference],
       r.[EntityId]            AS [RequirementEntityId],
       r.[RequirementNumber],
       r.[SubRequirement],
       r.[Title],
       r.[Summary],
       r.[EvidenceGuidance],
       r.[SubjectKinds]
FROM [compliance].[Standard] s
JOIN [compliance].[StandardVersion] sv ON sv.[StandardCode] = s.[StandardCode] AND sv.[ValidTo] IS NULL AND sv.[IsDeleted] = 0
JOIN [compliance].[Requirement] r ON r.[StandardVersionRowId] = sv.[RowId] AND r.[ValidTo] IS NULL AND r.[IsDeleted] = 0;
GO
GRANT SELECT ON [compliance].[vRequirementDetail] TO [app_execute];
GO
