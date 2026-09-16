-- #168 (2026-09-16): the text writer — the other half of the settings template (Transform.SettingsParse reads, this
-- writes). A revision's parsed settings printed as the name=value list the relay and the group use: the template's
-- rows in DisplayOrder (the vendor's SET order) as "CODE=value" joined by ", " on one line, then the logic masks
-- (Format mask3) after ", LOGIC SETTINGS: " on the same line — the legacy overflow field's own form and marker, which
-- ParseSettingsText treats as a separator, so a rendered file re-parses to the same rows and renders again to the same
-- bytes (the round-trip rule, owner 2026-09-16). A value prints as its RawValue (exactly as filed or entered); a value
-- with no raw text (a computed or migrated one) prints by the definition's Format: decimal:N (fixed N decimals),
-- integer, text; a setting the revision does not carry is left out (the relay keeps its own value for it).
-- No settings group handling yet (GroupNumber NULL only, as ParseSettingsText writes).
CREATE PROCEDURE [process].[RenderSettingsText]
    @ConfigurationFileRevisionRowId UNIQUEIDENTIFIER,
    @Text NVARCHAR(MAX) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [document].[ConfigurationFile] WHERE [RevisionRowId] = @ConfigurationFileRevisionRowId AND [IsDeleted] = 0)
        THROW 50180, N'process.RenderSettingsText: the revision is not a device configuration file.', 1;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    SELECT sd.[SettingCode], sd.[DisplayOrder], sd.[Format],
           [Value] = COALESCE(ps.[RawValue],
                              CASE WHEN sd.[Format] LIKE N'decimal:%' AND ps.[DecimalValue] IS NOT NULL
                                   THEN FORMAT(ps.[DecimalValue], N'0.' + REPLICATE(N'0', TRY_CONVERT(INT, SUBSTRING(sd.[Format], 9, 2))), N'en-US')
                                   WHEN ps.[DecimalValue] IS NOT NULL THEN [compliance].[fDecText](ps.[DecimalValue])
                                   WHEN ps.[IntegerValue] IS NOT NULL THEN CONVERT(NVARCHAR(40), ps.[IntegerValue])
                                   WHEN ps.[BooleanValue] IS NOT NULL THEN CASE ps.[BooleanValue] WHEN 1 THEN N'Y' ELSE N'N' END
                                   ELSE ps.[TextValue] END)
    INTO #v
    FROM [document].[ParsedSetting] ps
    JOIN [config].[SettingDefinition] sd ON sd.[RowId] = ps.[SettingDefinitionRowId] AND sd.[IsDeleted] = 0
    WHERE ps.[ConfigurationFileRevisionRowId] = @ConfigurationFileRevisionRowId AND ps.[IsDeleted] = 0
      AND ps.[ValidFrom] <= @now AND (ps.[ValidTo] IS NULL OR ps.[ValidTo] > @now) AND ps.[GroupNumber] IS NULL;
    DECLARE @main NVARCHAR(MAX) = (SELECT STRING_AGG(CONCAT([SettingCode], N'=', [Value]), N', ') WITHIN GROUP (ORDER BY [DisplayOrder], [SettingCode]) FROM #v WHERE ISNULL([Format], N'') <> N'mask3' AND [Value] IS NOT NULL);
    DECLARE @masks NVARCHAR(MAX) = (SELECT STRING_AGG(CONCAT([SettingCode], N'=', [Value]), N', ') WITHIN GROUP (ORDER BY [DisplayOrder], [SettingCode]) FROM #v WHERE [Format] = N'mask3' AND [Value] IS NOT NULL);
    SET @Text = CONCAT(ISNULL(@main, N''), CASE WHEN @masks IS NULL THEN N'' ELSE CONCAT(CASE WHEN @main IS NULL THEN N'' ELSE N', ' END, N'LOGIC SETTINGS: ', @masks) END);
END;
GO
