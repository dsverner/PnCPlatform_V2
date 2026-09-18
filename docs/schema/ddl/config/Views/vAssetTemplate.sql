-- #185 (2026-09-18): the device templates, one row per (template, model) — what the Templates menu lists.
--
-- The owner, looking for SEL221F_Template: "How do I get to this screen from the main application screen. I can't find
-- it... we must always build in an intuitive way for the users to find this functionality. Since we are looking at
-- Templates, I was expecting to see a Templates tab on the left hand side of the screen." A template is a
-- CharacteristicSchema.AssetTemplate definition (#184) bound to its models through config.DefinitionAppliesTo; this
-- view walks that binding out to the model so a list screen can show "SEL221F_Template · SEL-221F · Schweitzer" and
-- open the template by ModelId.
--
-- Base tables in the current-row form the filtered indexes use (#169): the definition and its Effective version, the
-- applies-to row of dimension Model, the model, its manufacturer's party entity for the name.
CREATE VIEW [config].[vAssetTemplate]
AS
SELECT d.[EntityId]            AS [DefinitionEntityId],
       d.[DefinitionKey],
       d.[Name],
       d.[Description],
       dv.[RowId]              AS [DefinitionVersionRowId],
       dv.[VersionNumber],
       m.[ModelId],
       m.[ModelCode],
       m.[ModelName],
       m.[Technology],
       me.[Name]               AS [Manufacturer]
FROM [config].[Definition] d
JOIN [config].[DefinitionVersion] dv ON dv.[DefinitionEntityId] = d.[EntityId] AND dv.[IsDeleted] = 0 AND dv.[Status] = N'Effective'
JOIN [config].[DefinitionAppliesTo] a ON a.[DefinitionVersionRowId] = dv.[RowId] AND a.[ValidTo] IS NULL AND a.[IsDeleted] = 0
                                      AND a.[DimensionCode] = N'Model'
JOIN [ref].[Model] m ON m.[ModelId] = a.[ValueEntityId] AND m.[IsActive] = 1
LEFT JOIN [ref].[Manufacturer] mf ON mf.[ManufacturerId] = m.[ManufacturerId]
LEFT JOIN [party].[Entity] me ON me.[EntityId] = mf.[EntityEntityId] AND me.[ValidTo] IS NULL AND me.[IsDeleted] = 0
WHERE d.[DefinitionKind] = N'CharacteristicSchema.AssetTemplate' AND d.[IsDeleted] = 0;
GO
GRANT SELECT ON [config].[vAssetTemplate] TO [app_execute];
GO
