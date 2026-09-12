-- PROCEDURE-ENGINE §7 (W3). Every expression a single block node carries, by site, without descending into child
-- blocks — so a fact use is attributed to the block that reads it (process.ProcedureFactUse). The sites are the
-- schema's expression properties: precondition, capture.<field>.validate, foreach.over, repeat.until, hold.until,
-- choice.cases[].when, parallel.branches[].applies, call.subject, call.bind.<name>, advances.subject.
CREATE FUNCTION [process].[fExpressionSites] (@BlockJson NVARCHAR(MAX))
RETURNS TABLE
AS
RETURN
    SELECT N'precondition' AS Site, JSON_QUERY(@BlockJson, '$.precondition') AS Expr WHERE JSON_QUERY(@BlockJson, '$.precondition') IS NOT NULL
    UNION ALL SELECT N'over',  JSON_QUERY(@BlockJson, '$.over')  WHERE JSON_QUERY(@BlockJson, '$.over')  IS NOT NULL
    UNION ALL SELECT N'until', JSON_QUERY(@BlockJson, '$.until') WHERE JSON_QUERY(@BlockJson, '$.until') IS NOT NULL
    UNION ALL SELECT N'subject', JSON_QUERY(@BlockJson, '$.subject') WHERE JSON_QUERY(@BlockJson, '$.subject') IS NOT NULL
    UNION ALL SELECT N'advances.subject', JSON_QUERY(@BlockJson, '$.advances.subject') WHERE JSON_QUERY(@BlockJson, '$.advances.subject') IS NOT NULL
    UNION ALL SELECT N'capture.' + f.[key] COLLATE DATABASE_DEFAULT + N'.validate', JSON_QUERY(f.[value], '$.validate')
              FROM OPENJSON(@BlockJson, '$.capture') f WHERE JSON_QUERY(f.[value], '$.validate') IS NOT NULL
    UNION ALL SELECT N'cases[' + c.[key] COLLATE DATABASE_DEFAULT + N'].when', JSON_QUERY(c.[value], '$.when')
              FROM OPENJSON(@BlockJson, '$.cases') c WHERE JSON_QUERY(c.[value], '$.when') IS NOT NULL
    UNION ALL SELECT N'branches[' + b.[key] COLLATE DATABASE_DEFAULT + N'].applies', JSON_QUERY(b.[value], '$.applies')
              FROM OPENJSON(@BlockJson, '$.branches') b WHERE JSON_QUERY(b.[value], '$.applies') IS NOT NULL
    UNION ALL SELECT N'bind.' + x.[key] COLLATE DATABASE_DEFAULT, x.[value]
              FROM OPENJSON(@BlockJson, '$.bind') x WHERE x.[type] = 5;
GO
