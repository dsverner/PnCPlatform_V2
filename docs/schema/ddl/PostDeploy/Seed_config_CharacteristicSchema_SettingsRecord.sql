-- #167 (2026-09-15): the legacy settings record's columnless fields as characteristics of a settings revision (owner: "fine
-- as characteristics since I don't see any value in indexing, grouping etc. on them"). One CharacteristicSchema.RecordTemplate
-- definition, SETTINGS_RECORD, with an Effective version; the record screen laid out whatever it carried.
-- #194 (2026-09-19): the eight classification fields (CLASS, USE, RESPONSIBILITY, BULK_POWER_ELEMENT, PROTECTION_GROUP,
-- ELEMENT, LINE_TYPE, NUMBER_OF_RELAYS) went — the owner: "all can go and the tab removed, I do not trust any of the data
-- in those fields". Version 2 carried the ten instrument-transformer characteristics only.
-- #206 (2026-09-20): the definition is retired. The owner, of the Analog inputs tab's bottom section: "what was imported
-- from the legacy database, which can be retired completely." The ten CT/PT fields were never stored values on DEV — the
-- importer put the legacy strings in the revision record's summary and the tab showed them as placeholders — and those
-- strings are now what Seed_asset_InstrumentTransformersFromLegacy makes the scheme's CT and PT sets from. Soft delete
-- (config.Definition_SoftDelete, generated; audited); idempotent; the summary text is untouched.
-- migration-rule: #206 the legacy CT/PT ratio columns are no longer characteristics of the record — they become the scheme's instrument transformers (Seed_asset_InstrumentTransformersFromLegacy); the SETTINGS_RECORD characteristic schema is retired (#194's classification drop stands)
IF OBJECT_ID(N'[config].[Definition_SoftDelete]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @sys UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @e UNIQUEIDENTIFIER;
SELECT @e = [EntityId] FROM [config].[Definition] WHERE [DefinitionKind] = N'CharacteristicSchema.RecordTemplate' AND [DefinitionKey] = N'SETTINGS_RECORD' AND [IsDeleted] = 0;
IF @e IS NOT NULL
    EXEC [config].[Definition_SoftDelete] @EntityId = @e, @ActorId = @sys;
GO
