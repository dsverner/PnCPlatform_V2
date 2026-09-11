-- SCHEMA-DESIGN §2.3 (75): the resolver. Among effective versions of @DefinitionKind whose
-- non-overlay applies-to rows all match the subject's facts, pick the one matching the most
-- dimensions (a version with no rows is the default and matches everything with score 0).
-- Ties are a configuration error, surfaced, not silently resolved. Then every effective
-- overlay version whose rows match is returned, in order, after the base.
-- Result set: (Rank, IsOverlay, DefinitionEntityId, DefinitionKey, VersionRowId, DimensionsMatched).
CREATE PROCEDURE [config].[ResolveDefinition]
    @DefinitionKind NVARCHAR(40),
    @Facts [config].[AppliesToFactList] READONLY,
    @At DATETIMEOFFSET(7) = NULL,
    @BaseVersionRowId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @At = ISNULL(@At, SYSDATETIMEOFFSET());

    ;WITH eff AS (
        SELECT v.[RowId], v.[DefinitionEntityId], d.[DefinitionKey]
        FROM [config].[DefinitionVersion] v
        JOIN [config].[Definition] d ON d.[EntityId] = v.[DefinitionEntityId] AND d.[IsDeleted] = 0
        WHERE d.[DefinitionKind] = @DefinitionKind AND v.[IsDeleted] = 0 AND v.[Status] = N'Effective'
          AND v.[EffectiveFrom] <= @At AND (v.[EffectiveTo] IS NULL OR v.[EffectiveTo] > @At)
    ), rows_ AS (
        SELECT a.[DefinitionVersionRowId], a.[DimensionCode], a.[ValueEntityId], a.[ValueCode], a.[IsOverlay]
        FROM [config].[DefinitionAppliesTo] a
        WHERE a.[IsDeleted] = 0 AND a.[ValidFrom] <= @At AND (a.[ValidTo] IS NULL OR a.[ValidTo] > @At)
    ), scored AS (
        SELECT e.[RowId], e.[DefinitionEntityId], e.[DefinitionKey],
               IsOverlay = CASE WHEN EXISTS (SELECT 1 FROM rows_ r WHERE r.[DefinitionVersionRowId] = e.[RowId] AND r.[IsOverlay] = 1) THEN 1 ELSE 0 END,
               Required  = (SELECT COUNT(*) FROM rows_ r WHERE r.[DefinitionVersionRowId] = e.[RowId]),
               Matched   = (SELECT COUNT(*) FROM rows_ r JOIN @Facts f ON f.[DimensionCode] = r.[DimensionCode]
                            WHERE r.[DefinitionVersionRowId] = e.[RowId]
                              AND ((r.[ValueEntityId] IS NOT NULL AND r.[ValueEntityId] = f.[ValueEntityId])
                                OR (r.[ValueCode] IS NOT NULL AND r.[ValueCode] = f.[ValueCode])))
        FROM eff e
    ), candidates AS (
        SELECT * FROM scored WHERE Matched = Required
    )
    SELECT * INTO #c FROM candidates;

    DECLARE @best INT = (SELECT MAX(Matched) FROM #c WHERE IsOverlay = 0);
    IF @best IS NULL
    BEGIN
        SET @BaseVersionRowId = NULL;
        SELECT TOP (0) [Rank] = 0, IsOverlay, DefinitionEntityId, DefinitionKey, VersionRowId = [RowId], DimensionsMatched = Matched FROM #c;
        RETURN;
    END
    IF (SELECT COUNT(*) FROM #c WHERE IsOverlay = 0 AND Matched = @best) > 1
    BEGIN
        DECLARE @keys NVARCHAR(MAX) = (SELECT STRING_AGG(DefinitionKey, N', ') FROM #c WHERE IsOverlay = 0 AND Matched = @best);
        DECLARE @msg NVARCHAR(MAX) = N'Applies-to tie for ' + @DefinitionKind + N' between: ' + @keys + N'. Configuration error; the Administrator must add a distinguishing dimension.';
        THROW 50040, @msg, 1;
    END
    SELECT @BaseVersionRowId = [RowId] FROM #c WHERE IsOverlay = 0 AND Matched = @best;

    SELECT [Rank] = ROW_NUMBER() OVER (ORDER BY IsOverlay, Matched DESC, DefinitionKey),
           IsOverlay, DefinitionEntityId, DefinitionKey, VersionRowId = [RowId], DimensionsMatched = Matched
    FROM #c
    WHERE [RowId] = @BaseVersionRowId OR IsOverlay = 1
    ORDER BY [Rank];
END;
GO
