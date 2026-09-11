-- SCHEMA-DESIGN §2.1 list, plus kinds named in later steps: Program.TestPlan (§10.2),
-- Program.NotificationType (§9.6), Program.BackupPolicy (§15.1),
-- CharacteristicSchema.StandardSettings (§8.6), Transform.Export (§13.1).
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [ref].[DefinitionKind] AS t
USING (VALUES
    (N'CharacteristicSchema.AssetTemplate',       N'CharacteristicSchema', N'Asset template',                        0),
    (N'CharacteristicSchema.RecordTemplate',      N'CharacteristicSchema', N'Record template (§10.1: a record kind may name a characteristic template; §13.1 reconciliation candidates)', 0),
    (N'CharacteristicSchema.CableType',           N'CharacteristicSchema', N'Cable type',                            0),
    (N'CharacteristicSchema.StructureType',       N'CharacteristicSchema', N'Structure type',                        0),
    (N'CharacteristicSchema.RationaleSchemeType', N'CharacteristicSchema', N'Rationale template per scheme type',    0),
    (N'CharacteristicSchema.RationaleDevice',     N'CharacteristicSchema', N'Rationale overlay per device model',    0),
    (N'CharacteristicSchema.DocumentClass',       N'CharacteristicSchema', N'Document class',                        0),
    (N'CharacteristicSchema.TestPlanReadings',    N'CharacteristicSchema', N'Test-plan readings',                    0),
    (N'CharacteristicSchema.StandardSettings',    N'CharacteristicSchema', N'Standard settings and philosophy',      0),
    (N'CharacteristicSchema.Enumeration',         N'CharacteristicSchema', N'Enumeration (allowed-value list; implied by §2.4, §3.1, §14.2)', 0),
    (N'Transform.SettingsParse',                  N'Transform',            N'Settings file parse',                   0),
    (N'Transform.SettingsGenerate',               N'Transform',            N'Settings file generate',                0),
    (N'Transform.SclParse',                       N'Transform',            N'SCL parse',                             0),
    (N'Transform.WordOutput',                     N'Transform',            N'Word document output',                  0),
    (N'Transform.Import',                         N'Transform',            N'Import',                                0),
    (N'Transform.Export',                         N'Transform',            N'Export',                                0),
    (N'Program.Workflow',                         N'Program',              N'Workflow',                              1),
    (N'Program.Formula',                          N'Program',              N'Formula',                               1),
    (N'Program.ObligationRule',                   N'Program',              N'Obligation rule',                       1),
    (N'Program.EvidenceDefinition',               N'Program',              N'Evidence definition',                   1),
    (N'Program.ClassificationDerivation',         N'Program',              N'Classification derivation',             1),
    (N'Program.QualificationRequirement',         N'Program',              N'Qualification requirement',             1),
    (N'Program.SegregationRule',                  N'Program',              N'Segregation rule',                      1),
    (N'Program.ReportDefinition',                 N'Program',              N'Report definition',                     1),
    (N'Program.WorkType',                         N'Program',              N'Work type',                             1),
    (N'Program.SchemeType',                       N'Program',              N'Scheme type',                           1),
    (N'Program.MaintenanceActivityType',          N'Program',              N'Maintenance activity type',             1),
    (N'Program.CleansingRules',                   N'Program',              N'Migration cleansing rules',             1),
    (N'Program.TestPlan',                         N'Program',              N'Test plan',                             1),
    (N'Program.NotificationType',                 N'Program',              N'Notification type',                     1),
    (N'Program.BackupPolicy',                     N'Program',              N'Backup policy',                         1)
) AS s ([DefinitionKind], [MetaKind], [Name], [HasPayloadText])
ON t.[DefinitionKind] = s.[DefinitionKind]
WHEN MATCHED AND (t.[MetaKind] <> s.[MetaKind] OR t.[Name] <> s.[Name] OR t.[HasPayloadText] <> s.[HasPayloadText])
    THEN UPDATE SET [MetaKind] = s.[MetaKind], [Name] = s.[Name], [HasPayloadText] = s.[HasPayloadText], [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET
    THEN INSERT ([DefinitionKind], [MetaKind], [Name], [HasPayloadText], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
         VALUES (s.[DefinitionKind], s.[MetaKind], s.[Name], s.[HasPayloadText], @actor, @now, @actor, @now);
GO
