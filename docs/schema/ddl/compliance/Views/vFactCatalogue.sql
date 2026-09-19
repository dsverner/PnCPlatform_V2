-- SCHEMA-DESIGN §12.3 (163). Every fact a rule may reference. Nothing regenerates it: a characteristic or
-- setting flagged IsCatalogueFact on an effective definition version, or an effective formula, appears by
-- virtue of its row existing (the property the extensibility gate proved, docs/schema/gate).
--
-- FactSource: Fixed (a column the schema holds; read by compliance.fFixedFactValue), Characteristic
-- (asset.CharacteristicValue by template entity + key), Setting (document.ParsedSetting on the device's
-- in-service settings file), Formula (a Program.Formula payload, evaluated recursively).
-- Fixed facts the design lists that are NOT yet here (STEPS.md step 12): scheme.members[role],
-- function.logical_node, device.connections[realisation], device.advisories[open], network.port,
-- network.vlan, network.routable (derivation is PROCEDURES.md #11), channel.*, asset.owner_of_record,
-- record.last, study.is_stale, person.*, entity.agreements, document.revision.current.
-- platform.backup.last.<kind> and platform.restore_test.last (§15.2) are listed below. Each needs a parameterised read the placeholder grammar cannot express.
CREATE VIEW [compliance].[vFactCatalogue] AS
SELECT [FactName], [FactSource], [FactKey], [DefinitionEntityId], [SourceSchema], [SourceObject], [SourceColumn],
       [DataType], [UnitCode], [SubjectKind], [TemporalClass], [PublishedByDefinitionVersionRowId],
       CONVERT(NVARCHAR(20), NULL) AS [Base], [ReferenceKind], [Parameters]
FROM (VALUES
    (N'asset.voltage_class',   N'Fixed', N'asset.voltage_class',   NULL, N'asset',    N'vAsset',                N'VoltageClassCode', N'Text',        NULL, N'Asset',              N'ValidTime', NULL, NULL, NULL),
    (N'device.model',          N'Fixed', N'device.model',          NULL, N'ref',      N'vModel',                N'ModelCode',        N'Text',        NULL, N'Device',             N'ValidTime', NULL, NULL, NULL),
    (N'device.technology',     N'Fixed', N'device.technology',     NULL, N'ref',      N'vModel',                N'Technology',       N'Enumeration', NULL, N'Device',             N'ValidTime', NULL, NULL, NULL),
    (N'device.firmware',       N'Fixed', N'device.firmware',       NULL, N'device',   N'vFirmwareHistory',      N'FirmwareVersionId',N'Text',        NULL, N'Device',             N'ValidTime', NULL, NULL, NULL),
    (N'station.type',          N'Fixed', N'station.type',          NULL, N'location', N'vNode',                 N'SubtypeCode',      N'Text',        NULL, N'Station',            N'ValidTime', NULL, NULL, NULL),
    (N'scheme.type',           N'Fixed', N'scheme.type',           NULL, N'scheme',   N'vScheme',               N'SchemeTypeDefinitionVersionRowId', N'Text', NULL, N'Scheme',   N'ValidTime', NULL, NULL, NULL),
    (N'function.commissioned', N'Fixed', N'function.commissioned', NULL, N'scheme',   N'vCommissionedFunction', N'AnsiCode',         N'Text',        NULL, N'ProtectionFunction', N'ValidTime', NULL, NULL, NULL),
    -- §15.2 platform facts: the completion instant (ISO 8601 text) of the last succeeded run; the
    -- design's platform.backup.last(kind) is spelled as one plain name per kind for the placeholder grammar
    (N'platform.backup.last.Full',          N'Fixed', N'platform.backup.last.Full',          NULL, N'audit', N'vBackupRun',   N'CompletedAt', N'DateTime', NULL, N'Platform', N'AppendOnly', NULL, NULL, NULL),
    (N'platform.backup.last.Differential',  N'Fixed', N'platform.backup.last.Differential',  NULL, N'audit', N'vBackupRun',   N'CompletedAt', N'DateTime', NULL, N'Platform', N'AppendOnly', NULL, NULL, NULL),
    (N'platform.backup.last.Log',           N'Fixed', N'platform.backup.last.Log',           NULL, N'audit', N'vBackupRun',   N'CompletedAt', N'DateTime', NULL, N'Platform', N'AppendOnly', NULL, NULL, NULL),
    (N'platform.backup.last.FilegroupFull', N'Fixed', N'platform.backup.last.FilegroupFull', NULL, N'audit', N'vBackupRun',   N'CompletedAt', N'DateTime', NULL, N'Platform', N'AppendOnly', NULL, NULL, NULL),
    (N'platform.restore_test.last',         N'Fixed', N'platform.restore_test.last',         NULL, N'audit', N'vRestoreTest', N'CompletedAt', N'DateTime', NULL, N'Platform', N'AppendOnly', NULL, NULL, NULL),
    -- FORMULA-GRAMMAR.md §4.2, PROCEDURES.md #35 first slice: parameterised facts (Parameters = JSON list of names)
    (N'scheme.members',        N'Fixed', N'scheme.members',        NULL, N'scheme',   N'vSchemeMember',         N'MemberEntityId',   N'Set',         NULL, N'Scheme',             N'BiTemporal', NULL, N'Member', N'["role"]'),
    (N'record.last',           N'Fixed', N'record.last',           NULL, N'record',   N'vRecord',               N'EntityId',         N'Reference',   NULL, N'Any',                N'ValidTime', NULL, N'Record', N'["kind","accepted"]'),
    (N'record.occurred_at',    N'Fixed', N'record.occurred_at',    NULL, N'record',   N'vRecord',               N'OccurredAt',       N'DateTime',    NULL, N'Record',             N'ValidTime', NULL, NULL, NULL),
    -- PROCEDURES.md #35 (2026-09-06): the remaining relation-valued and parameterised facts, read by compliance.fFactRead
    (N'function.logical_node',   N'Fixed', N'function.logical_node',   NULL, N'scheme',     N'vCommissionedFunction', N'LogicalNodeEntityId', N'Reference', NULL, N'ProtectionFunction', N'ValidTime', NULL, N'LogicalNode', NULL),
    (N'device.advisories',       N'Fixed', N'device.advisories',       NULL, N'device',     N'vAdvisoryScope',        N'AdvisoryEntityId', N'Set',         NULL, N'Device',             N'ValidTime', NULL, N'Advisory', N'["open"]'),
    (N'device.connections',      N'Fixed', N'device.connections',      NULL, N'connection', N'vConnection',           N'EntityId',         N'Set',         NULL, N'Device',             N'BiTemporal', NULL, N'Connection', N'["realisation"]'),
    (N'network.port',            N'Fixed', N'network.port',            NULL, N'connection', N'vNetworkPort',          N'EntityId',         N'Set',         NULL, N'Device',             N'ValidTime', NULL, N'Port', NULL),
    (N'network.vlan',            N'Fixed', N'network.vlan',            NULL, N'connection', N'vNetworkPort',          N'VlanId',           N'Set',         NULL, N'Device',             N'ValidTime', NULL, NULL, NULL),
    (N'network.services',        N'Fixed', N'network.services',        NULL, N'connection', N'vPortService',          N'EntityId',         N'Set',         NULL, N'Device',             N'ValidTime', NULL, N'PortService', N'["protocol"]'),
    (N'channel.route',           N'Fixed', N'channel.route',           NULL, N'location',   N'vRoute',                N'EntityId',         N'Reference',   NULL, N'Asset',              N'ValidTime', NULL, N'Route', NULL),
    (N'channel.links',           N'Fixed', N'channel.links',           NULL, N'location',   N'vRouteStep',            N'OccupiedAssetEntityId', N'Set',    NULL, N'Asset',              N'ValidTime', NULL, N'Asset', N'["owner"]'),
    (N'asset.owner_of_record',   N'Fixed', N'asset.owner_of_record',   NULL, N'asset',      N'vOwnershipLink',        N'EntityEntityId',   N'Reference',   NULL, N'Asset',              N'ValidTime', NULL, N'Entity', N'["role"]'),
    (N'study.is_stale',          N'Fixed', N'study.is_stale',          NULL, N'document',   N'vStudy',                N'IsStale',          N'Boolean',     NULL, N'Document',           N'ValidTime', NULL, NULL, NULL),
    (N'document.revision_current', N'Fixed', N'document.revision_current', NULL, N'document', N'vRevision',           N'EntityId',         N'Reference',   NULL, N'Document',           N'ValidTime', NULL, N'Revision', NULL),
    (N'document.class',          N'Fixed', N'document.class',          NULL, N'document',   N'vDocument',             N'DocumentClassDefinitionEntityId', N'Text', NULL, N'Document',     N'ValidTime', NULL, NULL, NULL),
    (N'person.qualifications',   N'Fixed', N'person.qualifications',   NULL, N'personnel',  N'vPersonQualification',  N'QualificationTypeCode', N'Boolean', NULL, N'Person',            N'ValidTime', NULL, NULL, N'["type"]'),
    (N'person.authorisations',   N'Fixed', N'person.authorisations',   NULL, N'personnel',  N'vAuthorisation',        N'RightKindCode',    N'Boolean',     NULL, N'Person',             N'ValidTime', NULL, NULL, N'["kind"]'),
    (N'person.training_current', N'Fixed', N'person.training_current', NULL, N'record',     N'vRecord',               N'OccurredAt',       N'Boolean',     NULL, N'Person',             N'ValidTime', NULL, NULL, N'["module"]'),
    (N'person.employer',         N'Fixed', N'person.employer',         NULL, N'personnel',  N'vPerson',               N'EmployerEntityEntityId', N'Reference', NULL, N'Person',          N'ValidTime', NULL, N'Entity', NULL),
    (N'entity.agreements',       N'Fixed', N'entity.agreements',       NULL, N'party',      N'vEntityAgreement',      N'EntityId',         N'Set',         NULL, N'Entity',             N'ValidTime', NULL, N'EntityAgreement', N'["kind"]'),
    (N'entity.kind',             N'Fixed', N'entity.kind',             NULL, N'party',      N'vEntity',               N'EntityKind',       N'Text',        NULL, N'Entity',             N'ValidTime', NULL, NULL, NULL),
    -- PLATFORM-ARCHITECTURE §8.1 (226): the platform's own baseline; §5.2 (217): lightning correlation
    (N'platform.release',        N'Fixed', N'platform.release',        NULL, N'platform',   N'vDeployment',           N'ReleaseId',        N'Text',        NULL, N'Platform',           N'AppendOnly', NULL, NULL, NULL),
    (N'platform.baseline',       N'Fixed', N'platform.baseline',       NULL, N'platform',   N'vRelease',              N'ReleaseId',        N'Reference',   NULL, N'Platform',           N'AppendOnly', NULL, N'Release', NULL),
    (N'operation.lightning_nearby', N'Fixed', N'operation.lightning_nearby', NULL, N'event', N'vLightningStrike',     N'StrikeId',         N'Set',         NULL, N'ProtectionOperation', N'AppendOnly', NULL, N'LightningStrike', N'["km","minutes"]'),
    (N'operation.lightning_count',  N'Fixed', N'operation.lightning_count',  NULL, N'event', N'vLightningStrike',     N'StrikeId',         N'Integer',     NULL, N'ProtectionOperation', N'AppendOnly', NULL, NULL, N'["km","minutes"]'),
    -- #171 (2026-09-16): what the device's scheme protects — resolved by compliance.fDeviceProtects (the scheme through the
    -- device's own membership or a protection function under its position, then the current SchemeProtects link, Primary first).
    -- The rating is parameterised by kind (Continuous | FourHour | FifteenMinute | PracticalLimitation) and read in compliance.fFactRead.
    (N'device.protects.name',            N'Fixed', N'device.protects.name',            NULL, N'asset', N'vAsset',       N'Name',      N'Text',    NULL,   N'Device', N'ValidTime',  NULL, NULL, NULL),
    (N'device.protects.terminal.voltage',N'Fixed', N'device.protects.terminal.voltage',NULL, N'ref',   N'vVoltageClass',N'NominalKv', N'Decimal', N'kV',  N'Device', N'BiTemporal', NULL, NULL, NULL),
    (N'device.protects.rating',          N'Fixed', N'device.protects.rating',          NULL, N'asset', N'vAssetRating', N'Amperes',   N'Decimal', N'A',   N'Device', N'BiTemporal', NULL, NULL, N'["kind"]'),
    -- PROCEDURE-ENGINE §7 "Facts the engine publishes" (#67), entered in W3 so a canonical procedure document passes
    -- compliance.ValidateProgramFacts; the reads (compliance.fFactRead) arrive with the interpreter in W4 (decision #101).
    -- step.capture takes its type from the document (DataType Any here; the checker types it from the document).
    -- procedure.<name> (a produces.as) and input.<name> are document-declared names: not rows here — ValidateProgramFacts
    -- passes those prefixes for a Program.Procedure and process.ValidateProcedureDocument checks them against the document.
    -- Parameters: a name ending in '?' is optional (pass=, member=; §7 resolution scope); the checker and fFactRead honour it (W4).
    (N'step.state',             N'Engine', N'step.state',             NULL, N'process', N'vStepInstance',       N'State',       N'Text',      NULL, N'ProcedureInstance',   N'Versioned', NULL, NULL,      N'["id","pass?","member?"]'),
    (N'step.outcome',           N'Engine', N'step.outcome',           NULL, N'process', N'vStepInstance',       N'Outcome',     N'Text',      NULL, N'ProcedureInstance',   N'Versioned', NULL, NULL,      N'["id","pass?","member?"]'),
    (N'step.committed_at',      N'Engine', N'step.committed_at',      NULL, N'process', N'vStepInstance',       N'CommittedAt', N'DateTime',  NULL, N'ProcedureInstance',   N'Versioned', NULL, NULL,      N'["id","pass?","member?"]'),
    (N'step.committed_by',      N'Engine', N'step.committed_by',      NULL, N'process', N'vStepInstance',       N'CommittedByActorId', N'Reference', NULL, N'ProcedureInstance', N'Versioned', NULL, N'Actor', N'["id","pass?","member?"]'),
    (N'step.capture',           N'Engine', N'step.capture',           NULL, N'process', N'vStepInstance',       N'Draft',       N'Any',       NULL, N'ProcedureInstance',   N'Versioned', NULL, NULL,      N'["id","field","pass?","member?"]'),
    (N'branch.outcome',         N'Engine', N'branch.outcome',         NULL, N'process', N'vBlockInstance',      N'Outcome',     N'Text',      NULL, N'ProcedureInstance',   N'Versioned', NULL, NULL,      N'["id","member?"]'),
    (N'procedure.outcome',      N'Engine', N'procedure.outcome',      NULL, N'process', N'vProcedureInstance',  N'Outcome',     N'Text',      NULL, N'ProcedureInstance',   N'Versioned', NULL, NULL,      NULL),
    (N'work.outage_required',   N'Fixed',  N'work.outage_required',   NULL, N'work',    N'vWorkRequest',        N'OutageRequired',      N'Boolean',  NULL, N'WorkRequest',      N'ValidTime', NULL, NULL,      NULL),
    (N'work.outage_window_start', N'Fixed', N'work.outage_window_start', NULL, N'work',  N'vWorkRequest',        N'OutageWindowStartAt', N'DateTime', NULL, N'WorkRequest',      N'ValidTime', NULL, NULL,      NULL),
    (N'package.revisions',      N'Engine', N'package.revisions',      NULL, N'document', N'vSettingsIssuePackageItem', N'RevisionRowId', N'Set', NULL, N'SettingsIssuePackage', N'ValidTime', NULL, N'ConfigurationFileRevision', NULL),
    (N'package.revision_count', N'Engine', N'package.revision_count', NULL, N'document', N'vSettingsIssuePackageItem', N'RevisionRowId', N'Integer', NULL, N'SettingsIssuePackage', N'ValidTime', NULL, NULL, NULL)
) AS f ([FactName], [FactSource], [FactKey], [DefinitionEntityId], [SourceSchema], [SourceObject], [SourceColumn], [DataType], [UnitCode], [SubjectKind], [TemporalClass], [PublishedByDefinitionVersionRowId], [ReferenceKind], [Parameters])
-- #171 (2026-09-16): the classification facts, one per kind per subject the kind applies to —
-- ref.ClassificationKind.SubjectKinds is the JSON array of Station / Asset / Device. Before this every kind produced a
-- station row and a line row whether or not it was ever recorded there. A kind with no SubjectKinds produces no fact.
UNION ALL
SELECT N'station.classification.' + k.[ClassificationKindCode], N'Fixed', N'station.classification.' + k.[ClassificationKindCode], NULL,
       N'asset', N'vClassification', N'ClassificationValue', N'Text', NULL, N'Station', N'BiTemporal', NULL, NULL, NULL, NULL
FROM [ref].[ClassificationKind] k WHERE k.[IsActive] = 1
  AND EXISTS (SELECT 1 FROM OPENJSON(ISNULL(k.[SubjectKinds], N'[]')) WHERE [value] = N'Station')
UNION ALL
SELECT N'line.classification.' + k.[ClassificationKindCode], N'Fixed', N'line.classification.' + k.[ClassificationKindCode], NULL,
       N'asset', N'vClassification', N'ClassificationValue', N'Text', NULL, N'Line', N'BiTemporal', NULL, NULL, NULL, NULL
FROM [ref].[ClassificationKind] k WHERE k.[IsActive] = 1
  AND EXISTS (SELECT 1 FROM OPENJSON(ISNULL(k.[SubjectKinds], N'[]')) WHERE [value] = N'Asset')
UNION ALL
-- the device's own classification (the BES Cyber Asset flag, external routable connectivity)
SELECT N'device.classification.' + k.[ClassificationKindCode], N'Fixed', N'device.classification.' + k.[ClassificationKindCode], NULL,
       N'asset', N'vClassification', N'ClassificationValue', N'Text', NULL, N'Device', N'BiTemporal', NULL, NULL, NULL, NULL
FROM [ref].[ClassificationKind] k WHERE k.[IsActive] = 1
  AND EXISTS (SELECT 1 FROM OPENJSON(ISNULL(k.[SubjectKinds], N'[]')) WHERE [value] = N'Device')
UNION ALL
-- #173 (2026-09-17): inherited from where the device stands — its Installed placement, then the nearest node at or above
-- it that carries the classification (location.fNearestClassified). This replaces device.station.classification.<Kind>:
-- the owner, 2026-09-17, on the CIP requirements following from the impact rating "of building that the device is in" —
-- a rating on the building beats one on the station, and a group that models rooms or panels can classify there instead.
-- #195 (2026-09-19): a kind recorded on ANY location level (ref.LocationNodeType) is what a device inherits — the CIP impact rating is the building's (#177/#195).
SELECT N'device.location.classification.' + k.[ClassificationKindCode], N'Fixed', N'device.location.classification.' + k.[ClassificationKindCode], NULL,
       N'asset', N'vClassification', N'ClassificationValue', N'Text', NULL, N'Device', N'BiTemporal', NULL, NULL, NULL, NULL
FROM [ref].[ClassificationKind] k WHERE k.[IsActive] = 1
  AND EXISTS (SELECT 1 FROM OPENJSON(ISNULL(k.[SubjectKinds], N'[]')) j JOIN [ref].[LocationNodeType] nt ON nt.[NodeTypeCode] = j.[value])   -- #195: any location level a kind is recorded on (a building's CIP rating), not stations only
UNION ALL
-- inherited from the primary asset the device's scheme protects, and from the bus at that terminal end
-- (#196: device.protects.classification.NpccBulkPowerSystem reads the element's own declaration, else its bus's)
SELECT N'device.protects.classification.' + k.[ClassificationKindCode], N'Fixed', N'device.protects.classification.' + k.[ClassificationKindCode], NULL,
       N'asset', N'vClassification', N'ClassificationValue', N'Text', NULL, N'Device', N'BiTemporal', NULL, NULL, NULL, NULL
FROM [ref].[ClassificationKind] k WHERE k.[IsActive] = 1
  AND EXISTS (SELECT 1 FROM OPENJSON(ISNULL(k.[SubjectKinds], N'[]')) WHERE [value] = N'Asset')
UNION ALL
SELECT N'device.protects.bus.classification.' + k.[ClassificationKindCode], N'Fixed', N'device.protects.bus.classification.' + k.[ClassificationKindCode], NULL,
       N'asset', N'vClassification', N'ClassificationValue', N'Text', NULL, N'Device', N'BiTemporal', NULL, NULL, NULL, NULL
FROM [ref].[ClassificationKind] k WHERE k.[IsActive] = 1
  AND EXISTS (SELECT 1 FROM OPENJSON(ISNULL(k.[SubjectKinds], N'[]')) WHERE [value] = N'Asset')
UNION ALL
-- published characteristics: every IsCatalogueFact on the effective version of an asset template
SELECT n.[Prefix] + cd.[CharacteristicKey], N'Characteristic', cd.[CharacteristicKey], dv.[DefinitionEntityId],
       N'asset', N'vCharacteristicValue',
       CASE cd.[DataType] WHEN N'Text' THEN N'TextValue' WHEN N'Enumeration' THEN N'TextValue' WHEN N'Integer' THEN N'IntegerValue'
                          WHEN N'Decimal' THEN N'DecimalValue' WHEN N'Boolean' THEN N'BooleanValue' WHEN N'DateTime' THEN N'DateTimeValue'
                          WHEN N'Reference' THEN N'ReferenceEntityId' END,
       cd.[DataType], cd.[UnitCode], n.[SubjectKind], N'ValidTime', dv.[RowId], cd.[Base], cd.[ReferenceTargetKind], NULL
FROM [config].[CharacteristicDefinition] cd
JOIN [config].[DefinitionVersion] dv ON dv.[RowId] = cd.[DefinitionVersionRowId] AND dv.[IsDeleted] = 0
JOIN [config].[Definition] d ON d.[EntityId] = dv.[DefinitionEntityId] AND d.[IsDeleted] = 0
CROSS JOIN (VALUES (N'asset.template.', N'Asset'), (N'device.template.', N'Device')) AS n ([Prefix], [SubjectKind])
WHERE cd.[IsDeleted] = 0 AND cd.[IsCatalogueFact] = 1
  AND d.[DefinitionKind] = N'CharacteristicSchema.AssetTemplate'
  AND dv.[Status] = N'Effective' AND dv.[EffectiveFrom] <= SYSDATETIMEOFFSET() AND (dv.[EffectiveTo] IS NULL OR dv.[EffectiveTo] > SYSDATETIMEOFFSET())
UNION ALL
-- published settings: every IsCatalogueFact on the effective version of a settings-parse transform
SELECT N'device.settings.' + sd.[SettingCode], N'Setting', sd.[SettingCode], dv.[DefinitionEntityId],
       N'document', N'vParsedSetting',
       CASE sd.[DataType] WHEN N'Text' THEN N'TextValue' WHEN N'Enumeration' THEN N'TextValue' WHEN N'Integer' THEN N'IntegerValue'
                          WHEN N'Decimal' THEN N'DecimalValue' WHEN N'Boolean' THEN N'BooleanValue' WHEN N'DateTime' THEN N'DateTimeValue'
                          WHEN N'Reference' THEN N'ReferenceEntityId' END,
       sd.[DataType], sd.[UnitCode], N'Device', N'ValidTime', dv.[RowId], sd.[Base], NULL, NULL
FROM [config].[SettingDefinition] sd
JOIN [config].[DefinitionVersion] dv ON dv.[RowId] = sd.[DefinitionVersionRowId] AND dv.[IsDeleted] = 0
JOIN [config].[Definition] d ON d.[EntityId] = dv.[DefinitionEntityId] AND d.[IsDeleted] = 0
WHERE sd.[IsDeleted] = 0 AND sd.[IsCatalogueFact] = 1
  AND d.[DefinitionKind] = N'Transform.SettingsParse'
  AND dv.[Status] = N'Effective' AND dv.[EffectiveFrom] <= SYSDATETIMEOFFSET() AND (dv.[EffectiveTo] IS NULL OR dv.[EffectiveTo] > SYSDATETIMEOFFSET())
UNION ALL
-- derived facts: every effective formula
SELECT N'asset.formula.' + d.[DefinitionKey], N'Formula', d.[DefinitionKey], d.[EntityId],
       N'config', N'vDefinitionVersion', N'PayloadText',
       -- FORMULA-GRAMMAR.md §7: a grammar-1 formula declares what it publishes; a grammar-0 formula is Boolean
       CASE JSON_VALUE(dv.[PayloadText], '$.publishes.type') WHEN N'num' THEN N'Decimal' WHEN N'text' THEN N'Text' WHEN N'date' THEN N'DateTime' ELSE N'Boolean' END,
       JSON_VALUE(dv.[PayloadText], '$.publishes.unit'), COALESCE(JSON_VALUE(dv.[PayloadText], '$.subjectKind'), N'Asset'), N'Versioned', dv.[RowId], JSON_VALUE(dv.[PayloadText], '$.publishes.base'), NULL, NULL
FROM [config].[Definition] d
JOIN [config].[DefinitionVersion] dv ON dv.[DefinitionEntityId] = d.[EntityId] AND dv.[IsDeleted] = 0
WHERE d.[IsDeleted] = 0 AND d.[DefinitionKind] = N'Program.Formula'
  AND dv.[Status] = N'Effective' AND dv.[EffectiveFrom] <= SYSDATETIMEOFFSET() AND (dv.[EffectiveTo] IS NULL OR dv.[EffectiveTo] > SYSDATETIMEOFFSET());
GO
GRANT SELECT ON [compliance].[vFactCatalogue] TO [app_execute];
GO
