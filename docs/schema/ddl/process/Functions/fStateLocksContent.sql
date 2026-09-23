-- #231 (2026-09-23): whether a workflow state, as the version the instance is pinned to defines it, fixes its subject's
-- content — the state flag `locksContent` (workflow.schema.json). Read generically, as `cancellation` is (#228): the settings
-- lifecycles flag the states in which the package's settings are on the relay (Applied, and Verified in the full one), so no
-- procedure or state name is written in code. The owner, 2026-09-23: once applied, the settings are not edited.
-- Inline, so a view can apply it per row. Locked = 0 for a NULL version or state.
CREATE FUNCTION [process].[fStateLocksContent] (@WorkflowDefinitionVersionRowId UNIQUEIDENTIFIER, @StateCode NVARCHAR(40))
RETURNS TABLE
AS
RETURN (
    SELECT CAST(CASE WHEN EXISTS (
        SELECT 1 FROM [config].[DefinitionVersion] dv CROSS APPLY OPENJSON(dv.[PayloadText], '$.states') st
        WHERE dv.[RowId] = @WorkflowDefinitionVersionRowId AND JSON_VALUE(st.[value], '$.code') = @StateCode
          AND JSON_VALUE(st.[value], '$.locksContent') = 'true') THEN 1 ELSE 0 END AS BIT) AS [Locked]
);
GO
