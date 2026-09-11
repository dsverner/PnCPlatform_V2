-- SCHEMA-DESIGN §6.2 (108): connection realisations.
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [ref].[ConnectionRealisation] AS t
USING (VALUES
    (N'PanelWire',      N'Panel wire'),
    (N'CableConductor', N'Cable conductor'),
    (N'Goose',          N'IEC 61850 GOOSE'),
    (N'SampledValues',  N'IEC 61850 sampled values'),
    (N'Mms',            N'IEC 61850 MMS'),
    (N'Serial',         N'Serial'),
    (N'Routable',       N'Routable'),
    (N'EthernetLink',   N'Ethernet link'),
    (N'FiberLink',      N'Fiber link'),
    (N'SerialLink',     N'Serial link'),
    (N'OverChannel',    N'Over a channel')
) AS s ([RealisationCode], [Name])
ON t.[RealisationCode] = s.[RealisationCode]
WHEN MATCHED AND t.[Name] <> s.[Name] THEN UPDATE SET [Name] = s.[Name], [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET THEN INSERT ([RealisationCode], [Name], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
    VALUES (s.[RealisationCode], s.[Name], @actor, @now, @actor, @now);
GO
