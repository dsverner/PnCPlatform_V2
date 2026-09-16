-- SCHEMA-DESIGN §4.7 (95): the four classification kinds the design names. Allowed values per
-- kind are not stated; AllowedValuesDefinitionRowId stays null for the Administrator to attach.
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [ref].[ClassificationKind] AS t
USING (VALUES
    (N'BesStatus',            N'BES status'),
    (N'CipImpactRating',      N'CIP impact rating'),
    (N'NpccBulkPowerSystem',  N'NPCC bulk power system'),
    (N'NpccA10',              N'NPCC A-10 list'),
    (N'Prc023',               N'PRC-023 list (impactful lines)')
) AS s ([ClassificationKindCode], [Name])
ON t.[ClassificationKindCode] = s.[ClassificationKindCode]
WHEN MATCHED AND t.[Name] <> s.[Name] THEN UPDATE SET [Name] = s.[Name], [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET
    THEN INSERT ([ClassificationKindCode], [Name], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
         VALUES (s.[ClassificationKindCode], s.[Name], @actor, @now, @actor, @now);
GO
