-- Decision #61 (the text settings file), PROCEDURE-ENGINE §5.1, §9 (W4, decision #113). The text reader: parses a
-- name=value settings file (the legacy SET1 form: "WDG1=2.9, WDG2=2.9, SLOPE=25 %, HARMONIC RESTRAINT = 20%") against
-- the device model's template — the SettingDefinition rows of the Effective Transform.SettingsParse bound to the
-- device's current firmware — and writes document.ParsedSetting rows, so every setting reads as device.settings.<code>.
-- Names match case- and space-insensitively (HARMONIC RESTRAINT → HARMONIC_RESTRAINT) and by the template's Aliases
-- (#168: Z1 for Z1%, RO for R0 — the legacy spellings); a numeric value is the leading number of the value text (unit
-- words after it are ignored for the reading: "25 %", "12 CYCLES"); the value text itself is kept whole as RawValue so
-- the writer (RenderSettingsText) prints the file back as it was. A "LOGIC SETTINGS:" marker (the legacy overflow field's
-- own words) is a separator; a chained "MTB=MTO=MPT=00 00 00" gives every name the value (#168, the SEL-221F texts); an
-- empty value ("50H=") is not a setting and is noted. Range is checked against the definition's MinValue/MaxValue.
-- Unmatched names are listed in ParseError and the file's ParseStatus is Partial (Parsed when every pair matched; Empty
-- when the text held no pairs; NoTemplate when the model has no template yet — the text is kept, never refused, #166).
CREATE PROCEDURE [process].[ParseSettingsText]
    @ConfigurationFileRevisionRowId UNIQUEIDENTIFIER,
    @Text NVARCHAR(MAX),
    @ActorId UNIQUEIDENTIFIER = NULL,
    @Matched INT = NULL OUTPUT,
    @Unmatched INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @device UNIQUEIDENTIFIER, @fw UNIQUEIDENTIFIER;
    SELECT @device = [DeviceEntityId], @fw = [FirmwareVersionId] FROM [document].[ConfigurationFile] WHERE [RevisionRowId] = @ConfigurationFileRevisionRowId AND [IsDeleted] = 0;
    IF @device IS NULL THROW 50180, N'process.ParseSettingsText: the revision is not a device configuration file.', 1;
    -- the template: the parse transform bound to the file's firmware (or the device's current firmware)
    DECLARE @tdef UNIQUEIDENTIFIER;
    SELECT @tdef = [ParseTransformDefinitionEntityId] FROM [ref].[FirmwareVersion] WHERE [FirmwareVersionId] = ISNULL(@fw, (SELECT [CurrentFirmwareVersionId] FROM [device].[vDevice] WHERE [EntityId] = @device));
    -- W8 (#153): a device that names no firmware (every migrated relay: the legacy database has no firmware column that
    -- maps) takes its model's template — the one firmware row of the model that carries a Transform.SettingsParse binding
    IF @tdef IS NULL
        SELECT TOP (1) @tdef = fv.[ParseTransformDefinitionEntityId]
        FROM [ref].[FirmwareVersion] fv JOIN [asset].[vAsset] a ON a.[ModelId] = fv.[ModelId]
        WHERE a.[EntityId] = @device AND fv.[ParseTransformDefinitionEntityId] IS NOT NULL AND fv.[IsActive] = 1
        ORDER BY CASE WHEN fv.[VersionString] = N'n/a' THEN 0 ELSE 1 END, fv.[FirmwareVersionId];
    -- #166 (2026-09-15): a relay whose model has no settings template yet keeps its text as filed — the legacy program's
    -- floor — with ParseStatus NoTemplate; a template seeded later parses it on the next revision. Not a refusal.
    IF @tdef IS NULL
    BEGIN
        UPDATE [document].[ConfigurationFile] SET [ParseStatus] = N'NoTemplate', [ParseError] = N'the device''s model names no settings template (Transform.SettingsParse); the text is kept as filed',
               [ModifiedBy] = @ActorId, [ModifiedAt] = @now WHERE [RevisionRowId] = @ConfigurationFileRevisionRowId AND [IsDeleted] = 0;
        SET @Matched = 0; SET @Unmatched = 0; RETURN;
    END
    DECLARE @tver UNIQUEIDENTIFIER;
    SELECT TOP (1) @tver = dv.[RowId] FROM [config].[DefinitionVersion] dv
    WHERE dv.[DefinitionEntityId] = @tdef AND dv.[IsDeleted] = 0 AND dv.[Status] = N'Effective' AND dv.[EffectiveFrom] <= @now AND (dv.[EffectiveTo] IS NULL OR dv.[EffectiveTo] > @now)
    ORDER BY dv.[VersionNumber] DESC;
    IF @tver IS NULL
    BEGIN
        UPDATE [document].[ConfigurationFile] SET [ParseStatus] = N'NoTemplate', [ParseError] = N'the settings template has no Effective version; the text is kept as filed',
               [ModifiedBy] = @ActorId, [ModifiedAt] = @now WHERE [RevisionRowId] = @ConfigurationFileRevisionRowId AND [IsDeleted] = 0;
        SET @Matched = 0; SET @Unmatched = 0; RETURN;
    END

    -- the fragments: the text split on commas and line ends; "LOGIC SETTINGS:" (the legacy overflow field's marker) is a separator too
    DECLARE @t NVARCHAR(MAX) = REPLACE(REPLACE(REPLACE(@Text, NCHAR(13), N','), NCHAR(10), N','), N'LOGIC SETTINGS:', N',');
    -- a separator the legacy user missed ("PSVC=S 27VLO=40", "MTU=00 86 00 MRI=MPT=..." — 2026-09-16): a space followed by a name the
    -- template knows and '=' can only be a missing comma, so it is read as one and noted; a spaced separator is normalised first
    SET @t = REPLACE(@t, N', ', N',');
    DECLARE @sepNotes NVARCHAR(MAX), @sepName NVARCHAR(200);
    DECLARE sn CURSOR LOCAL FAST_FORWARD FOR
        SELECT x.[Name] FROM (SELECT sd.[SettingCode] AS [Name] FROM [config].[SettingDefinition] sd WHERE sd.[DefinitionVersionRowId] = @tver AND sd.[IsDeleted] = 0
                              UNION SELECT LTRIM(RTRIM(a.[value])) FROM [config].[SettingDefinition] sd CROSS APPLY STRING_SPLIT(sd.[Aliases], N',') a WHERE sd.[DefinitionVersionRowId] = @tver AND sd.[IsDeleted] = 0 AND sd.[Aliases] IS NOT NULL) x
        WHERE x.[Name] NOT LIKE N'% %' AND x.[Name] <> N'' ORDER BY LEN(x.[Name]) DESC;
    OPEN sn; FETCH NEXT FROM sn INTO @sepName;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF CHARINDEX(N' ' + @sepName + N'=', @t) > 0
        BEGIN
            SET @t = REPLACE(@t, N' ' + @sepName + N'=', N',' + @sepName + N'=');
            SET @sepNotes = CONCAT(ISNULL(@sepNotes + N', ', N''), @sepName);
        END
        FETCH NEXT FROM sn INTO @sepName;
    END
    CLOSE sn; DEALLOCATE sn;
    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS n, LTRIM(RTRIM(p.[value])) AS Fragment
    INTO #frag
    FROM STRING_SPLIT(@t, N',') p
    WHERE CHARINDEX(N'=', p.[value]) > 1;
    -- the pairs: a fragment with one '=' is NAME=value; a chained "A=B=C=value" gives every name the value (#168)
    CREATE TABLE #pairs (n INT NOT NULL, sub INT NOT NULL, Name NVARCHAR(200) NOT NULL, RawValue NVARCHAR(400) NOT NULL, Number DECIMAL(28,10) NULL);
    DECLARE @fn INT, @frag NVARCHAR(4000), @val NVARCHAR(4000), @nm NVARCHAR(4000), @sub INT, @i INT;
    DECLARE f CURSOR LOCAL FAST_FORWARD FOR SELECT n, Fragment FROM #frag ORDER BY n;
    OPEN f; FETCH NEXT FROM f INTO @fn, @frag;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @i = LEN(@frag) - CHARINDEX(N'=', REVERSE(@frag)) + 1;        -- the last '=': what follows is the value
        SET @val = LTRIM(RTRIM(SUBSTRING(@frag, @i + 1, 4000)));
        SET @nm = LEFT(@frag, @i - 1); SET @sub = 0;
        -- every name before the last '=' (one, or several chained)
        DECLARE nm CURSOR LOCAL FAST_FORWARD FOR SELECT LTRIM(RTRIM(x.[value])) FROM STRING_SPLIT(@nm, N'=') x WHERE LTRIM(RTRIM(x.[value])) <> N'';
        DECLARE @one NVARCHAR(200);
        OPEN nm; FETCH NEXT FROM nm INTO @one;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @sub += 1;
            INSERT #pairs (n, sub, Name, RawValue) VALUES (@fn, @sub, UPPER(REPLACE(@one, N' ', N'_')), LEFT(@val, 400));
            FETCH NEXT FROM nm INTO @one;
        END
        CLOSE nm; DEALLOCATE nm;
        FETCH NEXT FROM f INTO @fn, @frag;
    END
    CLOSE f; DEALLOCATE f;
    -- a misspelt marker glued to the first mask's name ("LOGIC SEETINGS: MTU" — six legacy texts, #168) is still the marker: the name is what follows the colon
    UPDATE #pairs SET Name = SUBSTRING(Name, CHARINDEX(N':', Name) + 1, 200) WHERE Name LIKE N'LOGIC%TINGS:%';
    UPDATE #pairs SET Name = SUBSTRING(Name, PATINDEX(N'%[^_]%', Name), 200) WHERE Name LIKE N'\_%' ESCAPE N'\';
    -- the leading number of the value text, if any (the reading; the text stays whole in RawValue)
    UPDATE #pairs SET Number = TRY_CONVERT(DECIMAL(28,10), LEFT(RawValue, ISNULL(NULLIF(PATINDEX(N'%[^0-9.+-]%', RawValue + N' '), 0) - 1, LEN(RawValue)))) WHERE RawValue <> N'';

    -- match by code or by one of the template's aliases
    SELECT p.n, p.sub, p.Name, p.RawValue, p.Number, sd.[RowId] AS DefRowId, sd.[DataType], sd.[MinValue], sd.[MaxValue]
    INTO #m
    FROM #pairs p LEFT JOIN [config].[SettingDefinition] sd ON sd.[DefinitionVersionRowId] = @tver AND sd.[IsDeleted] = 0
        AND (UPPER(sd.[SettingCode]) = p.Name
             OR (sd.[Aliases] IS NOT NULL AND EXISTS (SELECT 1 FROM STRING_SPLIT(UPPER(sd.[Aliases]), N',') a WHERE LTRIM(RTRIM(a.[value])) = p.Name)));

    -- a chained fragment is a chain unless one of its segments is a value and a name run together; then it is one pair whose value holds the
    -- rest ("PSVC=S 27VLO=40" — a comma the legacy user missed): the value shows the defect instead of a wrong number landing
    -- in PSVC and 27VLO (#168). Re-read such fragments at their first '='.
    DECLARE @bad TABLE (n INT PRIMARY KEY);
    INSERT @bad SELECT DISTINCT n FROM #m m WHERE sub > 1 OR EXISTS (SELECT 1 FROM #m x WHERE x.n = m.n AND x.sub > 1);
    -- a chain is malformed only when an unresolved segment is more than one word ("S 27VLO": a value and a name run together);
    -- an unresolved single word in a chain is a misspelt name ("MBT" for MTB, "M4A" for MA4 — 2026-09-16) and the other names keep the value
    DELETE @bad WHERE n NOT IN (SELECT n FROM #m WHERE DefRowId IS NULL AND Name LIKE N'%\_%' ESCAPE N'\');
    DECLARE @malformed NVARCHAR(MAX) = (SELECT STRING_AGG(LEFT(f.Fragment, 60), N'; ') FROM #frag f JOIN @bad b ON b.n = f.n);
    DELETE #m WHERE n IN (SELECT n FROM @bad);
    INSERT #m (n, sub, Name, RawValue, Number, DefRowId, DataType, MinValue, MaxValue)
    SELECT f.n, 1, UPPER(REPLACE(LTRIM(RTRIM(LEFT(f.Fragment, CHARINDEX(N'=', f.Fragment) - 1))), N' ', N'_')),
           LEFT(LTRIM(RTRIM(SUBSTRING(f.Fragment, CHARINDEX(N'=', f.Fragment) + 1, 4000))), 400), NULL, sd.[RowId], sd.[DataType], sd.[MinValue], sd.[MaxValue]
    FROM #frag f JOIN @bad b ON b.n = f.n
    LEFT JOIN [config].[SettingDefinition] sd ON sd.[DefinitionVersionRowId] = @tver AND sd.[IsDeleted] = 0
        AND (UPPER(sd.[SettingCode]) = UPPER(REPLACE(LTRIM(RTRIM(LEFT(f.Fragment, CHARINDEX(N'=', f.Fragment) - 1))), N' ', N'_'))
             OR (sd.[Aliases] IS NOT NULL AND EXISTS (SELECT 1 FROM STRING_SPLIT(UPPER(sd.[Aliases]), N',') a WHERE LTRIM(RTRIM(a.[value])) = UPPER(REPLACE(LTRIM(RTRIM(LEFT(f.Fragment, CHARINDEX(N'=', f.Fragment) - 1))), N' ', N'_')))));
    UPDATE #m SET Number = TRY_CONVERT(DECIMAL(28,10), LEFT(RawValue, ISNULL(NULLIF(PATINDEX(N'%[^0-9.+-]%', RawValue + N' '), 0) - 1, LEN(RawValue)))) WHERE n IN (SELECT n FROM @bad) AND RawValue <> N'';

    BEGIN TRANSACTION;
    -- a re-parse (a template revised, #168) closes the previous reading's rows in valid time; the history keeps them
    UPDATE [document].[ParsedSetting] SET [ValidTo] = @now, [ModifiedBy] = @ActorId, [ModifiedAt] = @now
    WHERE [ConfigurationFileRevisionRowId] = @ConfigurationFileRevisionRowId AND [ValidTo] IS NULL AND [IsDeleted] = 0;
    DECLARE @n INT, @def UNIQUEIDENTIFIER, @dt NVARCHAR(20), @num DECIMAL(28,10), @raw NVARCHAR(400), @min DECIMAL(28,10), @max DECIMAL(28,10);
    -- W8 (#153): a legacy text can name a setting twice (11 of 949 migrated SEL files repeat a name, e.g. 50N2P); the first
    -- occurrence is the value, the repeat is noted — a second row would break UX_ParsedSetting_Current and lose the whole file
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT n, DefRowId, DataType, Number, RawValue, MinValue, MaxValue FROM #m m
        WHERE DefRowId IS NOT NULL AND RawValue <> N''
          AND n * 1000 + sub = (SELECT MIN(x.n * 1000 + x.sub) FROM #m x WHERE x.DefRowId = m.DefRowId AND x.RawValue <> N'') ORDER BY n, sub;
    OPEN c; FETCH NEXT FROM c INTO @n, @def, @dt, @num, @raw, @min, @max;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @rc NVARCHAR(20) = N'NotChecked', @note NVARCHAR(400) = NULL;
        IF @dt IN (N'Decimal', N'Integer') AND @num IS NOT NULL
        BEGIN
            IF @min IS NULL AND @max IS NULL SET @rc = N'NotChecked';
            ELSE IF (@min IS NULL OR @num >= @min) AND (@max IS NULL OR @num <= @max) SET @rc = N'Ok';
            ELSE BEGIN SET @rc = N'OutOfRange'; SET @note = CONCAT(N'value ', [compliance].[fDecText](@num), N' outside ', ISNULL([compliance].[fDecText](@min), N'-'), N'..', ISNULL([compliance].[fDecText](@max), N'-')); END
        END
        IF @dt = N'Integer' AND @num IS NOT NULL AND @num = ROUND(@num, 0)
            EXEC [document].[ParsedSetting_Add] @ConfigurationFileRevisionRowId = @ConfigurationFileRevisionRowId, @SettingDefinitionRowId = @def, @IntegerValue = @num, @RawValue = @raw, @RangeCheck = @rc, @RangeCheckNote = @note, @ActorId = @ActorId;
        ELSE IF @dt IN (N'Decimal', N'Integer') AND @num IS NOT NULL
            EXEC [document].[ParsedSetting_Add] @ConfigurationFileRevisionRowId = @ConfigurationFileRevisionRowId, @SettingDefinitionRowId = @def, @DecimalValue = @num, @RawValue = @raw, @RangeCheck = @rc, @RangeCheckNote = @note, @ActorId = @ActorId;
        ELSE
            EXEC [document].[ParsedSetting_Add] @ConfigurationFileRevisionRowId = @ConfigurationFileRevisionRowId, @SettingDefinitionRowId = @def, @TextValue = @raw, @RawValue = @raw, @RangeCheck = N'NotChecked', @ActorId = @ActorId;
        FETCH NEXT FROM c INTO @n, @def, @dt, @num, @raw, @min, @max;
    END
    CLOSE c; DEALLOCATE c;
    SET @Matched = (SELECT COUNT(*) FROM #m WHERE DefRowId IS NOT NULL AND RawValue <> N'');
    SET @Unmatched = (SELECT COUNT(*) FROM #m WHERE DefRowId IS NULL);
    DECLARE @status NVARCHAR(20) = CASE WHEN @Matched = 0 AND @Unmatched = 0 THEN N'Empty' WHEN @Unmatched = 0 THEN N'Parsed' ELSE N'Partial' END;
    DECLARE @err NVARCHAR(MAX) = CASE WHEN @Unmatched = 0 THEN NULL ELSE N'not in the template: ' + (SELECT STRING_AGG(Name, N', ') FROM #m WHERE DefRowId IS NULL) END;
    DECLARE @dups NVARCHAR(MAX) = (SELECT STRING_AGG(Name, N', ') FROM (SELECT Name FROM #m WHERE DefRowId IS NOT NULL AND RawValue <> N'' GROUP BY Name HAVING COUNT(*) > 1) d);
    IF @dups IS NOT NULL SET @err = CONCAT(ISNULL(@err + N'; ', N''), N'repeated in the text (first value kept): ', @dups);
    DECLARE @empty NVARCHAR(MAX) = (SELECT STRING_AGG(Name, N', ') FROM #m WHERE RawValue = N'');
    IF @empty IS NOT NULL SET @err = CONCAT(ISNULL(@err + N'; ', N''), N'empty value (not set): ', @empty);
    IF @malformed IS NOT NULL SET @err = CONCAT(ISNULL(@err + N'; ', N''), N'malformed (a separator missing?): ', @malformed);
    IF @sepNotes IS NOT NULL SET @err = CONCAT(ISNULL(@err + N'; ', N''), N'a separator was missing before: ', @sepNotes);
    UPDATE [document].[ConfigurationFile] SET [ParseStatus] = @status, [ParseError] = @err, [ModifiedBy] = @ActorId, [ModifiedAt] = @now
    WHERE [RevisionRowId] = @ConfigurationFileRevisionRowId AND [IsDeleted] = 0;
    COMMIT TRANSACTION;
END;
GO
