-- SCHEMA-DESIGN §12.3. Every fact name a program payload references, at any depth of the JSON tree.
CREATE FUNCTION [compliance].[fPayloadFactNames] (@json NVARCHAR(MAX))
RETURNS TABLE
AS
RETURN
    WITH nodes AS (
        SELECT CAST(@json AS NVARCHAR(MAX)) AS j
        UNION ALL
        SELECT CAST(o.[value] AS NVARCHAR(MAX))
        FROM nodes CROSS APPLY OPENJSON(nodes.j) o
        WHERE o.[type] IN (4, 5)
    )
    SELECT DISTINCT [FactName] = JSON_VALUE(j, '$.fact') FROM nodes WHERE JSON_VALUE(j, '$.fact') IS NOT NULL;
GO
