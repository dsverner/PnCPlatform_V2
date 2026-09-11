-- SCHEMA-DESIGN §12.3. One characteristic fact for an asset subject, as text, through the catalogue's key.
-- Matches by (template definition entity, characteristic key) across template versions, so a value
-- entered under version 1 remains addressable after version 2 becomes effective (SCHEMA-DESIGN §2.10
-- open item, raised by the gate).
CREATE FUNCTION [compliance].[fCharacteristicFactValue]
    (@subjectEntityId UNIQUEIDENTIFIER, @definitionEntityId UNIQUEIDENTIFIER, @key NVARCHAR(100), @at DATETIMEOFFSET(7))
RETURNS NVARCHAR(400)
AS
BEGIN
    DECLARE @v NVARCHAR(400);
    SELECT TOP (1) @v = COALESCE(
            cv.[TextValue],
            CONVERT(NVARCHAR(400), cv.[IntegerValue]),
            CONVERT(NVARCHAR(400), cv.[DecimalValue]),
            CASE cv.[BooleanValue] WHEN 1 THEN N'true' WHEN 0 THEN N'false' END,
            CONVERT(NVARCHAR(400), cv.[DateTimeValue], 127),
            CONVERT(NVARCHAR(400), cv.[ReferenceEntityId]))
    FROM [asset].[CharacteristicValue] cv
    JOIN [config].[CharacteristicDefinition] cd ON cd.[RowId] = cv.[CharacteristicDefinitionRowId] AND cd.[IsDeleted] = 0
    JOIN [config].[DefinitionVersion] dv ON dv.[RowId] = cd.[DefinitionVersionRowId] AND dv.[IsDeleted] = 0
    WHERE cv.[HostEntityId] = @subjectEntityId AND cv.[IsDeleted] = 0
      AND cv.[ValidFrom] <= @at AND (cv.[ValidTo] IS NULL OR cv.[ValidTo] > @at)
      AND dv.[DefinitionEntityId] = @definitionEntityId AND cd.[CharacteristicKey] = @key
    ORDER BY cv.[ValidFrom] DESC, cv.[RowSeq] DESC;
    RETURN @v;
END;
GO
