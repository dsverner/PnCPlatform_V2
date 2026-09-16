-- Hand-written read model (W6, decision #127). The setting display's rows: every parsed setting of a configuration-file
-- revision with its definition's name, category and unit, and one DisplayValue whatever the typed column. Carries the
-- device as DeviceEntityId so the read is scoped by the Asset family (the generated vParsedSetting has no subject column
-- and answers Global grants only). Permission ConfigurationFile.Read by the document.ParsedSetting prefix.
CREATE VIEW [document].[vParsedSettingNamed] AS
SELECT ps.[RowSeq],
       ps.[RowId],
       ps.[ConfigurationFileRevisionRowId],
       cf.[DeviceEntityId],
       sd.[SettingCode],
       sd.[Name]        AS [SettingName],
       sd.[Category],
       sd.[UnitCode],
       sd.[DataType],
       sd.[MinValue], sd.[MaxValue],
       sd.[AnsiCode],
       sd.[Description], sd.[DisplayOrder], sd.[Aliases], sd.[Format], sd.[EnumerationDefinitionRowId],   -- #168
       ps.[GroupNumber],
       ps.[TextValue], ps.[IntegerValue], ps.[DecimalValue], ps.[BooleanValue], ps.[DateTimeValue],
       [DisplayValue] = COALESCE(ps.[TextValue],
                                 CONVERT(NVARCHAR(50), ps.[DecimalValue]),
                                 CONVERT(NVARCHAR(50), ps.[IntegerValue]),
                                 CASE ps.[BooleanValue] WHEN 1 THEN N'true' WHEN 0 THEN N'false' END,
                                 CONVERT(NVARCHAR(40), ps.[DateTimeValue], 127)),
       ps.[RangeCheck], ps.[RangeCheckNote],
       ps.[RawValue]   -- #168: the value text as filed or entered
FROM [document].[vParsedSetting] ps
JOIN [document].[vConfigurationFile] cf ON cf.[RevisionRowId] = ps.[ConfigurationFileRevisionRowId]
LEFT JOIN [config].[vSettingDefinition] sd ON sd.[RowId] = ps.[SettingDefinitionRowId];
GO
GRANT SELECT ON [document].[vParsedSettingNamed] TO [app_execute];
GO
