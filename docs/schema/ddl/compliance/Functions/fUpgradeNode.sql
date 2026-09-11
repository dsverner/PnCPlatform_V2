-- FORMULA-GRAMMAR.md §9. Grammar 0 (the gate's predicate tree: {"fact","op","value"}, all/any/not, a rule's
-- "predicate") rewritten as grammar 1 on read. Idempotent on grammar 1. Mirrors formula.upgrade().
CREATE FUNCTION [compliance].[fUpgradeNode] (@json NVARCHAR(MAX))
RETURNS NVARCHAR(MAX)
AS
BEGIN
    IF @json IS NULL OR ISJSON(@json) <> 1 RETURN @json;
    IF JSON_VALUE(@json, '$.g') IS NOT NULL RETURN @json;

    -- a rule payload carrying the grammar-0 "predicate": becomes "scope"
    IF JSON_QUERY(@json, '$.predicate') IS NOT NULL
        RETURN JSON_MODIFY(JSON_MODIFY(JSON_MODIFY(@json, '$.g', 1), '$.scope', JSON_QUERY([compliance].[fUpgradeNode](JSON_QUERY(@json, '$.predicate')))), '$.predicate', NULL);

    DECLARE @list NVARCHAR(MAX), @n INT, @op NVARCHAR(10);
    IF JSON_QUERY(@json, '$.all') IS NOT NULL OR JSON_QUERY(@json, '$.any') IS NOT NULL
    BEGIN
        SET @op = CASE WHEN JSON_QUERY(@json, '$.all') IS NOT NULL THEN N'and' ELSE N'or' END;
        SELECT @list = STRING_AGG([compliance].[fUpgradeNode](j.[value]), N','), @n = COUNT(*)
        FROM OPENJSON(@json, CASE WHEN @op = N'and' THEN '$.all' ELSE '$.any' END) j;
        IF @n = 1 RETURN @list;
        RETURN CONCAT(N'{"op":"', @op, N'","a":[', @list, N']}');
    END
    IF JSON_QUERY(@json, '$.not') IS NOT NULL AND JSON_VALUE(@json, '$.op') IS NULL
        RETURN CONCAT(N'{"op":"not","x":', [compliance].[fUpgradeNode](JSON_QUERY(@json, '$.not')), N'}');

    -- a grammar-0 leaf: fact + op + value (grammar 1 leaves carry "l"/"r", never "fact" beside "op")
    DECLARE @fact NVARCHAR(200) = JSON_VALUE(@json, '$.fact');
    SET @op = JSON_VALUE(@json, '$.op');
    IF @fact IS NULL OR @op IS NULL RETURN @json;
    DECLARE @vtype INT = (SELECT [type] FROM OPENJSON(@json) WHERE [key] = N'value');
    DECLARE @lit NVARCHAR(MAX);
    IF @op = N'in'
    BEGIN
        SELECT @lit = N'{"set":[' + ISNULL(STRING_AGG(
            CASE v.[type] WHEN 1 THEN N'{"lit":"' + STRING_ESCAPE(v.[value], 'json') + N'","t":"text"}'
                          WHEN 2 THEN N'{"lit":"' + v.[value] + N'","t":"num"}'
                          WHEN 3 THEN N'{"lit":' + v.[value] + N',"t":"bool"}'
                          ELSE N'{"lit":null}' END, N','), N'') + N']}'
        FROM OPENJSON(@json, '$.value') v;
    END
    ELSE
        SET @lit = CASE @vtype WHEN 1 THEN N'{"lit":"' + STRING_ESCAPE(JSON_VALUE(@json, '$.value'), 'json') + N'","t":"text"}'
                               WHEN 2 THEN N'{"lit":"' + JSON_VALUE(@json, '$.value') + N'","t":"num"}'
                               WHEN 3 THEN N'{"lit":' + JSON_VALUE(@json, '$.value') + N',"t":"bool"}'
                               ELSE N'{"lit":null}' END;
    RETURN CONCAT(N'{"op":"', @op, N'","l":{"fact":"', STRING_ESCAPE(@fact, 'json'), N'"},"r":', @lit, N'}');
END;
GO
