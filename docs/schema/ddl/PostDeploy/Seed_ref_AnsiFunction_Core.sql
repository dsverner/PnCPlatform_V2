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
