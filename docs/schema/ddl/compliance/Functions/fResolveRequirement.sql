-- FORMULA-GRAMMAR.md §7 / PROCEDURES.md #22. The requirement an obligation-rule payload names, as its entity id:
--   "requirement": "<Requirement EntityId>"
--   "requirement": {"standard":"<StandardCode>","version":"<VersionLabel>","number":"<RequirementNumber>","sub":"<SubRequirement>"|null}
-- NULL when it cannot be resolved (the caller refuses the payload).
CREATE FUNCTION [compliance].[fResolveRequirement] (@payload NVARCHAR(MAX))
RETURNS UNIQUEIDENTIFIER
AS
BEGIN
    DECLARE @id UNIQUEIDENTIFIER = TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(@payload, '$.requirement'));
    IF @id IS NOT NULL
        RETURN (SELECT TOP (1) r.[EntityId] FROM [compliance].[vRequirement] r WHERE r.[EntityId] = @id);
    IF JSON_QUERY(@payload, '$.requirement') IS NULL RETURN NULL;
    DECLARE @std NVARCHAR(40) = JSON_VALUE(@payload, '$.requirement.standard'), @ver NVARCHAR(40) = JSON_VALUE(@payload, '$.requirement.version'),
            @num NVARCHAR(40) = JSON_VALUE(@payload, '$.requirement.number'), @sub NVARCHAR(40) = JSON_VALUE(@payload, '$.requirement.sub');
    RETURN (SELECT TOP (1) r.[EntityId]
            FROM [compliance].[vRequirement] r
            JOIN [compliance].[vStandardVersion] sv ON sv.[RowId] = r.[StandardVersionRowId]
            WHERE sv.[StandardCode] = @std AND sv.[VersionLabel] = @ver AND r.[RequirementNumber] = @num
              AND ISNULL(r.[SubRequirement], N'') = ISNULL(@sub, N'')
            ORDER BY r.[ValidFrom] DESC);
END;
GO
