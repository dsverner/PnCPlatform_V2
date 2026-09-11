-- Polymorphic kind names used across SCHEMA-DESIGN (SubjectKind, MemberKind, ScopeKind,
-- FromKind/ToKind, GranteeKind …) mapped to the table that holds the identity.
-- Extension tables share the parent's EntityId (device → asset, instrument → asset).
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [ref].[SubjectKind] AS t
USING (VALUES
    (N'Node',                      N'Location node',                    N'location',   N'NodeRegistry',                 N'EntityId'),
    (N'Station',                   N'Station node',                     N'location',   N'NodeRegistry',                 N'EntityId'),
    (N'Panel',                     N'Panel node',                       N'location',   N'NodeRegistry',                 N'EntityId'),
    (N'DevicePosition',            N'Device position node',             N'location',   N'NodeRegistry',                 N'EntityId'),
    (N'ProtectionFunction',        N'Protection-function node',         N'location',   N'NodeRegistry',                 N'EntityId'),
    (N'Stud',                      N'Terminal stud node',               N'location',   N'NodeRegistry',                 N'EntityId'),
    (N'CustodyLocation',           N'Custody location',                 N'location',   N'CustodyLocationRegistry',      N'EntityId'),
    (N'RouteStep',                 N'Route step',                       N'location',   N'RouteStepRegistry',            N'EntityId'),
    (N'Structure',                 N'Structure node (§3.3)',            N'location',   N'NodeRegistry',                 N'EntityId'),
    (N'Asset',                     N'Asset',                            N'asset',      N'AssetRegistry',                N'EntityId'),
    (N'Device',                    N'Device (asset extension)',         N'asset',      N'AssetRegistry',                N'EntityId'),
    (N'Channel',                   N'Channel asset',                    N'asset',      N'AssetRegistry',                N'EntityId'),
    (N'Instrument',                N'Test instrument (asset extension)',N'asset',      N'AssetRegistry',                N'EntityId'),
    (N'Line',                      N'Line asset',                       N'asset',      N'AssetRegistry',                N'EntityId'),
    (N'Entity',                    N'Organisation',                     N'party',      N'EntityRegistry',               N'EntityId'),
    (N'Scheme',                    N'Scheme',                           N'scheme',     N'SchemeRegistry',               N'EntityId'),
    (N'ProtectionCondition',       N'Protection condition',             N'scheme',     N'ProtectionConditionRegistry',  N'EntityId'),
    (N'ProtectionOperation',       N'Protection operation',             N'scheme',     N'ProtectionOperationRegistry',  N'EntityId'),
    (N'Connection',                N'Connection',                       N'connection', N'ConnectionRegistry',           N'EntityId'),
    (N'Port',                      N'Port',                             N'connection', N'PortRegistry',                 N'EntityId'),
    (N'NetworkPort',               N'Network port (port extension)',    N'connection', N'PortRegistry',                 N'EntityId'),
    (N'Dataset',                   N'IEC 61850 dataset',                N'connection', N'DatasetRegistry',              N'EntityId'),
    (N'SecurityPerimeter',         N'Security perimeter',               N'connection', N'SecurityPerimeterRegistry',    N'EntityId'),
    (N'Document',                  N'Document',                         N'document',   N'DocumentRegistry',             N'EntityId'),
    (N'Layer',                     N'Overlay layer (§13.1)',            N'network',    N'LayerRegistry',                N'EntityId'),
    (N'LayerNode',                 N'Layer node (§13.1)',               N'network',    N'LayerNodeRegistry',            N'EntityId'),
    (N'LayerBranch',               N'Layer branch (§13.1)',             N'network',    N'LayerBranchRegistry',          N'EntityId'),
    (N'Case',                      N'Layer snapshot / case (§13.1)',    N'network',    N'CaseRegistry',                 N'EntityId'),
    (N'DocumentRevision',          N'Document revision (fact version)', N'document',   N'Revision',                     N'RowId'),
    (N'ConfigurationFileRevision', N'Configuration-file revision',      N'document',   N'Revision',                     N'RowId'),
    (N'DrawingRevision',           N'Drawing revision',                 N'document',   N'Revision',                     N'RowId'),
    (N'WorkRequest',               N'Work Request',                     N'work',       N'WorkRequestRegistry',          N'EntityId'),
    (N'Record',                    N'Record',                           N'record',     N'RecordRegistry',               N'EntityId'),
    (N'TrainingModule',            N'Training module (a record cites it as second subject)', N'personnel', N'TrainingModule',  N'EntityId'),
    (N'Person',                    N'Person',                           N'personnel',  N'PersonRegistry',               N'EntityId'),
    (N'User',                      N'User',                             N'security',   N'UserRegistry',                 N'EntityId'),
    (N'Group',                     N'Group',                            N'security',   N'GroupRegistry',                N'EntityId'),
    (N'ObligationInstance',        N'Obligation instance',              N'compliance', N'ObligationInstanceRegistry',   N'EntityId'),
    (N'Audit',                     N'Compliance audit',                 N'compliance', N'AuditRegistry',                N'EntityId'),
    (N'Definition',                N'Definition',                       N'config',     N'DefinitionRegistry',           N'EntityId'),
    (N'DefinitionVersion',         N'Definition version (fact version)',N'config',     N'DefinitionVersion',            N'RowId'),
    (N'Platform',                  N'The platform itself (decision 56)',NULL,          NULL,                            NULL)
) AS s ([SubjectKindCode], [Name], [SchemaName], [TableName], [KeyColumnName])
ON t.[SubjectKindCode] = s.[SubjectKindCode]
WHEN MATCHED AND (t.[Name] <> s.[Name] OR ISNULL(t.[SchemaName], N'') <> ISNULL(s.[SchemaName], N'') OR ISNULL(t.[TableName], N'') <> ISNULL(s.[TableName], N'') OR ISNULL(t.[KeyColumnName], N'') <> ISNULL(s.[KeyColumnName], N''))
    THEN UPDATE SET [Name] = s.[Name], [SchemaName] = s.[SchemaName], [TableName] = s.[TableName], [KeyColumnName] = s.[KeyColumnName], [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET
    THEN INSERT ([SubjectKindCode], [Name], [SchemaName], [TableName], [KeyColumnName], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
         VALUES (s.[SubjectKindCode], s.[Name], s.[SchemaName], s.[TableName], s.[KeyColumnName], @actor, @now, @actor, @now);
GO
