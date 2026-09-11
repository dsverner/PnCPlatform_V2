-- SCHEMA-DESIGN §4.9: the unit codes the design lists. Conversion factors only where they are
-- exact by definition (SI prefixes, ft = 0.3048 m, % and pu as ratios); otherwise null.
-- "cycles" has no fixed factor to seconds (depends on system frequency) — null by design.
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
-- base units first so self/forward references resolve
MERGE [ref].[Unit] AS t
USING (VALUES
    (N'V',      N'volt',                 N'Voltage',        NULL,   NULL),
    (N'A',      N'ampere',               N'Current',        NULL,   NULL),
    (N'VA',     N'volt-ampere',          N'ApparentPower',  NULL,   NULL),
    (N'W',      N'watt',                 N'Power',          NULL,   NULL),
    (N'Ah',     N'ampere-hour',          N'Charge',         NULL,   NULL),
    (N'Ω',      N'ohm',                  N'Impedance',      NULL,   NULL),
    (N'ratio',  N'dimensionless ratio',  N'Ratio',          NULL,   NULL),
    (N's',      N'second',               N'Time',           NULL,   NULL),
    (N'Hz',     N'hertz',                N'Frequency',      NULL,   NULL),
    (N'm',      N'metre',                N'Length',         NULL,   NULL),
    (N'°C',     N'degree Celsius',       N'Temperature',    NULL,   NULL)
) AS s ([UnitCode], [Name], [Dimension], [BaseUnitCode], [ToBaseFactor])
ON t.[UnitCode] = s.[UnitCode]
WHEN NOT MATCHED BY TARGET
    THEN INSERT ([UnitCode], [Name], [Dimension], [BaseUnitCode], [ToBaseFactor], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
         VALUES (s.[UnitCode], s.[Name], s.[Dimension], s.[BaseUnitCode], s.[ToBaseFactor], @actor, @now, @actor, @now);
MERGE [ref].[Unit] AS t
USING (VALUES
    (N'kV',     N'kilovolt',             N'Voltage',        N'V',     1000),
    (N'kA',     N'kiloampere',           N'Current',        N'A',     1000),
    (N'MVA',    N'megavolt-ampere',      N'ApparentPower',  N'VA',    1000000),
    (N'MW',     N'megawatt',             N'Power',          N'W',     1000000),
    (N'%',      N'percent',              N'Ratio',          N'ratio', 0.01),
    (N'pu',     N'per unit',             N'Ratio',          N'ratio', 1),
    (N'ms',     N'millisecond',          N'Time',           N's',     0.001),
    (N'cycles', N'cycles (system frequency)', N'Time',      NULL,     NULL),
    (N'ft',     N'foot',                 N'Length',         N'm',     0.3048),
    (N'km',     N'kilometre',            N'Length',         N'm',     1000),
    (N'mi',     N'mile (statute)',       N'Length',         N'm',     1609.344),
    (N'min',    N'minute',               N'Time',           N's',     60)
) AS s ([UnitCode], [Name], [Dimension], [BaseUnitCode], [ToBaseFactor])
ON t.[UnitCode] = s.[UnitCode]
WHEN NOT MATCHED BY TARGET
    THEN INSERT ([UnitCode], [Name], [Dimension], [BaseUnitCode], [ToBaseFactor], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
         VALUES (s.[UnitCode], s.[Name], s.[Dimension], s.[BaseUnitCode], s.[ToBaseFactor], @actor, @now, @actor, @now);
GO
