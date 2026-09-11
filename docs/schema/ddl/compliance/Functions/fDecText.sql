-- FORMULA-GRAMMAR.md §4.4. The grammar's canonical decimal text: trailing zeros trimmed, never exponent
-- notation, so the same number always reads the same way. Deterministic.
--
-- It outlived the evaluator it was written for. When compliance.fEvalNode and its unit helpers were
-- dropped on 2026-09-10 this went with them, and the schema project's static analysis refused the build:
-- compliance.fTypedValue still needs it to shape a numeric fact read. Formatting a number is not
-- evaluating an expression, and fTypedValue belongs with fFactRead, which stays in the database.
CREATE FUNCTION [compliance].[fDecText] (@v DECIMAL(28,10))
RETURNS NVARCHAR(60)
AS
BEGIN
    IF @v IS NULL RETURN NULL;
    DECLARE @s NVARCHAR(60) = CONVERT(NVARCHAR(60), @v);
    IF CHARINDEX(N'.', @s) > 0
    BEGIN
        WHILE RIGHT(@s, 1) = N'0' SET @s = LEFT(@s, LEN(@s) - 1);
        IF RIGHT(@s, 1) = N'.' SET @s = LEFT(@s, LEN(@s) - 1);
    END
    IF @s IN (N'', N'-0') SET @s = N'0';
    RETURN @s;
END;
GO
