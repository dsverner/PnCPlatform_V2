-- #201 (2026-09-19): the instrument transformers and the other Hybrid equipment — lifted from the predecessor's eleven
-- INTERFACE types (PnCPlatform_DEV ref.vAssetType, class Hybrid), which V2 had carried as a class and never as types
-- (DEV held the Hybrid class row and zero Hybrid types). The vision §4.3 (decided 2026-09-03) makes CTs, VTs/PTs and the
-- other auxiliary equipment first-class equipment records in Phase 1 — "a relay setting is expressed against the
-- instrument transformers that feed it; the setting cannot be fully described, reviewed or regenerated without them";
-- §10.1 classes them Hybrid: "one foot at primary voltage, the other on the secondary circuit". The owner, 2026-09-19:
-- "Instrument transformers should be first class devices in their own right with testing (saturation curves, ratio and
-- polarity etc.)."
--
-- Classes by the vision's rule, not by the predecessor's list where the two differ: a panel-mounted auxiliary CT or VT
-- sits wholly on the secondary circuit and is Secondary; a meter the vision lists under Secondary. Both differ from the
-- predecessor (INTERFACE) and are marked so. VT_AUX is new: the legacy record's PT_AUX field names one. IsDevice = 1 for
-- the meters (the §4.1 list: serial, firmware, settings); the transformers, capacitors and traps carry a nameplate, not
-- firmware. The nameplate template (Seed_config_AssetTemplate_InstrumentTransformers) is bound as the type's default
-- template below — the seeds run in name order, so the template exists by the time this runs.
IF OBJECT_ID(N'[ref].[AssetType_Upsert]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
-- Hybrid: one foot at primary voltage
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'CT', @Name = N'Current transformer', @Description = N'A current transformer at primary voltage: free-standing, bushing or slipover; one or more secondary cores, each with its ratio taps (predecessor CT, INTERFACE)', @AssetClassCode = N'Hybrid', @IsDevice = 0, @ActorId = @actor;
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'VT', @Name = N'Voltage transformer', @Description = N'A voltage (potential) transformer at primary voltage, inductive (predecessor VT, INTERFACE)', @AssetClassCode = N'Hybrid', @IsDevice = 0, @ActorId = @actor;
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'COUPLING_CAPACITOR_VT', @Name = N'Coupling capacitor voltage transformer', @Description = N'A CVT: a capacitor divider and a tuned intermediate transformer, often shared with a carrier coupling (predecessor COUPLING_CAPACITOR_VT, INTERFACE)', @AssetClassCode = N'Hybrid', @IsDevice = 0, @ActorId = @actor;
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'CCPD', @Name = N'S&C potential device', @Description = N'The S&C neutral potential device on a capacitor bank: a single-phase voltage taken from the bank neutral, feeding a protection as a VT source (the owner, 2026-09-20, #207: the predecessor''s CCPD code is kept; its name would be read as a coupling-capacitor device, so the type is named S&C potential device)', @AssetClassCode = N'Hybrid', @IsDevice = 0, @ActorId = @actor;
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'COUPLING_CAPACITOR', @Name = N'Coupling capacitor', @Description = N'A power-line-carrier coupling capacitor (predecessor COUPLING_CAPACITOR, INTERFACE)', @AssetClassCode = N'Hybrid', @IsDevice = 0, @ActorId = @actor;
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'WAVE_TRAP', @Name = N'Wave trap', @Description = N'A power-line-carrier line trap (predecessor WAVE_TRAP, INTERFACE)', @AssetClassCode = N'Hybrid', @IsDevice = 0, @ActorId = @actor;
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'METERING_UNIT', @Name = N'Metering unit', @Description = N'A combined CT/VT metering unit at primary voltage (predecessor METERING_UNIT, INTERFACE)', @AssetClassCode = N'Hybrid', @IsDevice = 1, @ActorId = @actor;
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'RECTIFIER_TRANSFORMER', @Name = N'Rectifier transformer', @Description = N'An HVDC converter (rectifier) transformer (predecessor RECTIFIER_TRANSFORMER, INTERFACE)', @AssetClassCode = N'Hybrid', @IsDevice = 0, @IsAssembly = 1, @ActorId = @actor;
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'VOLTAGE_REGULATOR', @Name = N'Voltage regulator', @Description = N'A step voltage regulator (predecessor VOLTAGE_REGULATOR, INTERFACE)', @AssetClassCode = N'Hybrid', @IsDevice = 0, @ActorId = @actor;
-- Secondary by the vision's rule (wholly on the secondary circuit) — the predecessor classed CT_AUX and METER INTERFACE
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'CT_AUX', @Name = N'Auxiliary current transformer', @Description = N'A panel-mounted auxiliary (interposing) CT on the secondary circuit — ratio matching, summation, isolation (predecessor CT_AUX, INTERFACE; Secondary here by the vision §10.1 rule: no foot at primary voltage)', @AssetClassCode = N'Secondary', @IsDevice = 0, @ActorId = @actor;
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'VT_AUX', @Name = N'Auxiliary voltage transformer', @Description = N'A panel-mounted auxiliary VT on the secondary circuit (new in V2: the legacy record''s PT_AUX field names one)', @AssetClassCode = N'Secondary', @IsDevice = 0, @ActorId = @actor;
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'METER', @Name = N'Revenue or check meter', @Description = N'A revenue or check meter (predecessor METER, INTERFACE; Secondary here — the vision §10.1 lists meters with the P&C devices)', @AssetClassCode = N'Secondary', @IsDevice = 1, @ActorId = @actor;
GO
-- the nameplate template as the type's default (ref.AssetType.DefaultTemplateDefinitionEntityId, unused until now)
DECLARE @ct UNIQUEIDENTIFIER = (SELECT [EntityId] FROM [config].[Definition] WHERE [DefinitionKind] = N'CharacteristicSchema.AssetTemplate' AND [DefinitionKey] = N'CT_Template' AND [IsDeleted] = 0);
DECLARE @vt UNIQUEIDENTIFIER = (SELECT [EntityId] FROM [config].[Definition] WHERE [DefinitionKind] = N'CharacteristicSchema.AssetTemplate' AND [DefinitionKey] = N'VT_Template' AND [IsDeleted] = 0);
UPDATE [ref].[AssetType] SET [DefaultTemplateDefinitionEntityId] = @ct WHERE @ct IS NOT NULL AND [AssetTypeCode] IN (N'CT', N'CT_AUX', N'METERING_UNIT') AND ([DefaultTemplateDefinitionEntityId] IS NULL OR [DefaultTemplateDefinitionEntityId] <> @ct);
UPDATE [ref].[AssetType] SET [DefaultTemplateDefinitionEntityId] = @vt WHERE @vt IS NOT NULL AND [AssetTypeCode] IN (N'VT', N'VT_AUX', N'COUPLING_CAPACITOR_VT', N'CCPD') AND ([DefaultTemplateDefinitionEntityId] IS NULL OR [DefaultTemplateDefinitionEntityId] <> @vt);
GO
