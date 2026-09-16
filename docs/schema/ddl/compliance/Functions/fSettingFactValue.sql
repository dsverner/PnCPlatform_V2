-- SCHEMA-DESIGN §12.3, §8.3, §7.5 (121). A device.settings.<code> fact: the parsed value of that setting on
-- the device's in-service settings file (native or text, #168) at @at. The settings group read is the ActiveSettingsGroup
-- condition on the device at @at (decision 121); if none, the global (null-group) value; else the lowest
-- group present. The setting definition is matched by code under the transform definition entity across
-- its versions, as characteristics are.
CREATE FUNCTION [compliance].[fSettingFactValue]
    (@subjectEntityId UNIQUEIDENTIFIER, @transformDefinitionEntityId UNIQUEIDENTIFIER, @settingCode NVARCHAR(100), @at DATETIMEOFFSET(7))
RETURNS NVARCHAR(400)
AS
BEGIN
    DECLARE @v NVARCHAR(400);
    DECLARE @group TINYINT = (
        SELECT TOP (1) TRY_CONVERT(TINYINT, pc.[ConditionValue]) FROM [scheme].[ProtectionCondition] pc
        WHERE pc.[SubjectKind] = N'Device' AND pc.[SubjectEntityId] = @subjectEntityId AND pc.[ConditionKindCode] = N'ActiveSettingsGroup'
          AND pc.[IsDeleted] = 0 AND pc.[ValidFrom] <= @at AND (pc.[ValidTo] IS NULL OR pc.[ValidTo] > @at)
        ORDER BY pc.[ValidFrom] DESC, pc.[RowSeq] DESC);
    SELECT TOP (1) @v = COALESCE(
            ps.[TextValue],
            CONVERT(NVARCHAR(400), ps.[IntegerValue]),
            CONVERT(NVARCHAR(400), ps.[DecimalValue]),
            CASE ps.[BooleanValue] WHEN 1 THEN N'true' WHEN 0 THEN N'false' END,
            CONVERT(NVARCHAR(400), ps.[DateTimeValue], 127),
            CONVERT(NVARCHAR(400), ps.[ReferenceEntityId]))
    FROM [document].[ConfigurationFile] cf
    JOIN [document].[ParsedSetting] ps ON ps.[ConfigurationFileRevisionRowId] = cf.[RevisionRowId] AND ps.[IsDeleted] = 0
        AND ps.[ValidFrom] <= @at AND (ps.[ValidTo] IS NULL OR ps.[ValidTo] > @at)
    JOIN [config].[SettingDefinition] sd ON sd.[RowId] = ps.[SettingDefinitionRowId] AND sd.[IsDeleted] = 0
    JOIN [config].[DefinitionVersion] dv ON dv.[RowId] = sd.[DefinitionVersionRowId] AND dv.[IsDeleted] = 0
    WHERE cf.[DeviceEntityId] = @subjectEntityId AND cf.[FileKind] IN (N'NativeSettings', N'SettingsText') AND cf.[IsDeleted] = 0   -- #168: a parsed text file is a settings file too
      AND cf.[InServiceFrom] IS NOT NULL AND cf.[InServiceFrom] <= @at AND (cf.[InServiceTo] IS NULL OR cf.[InServiceTo] > @at)
      AND dv.[DefinitionEntityId] = @transformDefinitionEntityId AND sd.[SettingCode] = @settingCode
      AND (ps.[GroupNumber] IS NULL OR @group IS NULL OR ps.[GroupNumber] = @group)
    ORDER BY CASE WHEN ps.[GroupNumber] = @group THEN 0 WHEN ps.[GroupNumber] IS NULL THEN 1 ELSE 2 END, ps.[GroupNumber], ps.[ValidFrom] DESC, ps.[RowSeq] DESC;
    RETURN @v;
END;
GO
