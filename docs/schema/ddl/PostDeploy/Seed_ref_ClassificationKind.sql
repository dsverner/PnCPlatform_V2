-- SCHEMA-DESIGN §4.7 (95): the four classification kinds the design names. Allowed values per
-- kind are not stated; AllowedValuesDefinitionRowId stays null for the Administrator to attach.
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [ref].[ClassificationKind] AS t
USING (VALUES
    (N'BesStatus',            N'BES status'),
    (N'CipImpactRating',      N'CIP impact rating'),
    (N'NpccBulkPowerSystem',  N'NPCC bulk power system (declared by the A-10 study)'),
    (N'NpccA10',              N'NPCC A-10 list (retired 2026-09-16: the A-10 study declares the BPS bus — NpccBulkPowerSystem)'),
    (N'Prc023',               N'PRC-023 list (impactful lines)')
) AS s ([ClassificationKindCode], [Name])
ON t.[ClassificationKindCode] = s.[ClassificationKindCode]
WHEN MATCHED AND t.[Name] <> s.[Name] THEN UPDATE SET [Name] = s.[Name], [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET
    THEN INSERT ([ClassificationKindCode], [Name], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
         VALUES (s.[ClassificationKindCode], s.[Name], @actor, @now, @actor, @now);
GO
-- #170 (owner, 2026-09-16): the A-10 study is what declares an NPCC BPS bus — one kind, NpccBulkPowerSystem; NpccA10 is retired
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
UPDATE [ref].[ClassificationKind] SET [IsActive] = 0, [ModifiedBy] = @actor, [ModifiedAt] = SYSDATETIMEOFFSET() WHERE [ClassificationKindCode] = N'NpccA10' AND [IsActive] = 1;
GO
