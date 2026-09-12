-- PROCEDURE-ENGINE §8 "Structural checks at save" (W3, decision #100: rules in SQL, grammar in C#). Refuses a
-- canonical procedure document that is well-formed JSON but structurally wrong, in the rule's own words (the API
-- answers 409 with the message). The expression grammar, types and the JSON Schema are the API's (PnC.Formula);
-- fact names are compliance.ValidateProgramFacts's. Checks, in order:
--   50120 kind/key/body present            50121 every block id unique
--   50122 every step names a role alias declared in $.roles, mapped to an active security.Role
--   50123 every step names an active ref.RecordKind (#42: every step produces a record)
--   50124 branchOutcome keys and advances.onOutcome are among the step's outcomes
--   50125 advances names an Effective Program.Workflow and one of its transitions
--   50126 call names a Program.Procedure definition (any version — W4's pinning requires an Effective one; Q1 of the W3 plan)
--   50127 due.anchor names an earlier step
--   50128 produces names are unique
--   50135 procedure.<name> names a produces.as of the document and input.<name> one of its inputs (procedure.outcome is the engine's)
--   50129 the C1 check: a step with a precondition inside a foreach member or parallel branch sits in a scope that
--         some step's branchOutcome can end; at the root the instance itself can be cancelled, so no check applies
CREATE PROCEDURE [process].[ValidateProcedureDocument]
    @Canonical NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    IF ISJSON(@Canonical) <> 1 THROW 50120, N'Procedure document is not valid JSON.', 1;
    IF JSON_VALUE(@Canonical, '$.kind') <> N'procedure' OR JSON_VALUE(@Canonical, '$.key') IS NULL OR JSON_QUERY(@Canonical, '$.body') IS NULL
        THROW 50120, N'Procedure document must carry kind "procedure", a key and a body.', 1;

    DECLARE @msg NVARCHAR(MAX);
    SELECT BlockJson, Kind, BlockId, BlockPath, ParentPath, ScopePath, SortKey, Depth,
           ROW_NUMBER() OVER (ORDER BY SortKey) AS Ordinal
    INTO #b FROM [process].[fProcedureBlocks](@Canonical);

    -- 50121 unique ids
    SELECT @msg = STRING_AGG(BlockId, N', ') FROM (SELECT BlockId FROM #b WHERE BlockId IS NOT NULL GROUP BY BlockId HAVING COUNT(*) > 1) d;
    IF @msg IS NOT NULL BEGIN SET @msg = N'Block ids must be unique within the document: ' + @msg; THROW 50121, @msg, 1; END
    IF EXISTS (SELECT 1 FROM #b WHERE BlockId IS NULL AND Kind NOT IN (N'branch', N'sequence'))
        THROW 50121, N'Every block but an inner sequence must carry an id.', 1;

    -- 50122 role aliases → active roles
    SELECT @msg = STRING_AGG(s.BlockId + N' (' + ISNULL(JSON_VALUE(s.BlockJson, '$.role'), N'no role') + N')', N', ')
    FROM #b s
    LEFT JOIN OPENJSON(@Canonical, '$.roles') r ON r.[key] COLLATE DATABASE_DEFAULT = JSON_VALUE(s.BlockJson, '$.role')
    WHERE s.Kind = N'step' AND r.[key] IS NULL;
    IF @msg IS NOT NULL BEGIN SET @msg = N'Every step must name a role alias declared in roles: ' + @msg; THROW 50122, @msg, 1; END
    SELECT @msg = STRING_AGG(r.[key] COLLATE DATABASE_DEFAULT + N' → ' + ISNULL(JSON_VALUE(r.[value], '$.role'), N'?'), N', ')
    FROM OPENJSON(@Canonical, '$.roles') r
    LEFT JOIN [security].[Role] ro ON ro.[RoleCode] = JSON_VALUE(r.[value], '$.role') AND ro.[IsActive] = 1
    WHERE ro.[RoleCode] IS NULL;
    IF @msg IS NOT NULL BEGIN SET @msg = N'Role aliases must map to an active security.Role: ' + @msg; THROW 50122, @msg, 1; END

    -- 50123 record kinds
    SELECT @msg = STRING_AGG(s.BlockId + N' (' + ISNULL(JSON_VALUE(s.BlockJson, '$.record.kind'), N'no record') + N')', N', ')
    FROM #b s
    LEFT JOIN [ref].[RecordKind] k ON k.[RecordKindCode] = JSON_VALUE(s.BlockJson, '$.record.kind') AND k.[IsActive] = 1
    WHERE s.Kind = N'step' AND k.[RecordKindCode] IS NULL;
    IF @msg IS NOT NULL BEGIN SET @msg = N'Every step produces a record of an active ref.RecordKind (#42): ' + @msg; THROW 50123, @msg, 1; END

    -- 50124 outcome vocabulary
    SELECT @msg = STRING_AGG(s.BlockId + N'.' + bo.[key] COLLATE DATABASE_DEFAULT, N', ')
    FROM #b s CROSS APPLY OPENJSON(s.BlockJson, '$.branchOutcome') bo
    WHERE s.Kind = N'step'
      AND NOT EXISTS (SELECT 1 FROM OPENJSON(ISNULL(JSON_QUERY(s.BlockJson, '$.outcomes'), N'["Done"]')) o WHERE o.[value] COLLATE DATABASE_DEFAULT = bo.[key] COLLATE DATABASE_DEFAULT);
    IF @msg IS NOT NULL BEGIN SET @msg = N'branchOutcome names an outcome the step does not declare: ' + @msg; THROW 50124, @msg, 1; END
    SELECT @msg = STRING_AGG(s.BlockId + N' (' + JSON_VALUE(s.BlockJson, '$.advances.onOutcome') + N')', N', ')
    FROM #b s
    WHERE s.Kind = N'step' AND JSON_VALUE(s.BlockJson, '$.advances.onOutcome') IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM OPENJSON(ISNULL(JSON_QUERY(s.BlockJson, '$.outcomes'), N'["Done"]')) o WHERE o.[value] = JSON_VALUE(s.BlockJson, '$.advances.onOutcome'));
    IF @msg IS NOT NULL BEGIN SET @msg = N'advances.onOutcome names an outcome the step does not declare: ' + @msg; THROW 50124, @msg, 1; END

    -- 50125 advances → an Effective workflow and a transition on it
    SELECT @msg = STRING_AGG(s.BlockId + N' → ' + JSON_VALUE(s.BlockJson, '$.advances.workflow') + N'.' + JSON_VALUE(s.BlockJson, '$.advances.transition'), N', ')
    FROM #b s
    WHERE s.Kind = N'step' AND JSON_QUERY(s.BlockJson, '$.advances') IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM [config].[Definition] d
        JOIN [config].[DefinitionVersion] dv ON dv.[DefinitionEntityId] = d.[EntityId] AND dv.[IsDeleted] = 0 AND dv.[Status] = N'Effective'
             AND dv.[EffectiveFrom] <= SYSDATETIMEOFFSET() AND (dv.[EffectiveTo] IS NULL OR dv.[EffectiveTo] > SYSDATETIMEOFFSET())
        CROSS APPLY OPENJSON(dv.[PayloadText], '$.transitions') t
        WHERE d.[IsDeleted] = 0 AND d.[DefinitionKind] = N'Program.Workflow' AND d.[DefinitionKey] = JSON_VALUE(s.BlockJson, '$.advances.workflow')
          AND JSON_VALUE(t.[value], '$.name') = JSON_VALUE(s.BlockJson, '$.advances.transition'));
    IF @msg IS NOT NULL BEGIN SET @msg = N'advances must name an Effective Program.Workflow and one of its transitions: ' + @msg; THROW 50125, @msg, 1; END

    -- 50126 call → a Program.Procedure definition
    SELECT @msg = STRING_AGG(s.BlockId + N' → ' + JSON_VALUE(s.BlockJson, '$.procedure'), N', ')
    FROM #b s
    WHERE s.Kind = N'call'
      AND NOT EXISTS (SELECT 1 FROM [config].[Definition] d WHERE d.[IsDeleted] = 0 AND d.[DefinitionKind] = N'Program.Procedure' AND d.[DefinitionKey] = JSON_VALUE(s.BlockJson, '$.procedure'));
    IF @msg IS NOT NULL BEGIN SET @msg = N'call must name a Program.Procedure definition: ' + @msg; THROW 50126, @msg, 1; END

    -- 50127 due.anchor → an earlier step
    SELECT @msg = STRING_AGG(s.BlockId + N' → ' + ISNULL(JSON_VALUE(s.BlockJson, '$.due.anchor'), N'?'), N', ')
    FROM #b s
    WHERE s.Kind = N'step' AND JSON_QUERY(s.BlockJson, '$.due') IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM #b a WHERE a.Kind = N'step' AND a.BlockId = JSON_VALUE(s.BlockJson, '$.due.anchor') AND a.Ordinal < s.Ordinal);
    IF @msg IS NOT NULL BEGIN SET @msg = N'due.anchor must name an earlier step: ' + @msg; THROW 50127, @msg, 1; END

    -- 50128 produces names unique
    SELECT @msg = STRING_AGG(n, N', ') FROM (SELECT JSON_VALUE(BlockJson, '$.produces.as') AS n FROM #b WHERE Kind = N'step' AND JSON_VALUE(BlockJson, '$.produces.as') IS NOT NULL GROUP BY JSON_VALUE(BlockJson, '$.produces.as') HAVING COUNT(*) > 1) d;
    IF @msg IS NOT NULL BEGIN SET @msg = N'produces names must be unique: ' + @msg; THROW 50128, @msg, 1; END

    -- 50135 document-declared fact names
    SELECT @msg = STRING_AGG(f.[FactName], N', ')
    FROM [compliance].[fPayloadFactNames](@Canonical) f
    WHERE (f.[FactName] LIKE N'procedure.%' AND f.[FactName] <> N'procedure.outcome'
           AND NOT EXISTS (SELECT 1 FROM #b WHERE Kind = N'step' AND N'procedure.' + JSON_VALUE(BlockJson, '$.produces.as') = f.[FactName]))
       OR (f.[FactName] LIKE N'input.%'
           AND NOT EXISTS (SELECT 1 FROM OPENJSON(@Canonical, '$.inputs') i WHERE N'input.' + i.[key] COLLATE DATABASE_DEFAULT = f.[FactName]));
    IF @msg IS NOT NULL BEGIN SET @msg = N'procedure.<name> must name a produces and input.<name> an input of this document: ' + @msg; THROW 50135, @msg, 1; END

    -- 50129 C1: a precondition inside a scope needs a branch exit in that scope
    SELECT @msg = STRING_AGG(s.BlockId + N' in ' + s.ScopePath, N', ')
    FROM #b s
    WHERE s.Kind = N'step' AND JSON_QUERY(s.BlockJson, '$.precondition') IS NOT NULL AND s.ScopePath IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM #b x WHERE x.Kind = N'step' AND x.ScopePath = s.ScopePath AND JSON_QUERY(x.BlockJson, '$.branchOutcome') IS NOT NULL);
    IF @msg IS NOT NULL BEGIN SET @msg = N'A step with a precondition must sit in a branch that some branchOutcome can end (C1): ' + @msg; THROW 50129, @msg, 1; END
END;
GO
