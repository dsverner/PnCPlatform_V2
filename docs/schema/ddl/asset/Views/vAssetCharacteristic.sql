-- Hand-written read model. SCHEMA-DESIGN §2, §5; PLATFORM-ARCHITECTURE §3.4, decision 210.
--
-- An asset's characteristics with the *definition* that describes each one: its key, label, data type,
-- unit, display group and order. This is what makes an inspector definition-rendered rather than coded
-- per subject — the screen asks for the characteristics of an asset and lays out whatever comes back,
-- so a characteristic added to a template appears with no change to any code.
--
-- The typed value is left in its own column rather than flattened to text: the browser needs the type
-- to align numbers, format dates and render a Boolean, and flattening here would throw that away.
CREATE VIEW [asset].[vAssetCharacteristic] AS
SELECT cv.[RowSeq],
       cv.[RowId],
       cv.[EntityId],
       cv.[HostEntityId]                AS [AssetEntityId],
       cd.[RowId]                       AS [CharacteristicDefinitionRowId],
       cd.[CharacteristicKey],
       cd.[Name]                        AS [CharacteristicName],
       cd.[Description]                 AS [CharacteristicDescription],
       cd.[DataType],
       cd.[DisplayGroup],
       cd.[DisplayOrder],
       cd.[IsRequired],
       cd.[IsCatalogueFact],
       COALESCE(cv.[UnitOverrideCode], cd.[UnitCode]) AS [UnitCode],
       cv.[TextValue],
       cv.[IntegerValue],
       cv.[DecimalValue],
       cv.[BooleanValue],
       cv.[DateTimeValue],
       cv.[ReferenceEntityId],
       cv.[SourceRecordRowId],
       cv.[ValidFrom],
       cv.[ValidTo]
FROM [asset].[vCharacteristicValue] cv
JOIN [config].[vCharacteristicDefinition] cd ON cd.[RowId] = cv.[CharacteristicDefinitionRowId];
GO
GRANT SELECT ON [asset].[vAssetCharacteristic] TO [app_execute];
GO
