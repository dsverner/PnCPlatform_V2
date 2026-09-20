-- #214 (2026-09-20): the evaluator records a subject's standing verdict for a rule or derivation. Writes only when the verdict
-- is new or has changed (result, reason, error, rule version or the reads), so SinceAt / SinceRunId say when the present
-- verdict began; an unchanged verdict writes nothing (@Outcome Unchanged). The Reference upsert the generator makes for the
-- table would move ModifiedAt on every pass; this one keeps the row still while the truth is still.
--   @Outcome  Set | Changed | Unchanged
CREATE PROCEDURE [compliance].[RecordSubjectVerdict]
    @SubjectKind NVARCHAR(40),
    @SubjectEntityId UNIQUEIDENTIFIER,
    @VerdictKind NVARCHAR(20),
    @DefinitionEntityId UNIQUEIDENTIFIER,
    @VersionRowId UNIQUEIDENTIFIER,
    @Result NVARCHAR(60) = NULL,
    @Reason NVARCHAR(400) = NULL,
    @ReadsJson NVARCHAR(MAX) = NULL,
    @Error NVARCHAR(400) = NULL,
    @RunId UNIQUEIDENTIFIER,
    @At DATETIMEOFFSET(7),
    @ActorId UNIQUEIDENTIFIER = NULL,
    @Outcome NVARCHAR(20) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF NOT EXISTS (SELECT 1 FROM [compliance].[SubjectVerdict] v
                   WHERE v.[SubjectKind] = @SubjectKind AND v.[SubjectEntityId] = @SubjectEntityId AND v.[VerdictKind] = @VerdictKind AND v.[DefinitionEntityId] = @DefinitionEntityId)
    BEGIN
        INSERT [compliance].[SubjectVerdict] ([SubjectKind], [SubjectEntityId], [VerdictKind], [DefinitionEntityId], [VersionRowId], [Result], [Reason], [ReadsJson], [Error],
                                             [SinceRunId], [SinceAt], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
        VALUES (@SubjectKind, @SubjectEntityId, @VerdictKind, @DefinitionEntityId, @VersionRowId, @Result, @Reason, @ReadsJson, @Error, @RunId, @At, @ActorId, @now, @ActorId, @now);
        SET @Outcome = N'Set';
        RETURN;
    END
    UPDATE v SET [VersionRowId] = @VersionRowId, [Result] = @Result, [Reason] = @Reason, [ReadsJson] = @ReadsJson, [Error] = @Error,
                 [SinceRunId] = @RunId, [SinceAt] = @At, [IsActive] = 1, [ModifiedBy] = @ActorId, [ModifiedAt] = @now
      FROM [compliance].[SubjectVerdict] v
     WHERE v.[SubjectKind] = @SubjectKind AND v.[SubjectEntityId] = @SubjectEntityId AND v.[VerdictKind] = @VerdictKind AND v.[DefinitionEntityId] = @DefinitionEntityId
       AND (v.[IsActive] = 0 OR v.[VersionRowId] <> @VersionRowId
            OR ISNULL(v.[Result], N'') <> ISNULL(@Result, N'') OR ISNULL(v.[Reason], N'') <> ISNULL(@Reason, N'') OR ISNULL(v.[Error], N'') <> ISNULL(@Error, N'')
            OR ISNULL(v.[ReadsJson], N'') <> ISNULL(@ReadsJson, N''));
    SET @Outcome = CASE WHEN @@ROWCOUNT = 0 THEN N'Unchanged' ELSE N'Changed' END;
END;
GO
GRANT EXECUTE ON [compliance].[RecordSubjectVerdict] TO [app_execute];
GO
