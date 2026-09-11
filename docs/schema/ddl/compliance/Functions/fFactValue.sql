-- SCHEMA-DESIGN §12.3. A fact's value for a subject, by catalogue name, as text; NULL when the subject
-- has no value or the name is not catalogued. For reporting and for ObligationInstanceFact.ValueAsRead.
-- Reads the row and types it; it does not evaluate. A Formula-source fact is computed by the application's
-- evaluator (PnC.Formula) since 2026-09-10, so there is no Formula branch here any more and no recursion.
CREATE FUNCTION [compliance].[fFactValue]
    (@subjectEntityId UNIQUEIDENTIFIER, @factName NVARCHAR(200), @at DATETIMEOFFSET(7))
RETURNS NVARCHAR(400)
AS
BEGIN
    DECLARE @source NVARCHAR(20), @key NVARCHAR(200), @defEntity UNIQUEIDENTIFIER;
    SELECT TOP (1) @source = [FactSource], @key = [FactKey], @defEntity = [DefinitionEntityId]
    FROM [compliance].[vFactCatalogue] WHERE [FactName] = @factName;
    IF @source = N'Fixed'          RETURN [compliance].[fFixedFactValue](@subjectEntityId, @factName, @at);
    IF @source = N'Characteristic' RETURN [compliance].[fCharacteristicFactValue](@subjectEntityId, @defEntity, @key, @at);
    IF @source = N'Setting'        RETURN [compliance].[fSettingFactValue](@subjectEntityId, @defEntity, @key, @at);
    RETURN NULL;                   -- Formula and anything else: not this function's to compute
END;
GO
