-- Alternate-key kinds named across SCHEMA-DESIGN (§0.4, §3.2, §4.2, §6.4, §7.1, §8.1, §8.9,
-- §9.1, §9.4, §11.1, §13.1). SchemaName = the <schema>.AlternateKey table that carries it.
-- Note: §4.2 lists Designation on assets and §7.3 on the protection-function node; seeded as
-- the node's key per §7.3 (the later, more specific statement). Flagged in STEPS.md.
-- LegacyRecordNumber and SapWorkOrder are migration kinds (MIGRATION-PLAN.md Q15 / Q10, decided
-- 2026-09-04): the legacy OLD_NO is a record number, not a plant tag; SAP work orders key Work Requests.
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [ref].[AlternateKeyKind] AS t
USING (VALUES
    (N'StationNumber',             N'Station asset number (NB Power''s four-digit asset number, owner 2026-09-05)',            N'location',   N'Node',                0, NULL),
    (N'CascadeFloc',               N'Cascade functional location',            N'location',   N'Node',                0, NULL),
    (N'SiteAlias',                 N'Two-character site alias (shortens device names on schematic drawings; unique platform-wide, owner 2026-09-05)',               N'location',   N'Node',                0, NULL),
    (N'PanelSlot',                 N'Panel label (34A, the PNL34A segment of the FLOC) as drawn on the schematic and fixed to the panel at site; no standard nomenclature (owner 2026-09-05)',                       N'location',   N'Node',                1, N'Node'),
    (N'StructureNumber',           N'Structure number',                       N'location',   N'Node',                1, N'Asset'),
    (N'NercId',                    N'NERC identifier',                        N'location',   N'Node',                0, NULL),
    (N'Designation',               N'Function designation: device number + protection group (87A, 97B = isolation zone, B protection); owner 2026-09-05',                      N'location',   N'ProtectionFunction',  1, N'Node'),
    (N'SerialNumber',              N'Serial number',                          N'asset',      N'Asset',               1, N'Entity'),
    (N'CableNumber',               N'Cable number',                           N'asset',      N'Asset',               0, NULL),
    (N'LineNumber',                N'Line number',                            N'asset',      N'Asset',               0, NULL),
    (N'WireNumber',                N'Wire number (scoped to panel)',          N'asset',      N'Asset',               1, N'Node'),
    (N'AssetTag',                  N'Asset tag (predecessor)',                N'asset',      N'Asset',               0, NULL),
    (N'LegacyRecordNumber',        N'Legacy record number (OLD_NO)',          N'asset',      N'Asset',               0, NULL),
    (N'SapEquipmentNumber',        N'SAP equipment number',                   N'asset',      N'Asset',               0, NULL),
    (N'IedName',                   N'IEC 61850 IED name',                     N'asset',      N'Device',              0, NULL),
    (N'SchemeNumber',              N'Scheme number',                          N'scheme',     N'Scheme',              0, NULL),
    (N'DocumentNumber',            N'Document number',                        N'document',   N'Document',            0, NULL),
    (N'LegacyReference',           N'Legacy reference',                       N'document',   N'Document',            0, NULL),
    (N'DrawingNumber',             N'Drawing number',                         N'document',   N'Document',            0, NULL),
    (N'WorkRequestNumber',         N'Work Request number',                    N'work',       N'WorkRequest',         0, NULL),
    (N'LegacyChangeRequestNumber', N'Legacy change request number',           N'work',       N'WorkRequest',         0, NULL),
    (N'CascadeNumber',             N'Cascade work order number',              N'work',       N'WorkRequest',         0, NULL),
    (N'SapWorkOrder',              N'SAP work order number',                  N'work',       N'WorkRequest',         0, NULL),
    (N'EmployeeNumber',            N'Employee number',                        N'personnel',  N'Person',              0, NULL),
    (N'BadgeNumber',               N'Badge number',                           N'personnel',  N'Person',              0, NULL),
    (N'ActiveDirectorySid',        N'Active Directory SID',                   N'security',   N'User',                0, NULL),
    (N'LayerNodeNumber',           N'Layer node number (an external system''s bus number, scoped to its layer; §13.1)', N'network', N'LayerNode', 1, N'Layer')
) AS s ([KeyKindCode], [Name], [SchemaName], [SubjectKindCode], [ScopeRequired], [ScopeSubjectKindCode])
ON t.[KeyKindCode] = s.[KeyKindCode]
WHEN MATCHED AND (t.[Name] <> s.[Name] OR t.[SchemaName] <> s.[SchemaName] OR t.[SubjectKindCode] <> s.[SubjectKindCode] OR t.[ScopeRequired] <> s.[ScopeRequired] OR ISNULL(t.[ScopeSubjectKindCode], N'') <> ISNULL(s.[ScopeSubjectKindCode], N''))
    THEN UPDATE SET [Name] = s.[Name], [SchemaName] = s.[SchemaName], [SubjectKindCode] = s.[SubjectKindCode], [ScopeRequired] = s.[ScopeRequired], [ScopeSubjectKindCode] = s.[ScopeSubjectKindCode], [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET
    THEN INSERT ([KeyKindCode], [Name], [SchemaName], [SubjectKindCode], [ScopeRequired], [ScopeSubjectKindCode], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
         VALUES (s.[KeyKindCode], s.[Name], s.[SchemaName], s.[SubjectKindCode], s.[ScopeRequired], s.[ScopeSubjectKindCode], @actor, @now, @actor, @now);
GO
