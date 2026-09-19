-- #197 (2026-09-19): is a commissioned function load-responsive in PRC-023-6's sense, and why.
--
-- PRC-023-6 applies to "load-responsive phase protection systems as described in Attachment A" (4.1). Attachment A 1 lists
-- the functions it includes (phase distance, out-of-step, switch-on-to-fault, overcurrent, comms-aided schemes); Attachment A 2
-- excludes, among others, "protection systems intended for the detection of ground fault conditions" (2.2). The ruling is
-- held on ref.AnsiFunction (LoadResponsive, LoadResponsiveBasis) for the C37.2 device numbers the core seed names.
--
-- A commissioned code is rarely a bare device number: the legacy import left 800-odd strings such as 21-B, 87T, 50/51N-A,
-- 85TY-1 (one per position, from the FUNCTIONS text). This function reads such a string as the numbers it is built from:
-- each '/'-separated part takes the LONGEST ruled code that starts it (50BF-A -> 50BF, 51N -> 51N, 21-B -> 21), else its
-- leading digits (62B -> 62, which nobody has ruled); the code is GROUND when N or G follows the digits of any part
-- (50/51N: both the 50 and the 51 are neutral elements). The code is load-responsive when a part's number is ruled so and
-- the code is not ground; not load-responsive when every part is ruled and none qualifies; NULL (not ruled) otherwise —
-- the evaluator then reports the device undetermined rather than declaring the standard inapplicable.
--
-- The normalisation of the legacy strings themselves is a coming migration rule; nothing here rewrites them.
CREATE FUNCTION [ref].[fAnsiLoadResponsive] (@code NVARCHAR(10))
RETURNS TABLE
AS
RETURN
WITH parts AS (
    SELECT LTRIM(RTRIM([value])) AS [Part] FROM STRING_SPLIT(ISNULL(@code, N''), N'/')
),
based AS (
    SELECT p.[Part],
           (SELECT TOP (1) a.[AnsiCode] FROM [ref].[AnsiFunction] a
             WHERE a.[LoadResponsive] IS NOT NULL AND LEFT(p.[Part], LEN(a.[AnsiCode])) = a.[AnsiCode]
             ORDER BY LEN(a.[AnsiCode]) DESC) AS [Ruled],
           NULLIF(LEFT(p.[Part], PATINDEX(N'%[^0-9]%', p.[Part] + N'x') - 1), N'') AS [Digits],
           CASE WHEN SUBSTRING(p.[Part], PATINDEX(N'%[^0-9]%', p.[Part] + N'x'), 1) IN (N'N', N'G') THEN 1 ELSE 0 END AS [PartGround]
    FROM parts p
),
judged AS (
    SELECT b.[Part], ISNULL(b.[Ruled], b.[Digits]) AS [BaseCode], b.[PartGround], a.[LoadResponsive], a.[LoadResponsiveBasis]
    FROM based b LEFT JOIN [ref].[AnsiFunction] a ON a.[AnsiCode] = ISNULL(b.[Ruled], b.[Digits])
),
whole AS (
    SELECT MAX(j.[PartGround]) AS [IsGround],
           MAX(CONVERT(INT, j.[LoadResponsive])) AS [AnyYes],
           COUNT(*) AS [Parts], COUNT(j.[LoadResponsive]) AS [RuledParts],
           STRING_AGG(j.[BaseCode], N', ') WITHIN GROUP (ORDER BY j.[Part]) AS [BaseCodes]
    FROM judged j
)
SELECT w.[BaseCodes],
       w.[IsGround],
       CASE WHEN w.[AnyYes] = 1 AND w.[IsGround] = 0 THEN CONVERT(BIT, 1)
            WHEN w.[AnyYes] = 1 AND w.[IsGround] = 1 THEN CONVERT(BIT, 0)
            WHEN w.[RuledParts] = w.[Parts] THEN CONVERT(BIT, 0)
            ELSE CONVERT(BIT, NULL) END AS [LoadResponsive],
       CASE WHEN w.[AnyYes] = 1 AND w.[IsGround] = 1 THEN N'ground fault detection (PRC-023-6 Attachment A 2.2)'
            WHEN w.[AnyYes] = 1 THEN (SELECT TOP (1) j.[LoadResponsiveBasis] FROM judged j WHERE j.[LoadResponsive] = 1 ORDER BY j.[Part])
            WHEN w.[RuledParts] = w.[Parts] THEN (SELECT TOP (1) j.[LoadResponsiveBasis] FROM judged j ORDER BY j.[Part])
            ELSE N'not yet ruled load-responsive or not (' + ISNULL((SELECT TOP (1) j.[Part] FROM judged j WHERE j.[LoadResponsive] IS NULL ORDER BY j.[Part]), N'?') + N')' END AS [LoadResponsiveBasis]
FROM whole w;
GO
GRANT SELECT ON [ref].[fAnsiLoadResponsive] TO [app_execute];
GO
