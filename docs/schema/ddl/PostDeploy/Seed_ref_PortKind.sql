-- SCHEMA-DESIGN §6.1 (107): port kinds.
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [ref].[PortKind] AS t
USING (VALUES
    (N'CurrentInput',    N'Current input'),
    (N'VoltageInput',    N'Voltage input'),
    (N'ContactOutput',   N'Contact output'),
    (N'ContactInput',    N'Contact input'),
    (N'TripCoil',        N'Trip coil'),
    (N'AuxiliaryContact',N'Auxiliary contact'),
    (N'CtSecondaryCore', N'CT secondary core'),
    (N'TerminalCommon',  N'Terminal common'),
    (N'Ethernet',        N'Ethernet'),
    (N'Serial',          N'Serial'),
    (N'Fiber',           N'Fiber'),
    (N'Antenna',         N'Antenna'),
    (N'DcSupply',        N'DC supply')
) AS s ([PortKindCode], [Name])
ON t.[PortKindCode] = s.[PortKindCode]
WHEN MATCHED AND t.[Name] <> s.[Name] THEN UPDATE SET [Name] = s.[Name], [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET THEN INSERT ([PortKindCode], [Name], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
    VALUES (s.[PortKindCode], s.[Name], @actor, @now, @actor, @now);
GO
