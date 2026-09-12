-- PROCEDURE-ENGINE §2 (W3, decision #100). Structural checks on a canonical workflow document (workflow.schema.json):
--   50130 kind/key/states/transitions present    50131 state codes unique, exactly one initial
--   50132 every transition's from and to name a state
--   50133 onEnter.startProcedure and requires[].procedure name a Program.Procedure definition (any version; W4 pins)
CREATE PROCEDURE [process].[ValidateWorkflowDocument]
    @Canonical NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    IF ISJSON(@Canonical) <> 1 THROW 50130, N'Workflow document is not valid JSON.', 1;
    IF JSON_VALUE(@Canonical, '$.kind') <> N'workflow' OR JSON_VALUE(@Canonical, '$.key') IS NULL
       OR JSON_QUERY(@Canonical, '$.states') IS NULL OR JSON_QUERY(@Canonical, '$.transitions') IS NULL
        THROW 50130, N'Workflow document must carry kind "workflow", a key, states and transitions.', 1;

    DECLARE @msg NVARCHAR(MAX);
    SELECT JSON_VALUE(s.[value], '$.code') AS Code, s.[value] AS j INTO #s FROM OPENJSON(@Canonical, '$.states') s;

    SELECT @msg = STRING_AGG(Code, N', ') FROM (SELECT Code FROM #s GROUP BY Code HAVING COUNT(*) > 1) d;
    IF @msg IS NOT NULL BEGIN SET @msg = N'State codes must be unique: ' + @msg; THROW 50131, @msg, 1; END
    IF (SELECT COUNT(*) FROM #s WHERE JSON_VALUE(j, '$.initial') = 'true') <> 1
        THROW 50131, N'Exactly one state must be initial.', 1;

    SELECT @msg = STRING_AGG(JSON_VALUE(t.[value], '$.name') + N' (' + ISNULL(JSON_VALUE(t.[value], '$.from'), N'?') + N' → ' + ISNULL(JSON_VALUE(t.[value], '$.to'), N'?') + N')', N', ')
    FROM OPENJSON(@Canonical, '$.transitions') t
    WHERE NOT EXISTS (SELECT 1 FROM #s WHERE Code COLLATE DATABASE_DEFAULT = JSON_VALUE(t.[value], '$.from'))
       OR NOT EXISTS (SELECT 1 FROM #s WHERE Code COLLATE DATABASE_DEFAULT = JSON_VALUE(t.[value], '$.to'));
    IF @msg IS NOT NULL BEGIN SET @msg = N'Every transition must run between declared states: ' + @msg; THROW 50132, @msg, 1; END

    SELECT @msg = STRING_AGG(k, N', ')
    FROM (
        SELECT JSON_VALUE(e.[value], '$.startProcedure') AS k FROM #s CROSS APPLY OPENJSON(j, '$.onEnter') e WHERE JSON_VALUE(e.[value], '$.startProcedure') IS NOT NULL
        UNION ALL
        SELECT JSON_VALUE(r.[value], '$.procedure') FROM OPENJSON(@Canonical, '$.transitions') t CROSS APPLY OPENJSON(t.[value], '$.requires') r WHERE JSON_VALUE(r.[value], '$.procedure') IS NOT NULL
    ) p
    WHERE NOT EXISTS (SELECT 1 FROM [config].[Definition] d WHERE d.[IsDeleted] = 0 AND d.[DefinitionKind] = N'Program.Procedure' AND d.[DefinitionKey] = p.k);
    IF @msg IS NOT NULL BEGIN SET @msg = N'startProcedure and requires.procedure must name a Program.Procedure definition: ' + @msg; THROW 50133, @msg, 1; END
END;
GO
