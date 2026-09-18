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
   AND [AnsiCode] IN (N'21', N'25', N'27', N'50', N'50N', N'50BF', N'51', N'51N', N'59', N'67', N'67N', N'79', N'87');
GO

-- The rest of the catalogue. Everything else in this catalogue is
-- either a manufacturer's abbreviation added deliberately with a manual behind it (marked 0 by the seed that adds it) or
-- a string the legacy importer invented from a position's free text (left NULL — nobody has said what it is).
GO
