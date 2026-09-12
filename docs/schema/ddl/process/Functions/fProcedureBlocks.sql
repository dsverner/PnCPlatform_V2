-- PROCEDURE-ENGINE §3, §8 (W3). The block tree of a canonical procedure document as rows, depth-first in document
-- order. One row per block and per parallel branch. Used by process.ValidateProcedureDocument and
-- process.ProjectProcedureVersion so both walk the tree the same way.
--   BlockPath  ids from the root joined by '/', branches included, choice cases adding no segment
--   ScopePath  the nearest enclosing foreach body or parallel branch (null at the root) — the "branch" that a
--              branchOutcome can end (§3, the C1 check)
--   SortKey    zero-padded ordinals, so ORDER BY SortKey is document order
CREATE FUNCTION [process].[fProcedureBlocks] (@Canonical NVARCHAR(MAX))
RETURNS TABLE
AS
RETURN
    WITH tree AS (
        SELECT CAST(JSON_QUERY(@Canonical, '$.body') AS NVARCHAR(MAX)) AS j,
               CAST(JSON_VALUE(@Canonical, '$.body.block') AS NVARCHAR(20)) AS Kind,
               CAST(JSON_VALUE(@Canonical, '$.body.id') AS NVARCHAR(64)) AS BlockId,
               CAST(JSON_VALUE(@Canonical, '$.body.id') AS NVARCHAR(400)) AS BlockPath,
               CAST(NULL AS NVARCHAR(400)) AS ParentPath,
               CAST(NULL AS NVARCHAR(400)) AS ScopePath,
               CAST(N'000' AS NVARCHAR(400)) AS SortKey,
               0 AS Depth
        WHERE JSON_QUERY(@Canonical, '$.body') IS NOT NULL
        UNION ALL
        SELECT CAST(c.child AS NVARCHAR(MAX)),
               CAST(c.kind AS NVARCHAR(20)),
               CAST(c.id AS NVARCHAR(64)),
               CAST(t.BlockPath + CASE WHEN c.id IS NULL THEN N'' ELSE N'/' + c.id END AS NVARCHAR(400)),
               t.BlockPath,
               CAST(CASE WHEN c.opens_scope = 1 THEN t.BlockPath + CASE WHEN c.id IS NULL THEN N'' ELSE N'/' + c.id END ELSE t.ScopePath END AS NVARCHAR(400)),
               CAST(t.SortKey + N'.' + RIGHT(N'000' + CAST(c.ord AS NVARCHAR(10)), 3) AS NVARCHAR(400)),
               t.Depth + 1
        FROM tree t
        CROSS APPLY (
            -- sequence: items in order
            SELECT CAST(o.[key] AS INT) AS ord, o.[value] AS child, JSON_VALUE(o.[value], '$.block') AS kind, JSON_VALUE(o.[value], '$.id') AS id, 0 AS opens_scope
            FROM OPENJSON(t.j, '$.items') o WHERE t.Kind = N'sequence'
            UNION ALL
            -- parallel: each branch is a node of kind 'branch' (its own id), opening a scope
            SELECT CAST(o.[key] AS INT), o.[value], N'branch', JSON_VALUE(o.[value], '$.id'), 1
            FROM OPENJSON(t.j, '$.branches') o WHERE t.Kind = N'parallel'
            UNION ALL
            -- a branch's body
            SELECT 0, JSON_QUERY(t.j, '$.body'), JSON_VALUE(t.j, '$.body.block'), JSON_VALUE(t.j, '$.body.id'), 0
            WHERE t.Kind = N'branch'
            UNION ALL
            -- choice: each case's body (the case itself adds no path segment), then else
            SELECT CAST(o.[key] AS INT), JSON_QUERY(o.[value], '$.body'), JSON_VALUE(o.[value], '$.body.block'), JSON_VALUE(o.[value], '$.body.id'), 0
            FROM OPENJSON(t.j, '$.cases') o WHERE t.Kind = N'choice'
            UNION ALL
            SELECT 999, JSON_QUERY(t.j, '$.else'), JSON_VALUE(t.j, '$.else.block'), JSON_VALUE(t.j, '$.else.id'), 0
            WHERE t.Kind = N'choice' AND JSON_QUERY(t.j, '$.else') IS NOT NULL
            UNION ALL
            -- foreach (opens a scope: the member) and repeat: one body
            SELECT 0, JSON_QUERY(t.j, '$.body'), JSON_VALUE(t.j, '$.body.block'), JSON_VALUE(t.j, '$.body.id'), CASE WHEN t.Kind = N'foreach' THEN 1 ELSE 0 END
            WHERE t.Kind IN (N'foreach', N'repeat')
        ) c
        WHERE t.Depth < 64
    )
    SELECT j AS BlockJson, Kind, BlockId, BlockPath, ParentPath, ScopePath, SortKey, Depth FROM tree;
GO
