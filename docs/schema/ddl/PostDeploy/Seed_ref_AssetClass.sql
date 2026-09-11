-- SCHEMA-DESIGN §4.1 (88): the four asset classes. The vision's one-line rule per class is not
-- quoted in the design table, so Rule stays null until the owner supplies the text.
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [ref].[AssetClass] AS t
USING (VALUES
    (N'Primary',      N'Primary'),
    (N'Secondary',    N'Secondary'),
    (N'Hybrid',       N'Hybrid (the predecessor''s INTERFACE)'),
    (N'NonEnergised', N'Non-energised')
) AS s ([AssetClassCode], [Name])
ON t.[AssetClassCode] = s.[AssetClassCode]
WHEN MATCHED AND t.[Name] <> s.[Name] THEN UPDATE SET [Name] = s.[Name], [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET
    THEN INSERT ([AssetClassCode], [Name], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
         VALUES (s.[AssetClassCode], s.[Name], @actor, @now, @actor, @now);
GO
