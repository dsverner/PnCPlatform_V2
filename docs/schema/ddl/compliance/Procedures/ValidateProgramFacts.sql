-- SCHEMA-DESIGN §12.3 (163): the interpreter refuses a program that names a fact absent from the catalogue.
-- Called at authoring (config.AddDefinitionVersion, Program kinds) and again at run (RunRulePreview).
CREATE PROCEDURE [compliance].[ValidateProgramFacts] @PayloadText NVARCHAR(MAX), @DefinitionKind NVARCHAR(40) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF ISJSON(@PayloadText) <> 1 THROW 50110, N'Program payload is not valid JSON.', 1;
    -- FORMULA-GRAMMAR.md §8–§9: a stored payload is grammar 1 (canonical AST) or grammar 0 (upgraded on read)
    IF JSON_VALUE(@PayloadText, '$.g') IS NOT NULL AND JSON_VALUE(@PayloadText, '$.g') NOT IN (N'0', N'1')
        THROW 50112, N'Program payload grammar version is not supported (grammar_version).', 1;
    DECLARE @missing NVARCHAR(MAX);
    SELECT @missing = STRING_AGG(f.[FactName], N', ')
    FROM [compliance].[fPayloadFactNames](@PayloadText) f
    LEFT JOIN [compliance].[vFactCatalogue] c ON c.[FactName] = f.[FactName]
    WHERE c.[FactName] IS NULL
      AND f.[FactName] <> ISNULL(JSON_VALUE(@PayloadText, '$.publishes.fact'), N'')   -- #171: a formula's own published name (FORMULA-GRAMMAR §7 "publishes") is not a reference
      -- PROCEDURE-ENGINE §7 (W3): procedure.<name> and input.<name> are declared by the procedure document itself;
      -- process.ValidateProcedureDocument checks them against its produces and inputs
      AND NOT (@DefinitionKind = N'Program.Procedure' AND (f.[FactName] LIKE N'procedure.%' OR f.[FactName] LIKE N'input.%'));
    IF @missing IS NOT NULL
    BEGIN
        DECLARE @msg NVARCHAR(MAX) = N'Program references facts not in the catalogue: ' + @missing;
        THROW 50111, @msg, 1;
    END
    -- PROCEDURES.md #22: an obligation rule names the requirement it implements (§12.2), resolvable when authored
    IF @DefinitionKind = N'Program.ObligationRule' AND JSON_QUERY(@PayloadText, '$.requirement') IS NULL AND JSON_VALUE(@PayloadText, '$.requirement') IS NULL
        THROW 50113, N'An obligation rule must name its requirement ("requirement": entity id or {standard, version, number, sub}).', 1;
    IF @DefinitionKind = N'Program.ObligationRule' AND [compliance].[fResolveRequirement](@PayloadText) IS NULL
        THROW 50114, N'The obligation rule names a requirement that does not resolve to a compliance.Requirement.', 1;
END;
GO
