-- SCHEMA-DESIGN §2.3 (75): the twelve dimensions.
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [ref].[AppliesToDimension] AS t
USING (VALUES
    (N'Manufacturer',          N'Manufacturer',            N'Entity', N'Entity'),
    (N'Model',                 N'Model',                   N'Code',   NULL),
    (N'FirmwareVersion',       N'Firmware version',        N'Code',   NULL),
    (N'AssetClass',            N'Asset class',             N'Code',   NULL),
    (N'AssetType',             N'Asset type',              N'Code',   NULL),
    (N'SchemeType',            N'Scheme type definition',  N'Entity', N'Definition'),
    (N'ProtectionApplication', N'Protection application',  N'Code',   NULL),
    (N'DocumentClass',         N'Document class definition',N'Entity', N'Definition'),
    (N'SubjectKind',           N'Subject kind',            N'Code',   NULL),
    (N'StationType',           N'Station type (subtype)',  N'Code',   NULL),
    (N'VoltageClass',          N'Voltage class',           N'Code',   NULL),
    (N'WorkType',              N'Work type definition',    N'Entity', N'Definition')
) AS s ([DimensionCode], [Name], [ValueKind], [SubjectKindCode])
ON t.[DimensionCode] = s.[DimensionCode]
WHEN MATCHED AND (t.[Name] <> s.[Name] OR t.[ValueKind] <> s.[ValueKind] OR ISNULL(t.[SubjectKindCode], N'') <> ISNULL(s.[SubjectKindCode], N''))
    THEN UPDATE SET [Name] = s.[Name], [ValueKind] = s.[ValueKind], [SubjectKindCode] = s.[SubjectKindCode], [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET
    THEN INSERT ([DimensionCode], [Name], [ValueKind], [SubjectKindCode], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
         VALUES (s.[DimensionCode], s.[Name], s.[ValueKind], s.[SubjectKindCode], @actor, @now, @actor, @now);
GO
