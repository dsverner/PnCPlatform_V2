-- SCHEMA-DESIGN §1.3 (decision 65): read logging on for configuration files and evidence packages.
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [config].[ReadLoggedClass] AS t
USING (VALUES
    (N'document',   N'ConfigurationFile', 1),
    (N'compliance', N'EvidencePackage',   1)
) AS s ([SchemaName], [TableName], [IsLogged])
ON t.[SchemaName] = s.[SchemaName] AND t.[TableName] = s.[TableName]
WHEN NOT MATCHED BY TARGET
    THEN INSERT ([SchemaName], [TableName], [IsLogged], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
         VALUES (s.[SchemaName], s.[TableName], s.[IsLogged], @actor, @now, @actor, @now);
GO
