-- Decision #61 (the text settings file), PROCEDURE-ENGINE §5.1, §9 (W4, decision #113). The text reader: parses a
-- name=value settings file (the legacy SET1 form: "WDG1=2.9, WDG2=2.9, SLOPE=25 %, HARMONIC RESTRAINT = 20%") against
-- the device model's template — the SettingDefinition rows of the Effective Transform.SettingsParse bound to the
-- device's current firmware — and writes document.ParsedSetting rows, so every setting reads as device.settings.<code>.
-- Names match case- and space-insensitively (HARMONIC RESTRAINT → HARMONIC_RESTRAINT); a numeric value is the leading
-- number of the value text (unit words after it are ignored: "25 %", "1.4 OHMS"); anything else is text. Range is
-- checked against the definition's MinValue/MaxValue. Unmatched names are listed in ParseError and the file's
-- ParseStatus is Partial (Parsed when every pair matched; Empty when the text held no pairs).
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
    IF @tdef IS NULL THROW 50181, N'process.ParseSettingsText: the device''s firmware names no settings template (Transform.SettingsParse).', 1;
    DECLARE @tver UNIQUEIDENTIFIER;
    SELECT TOP (1) @tver = dv.[RowId] FROM [config].[DefinitionVersion] dv
    WHERE dv.[DefinitionEntityId] = @tdef AND dv.[IsDeleted] = 0 AND dv.[Status] = N'Effective' AND dv.[EffectiveFrom] <= @now AND (dv.[EffectiveTo] IS NULL OR dv.[EffectiveTo] > @now)
    ORDER BY dv.[VersionNumber] DESC;
    IF @tver IS NULL THROW 50182, N'process.ParseSettingsText: the settings template has no Effective version.', 1;

    -- the pairs
    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS n,
           UPPER(REPLACE(LTRIM(RTRIM(LEFT(p.[value], CHARINDEX(N'=', p.[value]) - 1))), N' ', N'_')) AS Name,
           LTRIM(RTRIM(SUBSTRING(p.[value], CHARINDEX(N'=', p.[value]) + 1, 4000))) AS RawValue
    INTO #pairs
    FROM STRING_SPLIT(REPLACE(REPLACE(@Text, NCHAR(13), N','), NCHAR(10), N','), N',') p
    WHERE CHARINDEX(N'=', p.[value]) > 1;
    -- the leading number of the value text, if any
    ALTER TABLE #pairs ADD Number DECIMAL(28,10) NULL;
    UPDATE #pairs SET Number = TRY_CONVERT(DECIMAL(28,10), LEFT(RawValue, ISNULL(NULLIF(PATINDEX(N'%[^0-9.+-]%', RawValue + N' '), 0) - 1, LEN(RawValue))));

    SELECT p.n, p.Name, p.RawValue, p.Number, sd.[RowId] AS DefRowId, sd.[DataType], sd.[MinValue], sd.[MaxValue]
    INTO #m
    FROM #pairs p LEFT JOIN [config].[SettingDefinition] sd ON sd.[DefinitionVersionRowId] = @tver AND sd.[IsDeleted] = 0 AND UPPER(sd.[SettingCode]) = p.Name;

    BEGIN TRANSACTION;
    DECLARE @n INT, @def UNIQUEIDENTIFIER, @dt NVARCHAR(20), @num DECIMAL(28,10), @raw NVARCHAR(4000), @min DECIMAL(28,10), @max DECIMAL(28,10);
    -- W8 (#153): a legacy text can name a setting twice (11 of 949 migrated SEL files repeat a name, e.g. 50N2P); the first
    -- occurrence is the value, the repeat is noted — a second row would break UX_ParsedSetting_Current and lose the whole file
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT n, DefRowId, DataType, Number, RawValue, MinValue, MaxValue FROM #m m
        WHERE DefRowId IS NOT NULL AND n = (SELECT MIN(x.n) FROM #m x WHERE x.DefRowId = m.DefRowId) ORDER BY n;
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
        IF @dt IN (N'Decimal', N'Integer') AND @num IS NOT NULL
            EXEC [document].[ParsedSetting_Add] @ConfigurationFileRevisionRowId = @ConfigurationFileRevisionRowId, @SettingDefinitionRowId = @def, @DecimalValue = @num, @RangeCheck = @rc, @RangeCheckNote = @note, @ActorId = @ActorId;
        ELSE
            EXEC [document].[ParsedSetting_Add] @ConfigurationFileRevisionRowId = @ConfigurationFileRevisionRowId, @SettingDefinitionRowId = @def, @TextValue = @raw, @RangeCheck = N'NotChecked', @ActorId = @ActorId;
        FETCH NEXT FROM c INTO @n, @def, @dt, @num, @raw, @min, @max;
    END
    CLOSE c; DEALLOCATE c;
    SET @Matched = (SELECT COUNT(*) FROM #m WHERE DefRowId IS NOT NULL);
    SET @Unmatched = (SELECT COUNT(*) FROM #m WHERE DefRowId IS NULL);
    DECLARE @status NVARCHAR(20) = CASE WHEN @Matched = 0 AND @Unmatched = 0 THEN N'Empty' WHEN @Unmatched = 0 THEN N'Parsed' ELSE N'Partial' END;
    DECLARE @err NVARCHAR(MAX) = CASE WHEN @Unmatched = 0 THEN NULL ELSE N'not in the template: ' + (SELECT STRING_AGG(Name, N', ') FROM #m WHERE DefRowId IS NULL) END;
    DECLARE @dups NVARCHAR(MAX) = (SELECT STRING_AGG(Name, N', ') FROM (SELECT Name FROM #m WHERE DefRowId IS NOT NULL GROUP BY Name HAVING COUNT(*) > 1) d);
    IF @dups IS NOT NULL SET @err = CONCAT(ISNULL(@err + N'; ', N''), N'repeated in the text (first value kept): ', @dups);
    UPDATE [document].[ConfigurationFile] SET [ParseStatus] = @status, [ParseError] = @err, [ModifiedBy] = @ActorId, [ModifiedAt] = @now
    WHERE [RevisionRowId] = @ConfigurationFileRevisionRowId AND [IsDeleted] = 0;
    COMMIT TRANSACTION;
END;
GO
