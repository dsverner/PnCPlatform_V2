-- #192 (2026-09-18): what changed in the basis since this draft was taken from it — the owner's caveat: "if the data for
-- the first changed ... the second work request would get flagged of the change". Three values per setting:
--   Then  the basis as frozen when the draft was taken (the newest basis-<n>.json on this revision — process.WriteBasisSnapshot)
--   Now   the basis's current parsed rows (process.fBasisRevision: the linked draft, or the in-service revision if withdrawn)
--   Mine  this draft's current parsed rows
-- Outcome: take (the basis moved, mine did not — theirs applies), agree (both moved to the same value), conflict (all
-- three differ — the engineer decides), mine (only mine moved — not drift). A draft based before this increment has no
-- frozen basis: every Now<>Mine row is a conflict with Then NULL, so it is re-based on first sight (#191). Settings that
-- are the same in all three are not returned.
CREATE FUNCTION [process].[fBasisDrift] (@RevisionRowId UNIQUEIDENTIFIER)
RETURNS @out TABLE ([SettingCode] NVARCHAR(40), [GroupNumber] INT, [SettingName] NVARCHAR(200), [ThenValue] NVARCHAR(400), [NowValue] NVARCHAR(400), [MineValue] NVARCHAR(400), [Outcome] NVARCHAR(10))
AS
BEGIN
    DECLARE @basis UNIQUEIDENTIFIER = [process].[fBasisRevision](@RevisionRowId);
    IF @basis IS NULL RETURN;
    DECLARE @json NVARCHAR(MAX) = (SELECT TOP (1) CONVERT(NVARCHAR(MAX), CONVERT(VARCHAR(MAX), fs.[file_stream]))
                                   FROM [document].[vFile] f JOIN [document].[FileStore] fs ON fs.[stream_id] = f.[FileStreamId]
                                   WHERE f.[RevisionRowId] = @RevisionRowId AND f.[FileRole] = N'Attachment' AND f.[FileName] LIKE N'basis-%.json' ORDER BY f.[RowSeq] DESC);
    ;WITH thenRows AS (SELECT JSON_VALUE(j.[value], '$.c') AS c, ISNULL(TRY_CONVERT(INT, JSON_VALUE(j.[value], '$.g')), 1) AS g, JSON_VALUE(j.[value], '$.v') AS v FROM OPENJSON(@json) j),
          nowRows AS (SELECT [SettingCode] AS c, ISNULL([GroupNumber], 1) AS g, [RawValue] AS v, [SettingName] AS n FROM [document].[vParsedSettingNamed] WHERE [ConfigurationFileRevisionRowId] = @basis),
          mineRows AS (SELECT [SettingCode] AS c, ISNULL([GroupNumber], 1) AS g, [RawValue] AS v, [SettingName] AS n FROM [document].[vParsedSettingNamed] WHERE [ConfigurationFileRevisionRowId] = @RevisionRowId),
          keys AS (SELECT c, g FROM thenRows UNION SELECT c, g FROM nowRows UNION SELECT c, g FROM mineRows)
    INSERT @out ([SettingCode], [GroupNumber], [SettingName], [ThenValue], [NowValue], [MineValue], [Outcome])
    SELECT k.c, k.g, COALESCE(m.n, w.n), t.v, w.v, m.v,
           CASE WHEN @json IS NULL THEN CASE WHEN ISNULL(w.v, N'') <> ISNULL(m.v, N'') THEN N'conflict' ELSE N'same' END
                WHEN ISNULL(w.v, N'') = ISNULL(t.v, N'') AND ISNULL(m.v, N'') = ISNULL(t.v, N'') THEN N'same'
                WHEN ISNULL(w.v, N'') = ISNULL(t.v, N'') THEN N'mine'
                WHEN ISNULL(m.v, N'') = ISNULL(t.v, N'') THEN N'take'
                WHEN ISNULL(m.v, N'') = ISNULL(w.v, N'') THEN N'agree'
                ELSE N'conflict' END
    FROM keys k
    LEFT JOIN thenRows t ON t.c = k.c AND t.g = k.g
    LEFT JOIN nowRows w ON w.c = k.c AND w.g = k.g
    LEFT JOIN mineRows m ON m.c = k.c AND m.g = k.g;
    DELETE FROM @out WHERE [Outcome] = N'same';
    RETURN;
END;
GO
