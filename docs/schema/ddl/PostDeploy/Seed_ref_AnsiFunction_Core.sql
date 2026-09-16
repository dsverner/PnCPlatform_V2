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
