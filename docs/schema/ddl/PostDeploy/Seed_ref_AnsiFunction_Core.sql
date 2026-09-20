-- #168 (2026-09-16): the ANSI/IEEE C37.2 function numbers the settings templates cite, so a fresh database can bind them
-- (ref.AnsiFunction had no seed — the legacy import fills it on a migrated database). Names per C37.2; idempotent upsert.
IF OBJECT_ID(N'[ref].[AnsiFunction_Upsert]') IS NULL RETURN;
GO
DECLARE @a UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @c NVARCHAR(10), @n NVARCHAR(200), @cat NVARCHAR(40);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT [Code], [Name], [Category] FROM (VALUES
    (N'21',   N'Distance relay',                         N'Protection'),
    (N'25',   N'Synchronizing or synchronism-check device', N'Control'),
    (N'27',   N'Undervoltage relay',                     N'Protection'),
    (N'50',   N'Instantaneous overcurrent relay',        N'Protection'),
    (N'50N',  N'Instantaneous neutral overcurrent relay', N'Protection'),
    (N'50BF', N'Breaker failure relay',                  N'Protection'),
    (N'51',   N'AC time overcurrent relay',              N'Protection'),
    (N'51N',  N'AC time neutral overcurrent relay',      N'Protection'),
    (N'59',   N'Overvoltage relay',                      N'Protection'),
    (N'67',   N'AC directional overcurrent relay',       N'Protection'),
    (N'67N',  N'AC directional neutral overcurrent relay', N'Protection'),
    (N'78',   N'Phase-angle measuring or out-of-step protective relay', N'Protection'),   -- #197: PRC-023-6 Attachment A 1.2
    (N'79',   N'AC reclosing relay',                     N'Control'),
    (N'87',   N'Differential protective relay',          N'Protection')
) x ([Code], [Name], [Category]);
OPEN c; FETCH NEXT FROM c INTO @c, @n, @cat;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- the C37.2 name wins: the legacy import named a code after the first position text that carried it (a defect, #168)
    EXEC [ref].[AnsiFunction_Upsert] @AnsiCode = @c, @Name = @n, @Category = @cat, @ActorId = @a;
    FETCH NEXT FROM c INTO @c, @n, @cat;
END
CLOSE c; DEALLOCATE c;
GO

-- #182 (2026-09-17): the codes above ARE C37.2 device numbers, and are marked so. The flag is set by a plain UPDATE
-- rather than through the upsert: that procedure is GENERATED from the deployed catalogue, so on the publish that adds
-- the column it does not yet take the parameter. A column and the procedure that writes it arrive one publish apart.
UPDATE [ref].[AnsiFunction] SET [IsDeviceNumber] = 1
 WHERE [IsDeviceNumber] IS NULL
   AND [AnsiCode] IN (N'21', N'25', N'27', N'50', N'50N', N'50BF', N'51', N'51N', N'59', N'67', N'67N', N'78', N'79', N'87');
GO

-- #197 (2026-09-19): which of these PRC-023-6 applies to. The standard binds "load-responsive phase protection systems as
-- described in Attachment A" (4.1). Attachment A 1 includes: 1.1 phase distance, 1.2 out-of-step tripping, 1.3 switch-on-to-
-- fault, 1.4 overcurrent relays, 1.5 communications-aided schemes, 1.6 phase overcurrent supervision of current-based pilot
-- schemes. Attachment A 2 excludes: 2.2 "protection systems intended for the detection of ground fault conditions", among
-- others. Differential (87) is not listed: a differential element measures the difference current, not load. The owner,
-- 2026-09-19: "a device is only applicable if it has a load responsive element... in service"; the neutral overcurrent MCGG22
-- had been shown a PRC-023 obligation it never had. A plain UPDATE for the reason #182 gives above (generated upsert).
-- Read from https://www.nerc.com/pa/Stand/Reliability%20Standards/PRC-023-6.pdf (FERC letter order 2024-01-24).
IF NOT EXISTS (SELECT 1 FROM [ref].[AnsiFunction] WHERE [AnsiCode] = N'SOTF')
    EXEC [ref].[AnsiFunction_Upsert] @AnsiCode = N'SOTF', @Name = N'Switch-onto-fault protection', @Category = N'Protection', @ActorId = '00000000-0000-0000-0000-000000000001';
UPDATE [ref].[AnsiFunction] SET [IsDeviceNumber] = 0 WHERE [AnsiCode] = N'SOTF' AND [IsDeviceNumber] IS NULL;
UPDATE a SET [LoadResponsive] = x.[Yes], [LoadResponsiveBasis] = x.[Basis]
FROM [ref].[AnsiFunction] a
JOIN (VALUES
    (N'21',   1, N'phase distance (PRC-023-6 Attachment A 1.1)'),
    (N'78',   1, N'out-of-step tripping (PRC-023-6 Attachment A 1.2)'),
    (N'SOTF', 1, N'switch-on-to-fault (PRC-023-6 Attachment A 1.3)'),
    (N'50',   1, N'overcurrent relay (PRC-023-6 Attachment A 1.4)'),
    (N'51',   1, N'overcurrent relay (PRC-023-6 Attachment A 1.4)'),
    (N'67',   1, N'overcurrent relay (PRC-023-6 Attachment A 1.4)'),
    (N'50N',  0, N'ground fault detection (PRC-023-6 Attachment A 2.2)'),
    (N'51N',  0, N'ground fault detection (PRC-023-6 Attachment A 2.2)'),
    (N'67N',  0, N'ground fault detection (PRC-023-6 Attachment A 2.2)'),
    (N'87',   0, N'not listed in PRC-023-6 Attachment A 1: a differential element measures the difference current, not load'),
    (N'25',   0, N'not listed in PRC-023-6 Attachment A 1 (not a load-responsive protective function)'),
    (N'27',   0, N'not listed in PRC-023-6 Attachment A 1 (not a load-responsive protective function)'),
    (N'59',   0, N'not listed in PRC-023-6 Attachment A 1 (not a load-responsive protective function)'),
    (N'79',   0, N'not listed in PRC-023-6 Attachment A 1 (not a load-responsive protective function)'),
    (N'50BF', 0, N'not listed in PRC-023-6 Attachment A 1 (not a load-responsive protective function)')
) x ([Code], [Yes], [Basis]) ON x.[Code] = a.[AnsiCode]
WHERE a.[LoadResponsive] IS NULL OR a.[LoadResponsive] <> x.[Yes] OR ISNULL(a.[LoadResponsiveBasis], N'') <> x.[Basis];
GO

-- The rest of the catalogue. Everything else in this catalogue is
-- either a manufacturer's abbreviation added deliberately with a manual behind it (marked 0 by the seed that adds it) or
-- a string the legacy importer invented from a position's free text (left NULL — nobody has said what it is).
GO

-- #206 (2026-09-20): which analog inputs a function of each number needs — the owner's rule: "when a particular device
-- indicates that it has CT and PT inputs, it is reasonable to assume that they exist because without them, the protection
-- is useless ... a KD relay is a distance protection which requires voltage and current inputs." I = current, V = voltage,
-- IV = both, VSYNC = a synchronising voltage (the 25's sync input), NONE = no analog input (timers, pilot channels, lockouts,
-- breakers, annunciators). The table was proposed by the session from the device numbers' own definitions and approved by
-- the owner with the #206 plan on 2026-09-20; it is NOT read from a standard's text (C37.2 names the functions, it does not
-- list their inputs), which the basis says. A base code the legacy strings use but the catalogue lacks (46, 49, 37, 47, 24,
-- 32, 40, 55, 62, 85, 94, 74, 48, 52, 86, 63, 90, 97, 30, 12) is added with its NUMBER as its name — no C37.2 name is
-- invented here; a later seed may name it from the standard. A plain UPDATE for the reason #182 gives (generated upsert).
DECLARE @a206 UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @c206 NVARCHAR(10);
DECLARE c206 CURSOR LOCAL FAST_FORWARD FOR SELECT [Code] FROM (VALUES
    (N'46'), (N'49'), (N'37'), (N'47'), (N'24'), (N'32'), (N'40'), (N'55'), (N'81'), (N'62'), (N'85'), (N'94'), (N'74'), (N'48'), (N'52'), (N'86'), (N'63'), (N'90'), (N'97'), (N'30'), (N'12'), (N'60'), (N'64'), (N'51G'), (N'87T')) x ([Code])
    WHERE NOT EXISTS (SELECT 1 FROM [ref].[AnsiFunction] f WHERE f.[AnsiCode] = x.[Code]);
OPEN c206; FETCH NEXT FROM c206 INTO @c206;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC [ref].[AnsiFunction_Upsert] @AnsiCode = @c206, @Name = @c206, @Category = NULL, @ActorId = @a206;
    FETCH NEXT FROM c206 INTO @c206;
END
CLOSE c206; DEALLOCATE c206;
UPDATE a SET [AnalogInputs] = x.[Inputs], [AnalogInputsBasis] = x.[Basis]
FROM [ref].[AnsiFunction] a
JOIN (VALUES
    (N'50',   N'I',     N'instantaneous overcurrent measures current (owner-approved table, #206 plan, 2026-09-20)'),
    (N'50N',  N'I',     N'neutral overcurrent measures current (owner-approved table, #206)'),
    (N'50BF', N'I',     N'breaker failure measures current (owner-approved table, #206)'),
    (N'51',   N'I',     N'time overcurrent measures current (owner-approved table, #206)'),
    (N'51N',  N'I',     N'neutral time overcurrent measures current (owner-approved table, #206)'),
    (N'51G',  N'I',     N'ground time overcurrent measures current (owner-approved table, #206)'),
    (N'46',   N'I',     N'negative-sequence / phase-balance current (owner-approved table, #206)'),
    (N'49',   N'I',     N'thermal, from current (owner-approved table, #206)'),
    (N'87',   N'I',     N'differential measures currents (owner-approved table, #206)'),
    (N'87T',  N'I',     N'transformer differential measures currents (owner-approved table, #206)'),
    (N'37',   N'I',     N'undercurrent (owner-approved table, #206)'),
    (N'27',   N'V',     N'undervoltage measures voltage (owner-approved table, #206)'),
    (N'59',   N'V',     N'overvoltage measures voltage (owner-approved table, #206)'),
    (N'81',   N'V',     N'frequency, from voltage (owner-approved table, #206)'),
    (N'47',   N'V',     N'phase-sequence / phase-balance voltage (owner-approved table, #206)'),
    (N'24',   N'V',     N'volts per hertz, from voltage (owner-approved table, #206)'),
    (N'21',   N'IV',    N'distance needs voltage and current — the owner''s KD example (#206)'),
    (N'67',   N'IV',    N'directional overcurrent: current, polarised by voltage (owner-approved table, #206)'),
    (N'67N',  N'IV',    N'directional neutral overcurrent: current, polarised by voltage (owner-approved table, #206)'),
    (N'32',   N'IV',    N'directional power: voltage and current (owner-approved table, #206)'),
    (N'40',   N'IV',    N'loss of field: voltage and current (owner-approved table, #206)'),
    (N'78',   N'IV',    N'out-of-step: impedance from voltage and current (owner-approved table, #206)'),
    (N'55',   N'IV',    N'power factor: voltage and current (owner-approved table, #206)'),
    (N'SOTF', N'I',     N'switch-onto-fault: overcurrent supervision (owner-approved table, #206)'),
    (N'25',   N'VSYNC', N'synchronism check: the sync-input voltage, a single-phase PT (owner, 2026-09-20: "a single phase PT feeding the sync input")'),
    (N'62',   N'NONE',  N'timer (owner-approved table, #206)'),
    (N'85',   N'NONE',  N'pilot / communications (owner-approved table, #206)'),
    (N'79',   N'NONE',  N'reclosing (owner-approved table, #206)'),
    (N'94',   N'NONE',  N'tripping relay (owner-approved table, #206)'),
    (N'74',   N'NONE',  N'alarm (owner-approved table, #206)'),
    (N'48',   N'NONE',  N'incomplete sequence (owner-approved table, #206)'),
    (N'52',   N'NONE',  N'circuit breaker (owner-approved table, #206)'),
    (N'86',   N'NONE',  N'lockout (owner-approved table, #206)'),
    (N'63',   N'NONE',  N'pressure (owner-approved table, #206)'),
    (N'90',   N'NONE',  N'regulating (owner-approved table, #206)'),
    (N'97',   N'NONE',  N'runner / auxiliary (owner-approved table, #206)'),
    (N'30',   N'NONE',  N'annunciator (owner-approved table, #206)'),
    (N'12',   N'NONE',  N'overspeed (owner-approved table, #206)'),
    (N'60',   N'NONE',  N'left NONE: voltage or current balance — which input varies by scheme; to be ruled (#206)'),
    (N'64',   N'NONE',  N'left NONE: ground / stator earth-fault schemes vary; to be ruled (#206)')
) x ([Code], [Inputs], [Basis]) ON x.[Code] = a.[AnsiCode]
WHERE a.[AnalogInputs] IS NULL OR a.[AnalogInputs] <> x.[Inputs] OR ISNULL(a.[AnalogInputsBasis], N'') <> x.[Basis];
GO
