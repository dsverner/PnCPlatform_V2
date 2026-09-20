-- #208 (2026-09-20): every source membership feeds an analog input. The sources that exist without one (the #206 rule's
-- migration-rule: #208 every scheme source (CtSource / VtSource / SyncVtSource) without an analog input is given one — per scheme and role, the sources by distinct ratio in ratio order become "Current 1..n", "Voltage 1..n", "Sync voltage 1..n" (the same ratio shares the input: paralleled); a rule-made source left on an input with sources of another ratio is moved to its own; idempotent
-- sets, the hand-made ones, the smoke's) are given one here, on every deploy, idempotently: per scheme and role, the sources
-- by distinct ratio in ratio order → "Current 1..n", "Voltage 1..n", "Sync voltage 1..n" (sources of the same ratio share
-- the input — that is the paralleled case, which the legacy strings cannot tell apart and the #206 dedupe already merged;
-- a different ratio is a different input: an auxiliary PT is not paralleled with the main set). A source with no ratio gets
-- an input of its own. A source the #206 rule made (asset.AlternateKey kind MigrationSource) that stands on an input with
-- sources of another ratio — the first run put every VT source on one "Voltage" — is detached first and regrouped; a
-- source a person named is never moved. scheme.AddSchemeMember does the same find-or-make for every source named from now
-- on, so this seed is the catch-up for what came before.
IF OBJECT_ID(N'[scheme].[AnalogInput_Add]') IS NULL OR COL_LENGTH(N'[scheme].[SchemeMember]', N'AnalogInputEntityId') IS NULL RETURN;   -- the deploy that made the table; its procedures come with the next
GO
SET NOCOUNT ON;
DECLARE @sys UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';

-- 0a. the first run's unnumbered codes take their number (idempotent)
UPDATE [scheme].[AnalogInput] SET [InputCode] = [InputCode] + N' 1', [ModifiedBy] = @sys, [ModifiedAt] = SYSDATETIMEOFFSET()
WHERE [InputCode] IN (N'Voltage', N'Sync voltage') AND [ValidTo] IS NULL AND [IsDeleted] = 0
  AND NOT EXISTS (SELECT 1 FROM [scheme].[AnalogInput] o WHERE o.[SchemeEntityId] = [scheme].[AnalogInput].[SchemeEntityId] AND o.[InputCode] = [scheme].[AnalogInput].[InputCode] + N' 1' AND o.[ValidTo] IS NULL AND o.[IsDeleted] = 0);
-- 0b. a rule-made source on an input whose sources carry more than one ratio number, and whose ratio is not the input's
--     lowest, is detached to be regrouped below (the lowest-ratio sources keep the input, so "Voltage 1" keeps its main set)
UPDATE sm SET [AnalogInputEntityId] = NULL, [ModifiedBy] = @sys, [ModifiedAt] = SYSDATETIMEOFFSET()
FROM [scheme].[SchemeMember] sm
JOIN [scheme].[vSchemeSource] src ON src.[MemberEntityId] = sm.[EntityId]
JOIN [scheme].[vSchemeInput] si ON si.[EntityId] = src.[AnalogInputEntityId] AND si.[DistinctRatios] > 1
CROSS APPLY (SELECT MIN(o.[Ratio]) AS [Lowest] FROM [scheme].[vSchemeSource] o WHERE o.[AnalogInputEntityId] = si.[EntityId]) lo
WHERE sm.[ValidTo] IS NULL AND sm.[IsDeleted] = 0
  AND (src.[Ratio] IS NULL OR src.[Ratio] <> lo.[Lowest])
  AND EXISTS (SELECT 1 FROM [asset].[AlternateKey] k WHERE k.[SubjectEntityId] = src.[AssetEntityId] AND k.[KeyKindCode] = N'MigrationSource' AND k.[IsDeleted] = 0);
DECLARE @detached INT = @@ROWCOUNT;

-- the sources with no input, with their ratio number (scheme.vSchemeSource reads it)
SELECT src.[SchemeEntityId], src.[MemberEntityId], src.[MemberRoleCode], src.[Ratio], src.[AssetName]
INTO #orphan
FROM [scheme].[vSchemeSource] src
WHERE src.[AnalogInputEntityId] IS NULL;

-- the input each will feed
SELECT o.[SchemeEntityId], o.[MemberEntityId], o.[MemberRoleCode],
       [InputKind] = CASE o.[MemberRoleCode] WHEN N'CtSource' THEN N'Current' WHEN N'VtSource' THEN N'Voltage' ELSE N'SyncVoltage' END,
       [InputCode] = CASE o.[MemberRoleCode] WHEN N'CtSource' THEN N'Current ' WHEN N'VtSource' THEN N'Voltage ' ELSE N'Sync voltage ' END
                     + CONVERT(NVARCHAR(4), taken.[N] + DENSE_RANK() OVER (PARTITION BY o.[SchemeEntityId], o.[MemberRoleCode] ORDER BY ISNULL(o.[Ratio], 999999999), CASE WHEN o.[Ratio] IS NULL THEN o.[MemberEntityId] ELSE '00000000-0000-0000-0000-000000000000' END))
INTO #plan
FROM #orphan o
-- numbering continues after the inputs the scheme already has of that kind (an existing "Current 1" stays; new ones are 2, 3 ...)
CROSS APPLY (SELECT COUNT(*) AS [N] FROM [scheme].[AnalogInput] ai WHERE ai.[SchemeEntityId] = o.[SchemeEntityId] AND ai.[ValidTo] IS NULL AND ai.[IsDeleted] = 0
             AND ai.[InputKind] = CASE o.[MemberRoleCode] WHEN N'CtSource' THEN N'Current' WHEN N'VtSource' THEN N'Voltage' ELSE N'SyncVoltage' END) taken;

-- current inputs the scheme already has with the same code are reused; the rest are made
DECLARE @scheme UNIQUEIDENTIFIER, @code NVARCHAR(40), @kind NVARCHAR(20), @input UNIQUEIDENTIFIER, @made INT = 0, @assigned INT = 0;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT [SchemeEntityId], [InputCode], [InputKind] FROM #plan;
OPEN c; FETCH NEXT FROM c INTO @scheme, @code, @kind;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @input = NULL;
    SELECT @input = [EntityId] FROM [scheme].[AnalogInput] WHERE [SchemeEntityId] = @scheme AND [InputCode] = @code AND [ValidTo] IS NULL AND [IsDeleted] = 0;
    IF @input IS NULL
    BEGIN
        EXEC [scheme].[AnalogInput_Add] @SchemeEntityId = @scheme, @InputCode = @code, @InputKind = @kind, @ActorId = @sys, @EntityId = @input OUTPUT;
        SET @made += 1;
    END
    UPDATE sm SET [AnalogInputEntityId] = @input, [ModifiedBy] = @sys, [ModifiedAt] = SYSDATETIMEOFFSET()
    FROM [scheme].[SchemeMember] sm
    JOIN #plan p ON p.[MemberEntityId] = sm.[EntityId] AND p.[SchemeEntityId] = @scheme AND p.[InputCode] = @code
    WHERE sm.[ValidTo] IS NULL AND sm.[IsDeleted] = 0 AND sm.[AnalogInputEntityId] IS NULL;
    SET @assigned += @@ROWCOUNT;
    FETCH NEXT FROM c INTO @scheme, @code, @kind;
END
CLOSE c; DEALLOCATE c;
DECLARE @report NVARCHAR(400) = N'#208: analog inputs made ' + CONVERT(NVARCHAR(10), @made) + N', sources given an input ' + CONVERT(NVARCHAR(10), @assigned) + N', rule-made sources regrouped off a mixed-ratio input ' + CONVERT(NVARCHAR(10), @detached);
PRINT @report;
DROP TABLE #orphan; DROP TABLE #plan;
GO
