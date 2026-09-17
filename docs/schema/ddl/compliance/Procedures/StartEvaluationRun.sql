-- #173 (2026-09-17): open a rule-evaluation run. The generated [compliance].[RuleEvaluationRun_Append] declares @ActorId with no
-- default (an append-only table's actor is a column, not a convention), and the API never binds ActorId — SqlSession leaves it to
-- the procedure's own personnel.ResolveActor, which is how every other write in the platform attributes itself. Hand-editing the
-- generated file to add a default lasted exactly one deploy: tools/generate.py rewrites it from the catalog every time, so the
-- fix has to live in a file the generator does not own. This is that file; [compliance].[RuleEvaluationRun_Complete] is its pair.
-- The run row exists before the first obligation instance is written, because ObligationInstance.EvaluationRunId references it.
CREATE PROCEDURE [compliance].[StartEvaluationRun]
    @Mode NVARCHAR(20),
    @Trigger NVARCHAR(20),
    @StartedAt DATETIMEOFFSET(7),
    @RuleDefinitionVersionRowId UNIQUEIDENTIFIER = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @RunId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    SET @RunId = ISNULL(@RunId, NEWID());
    EXEC [compliance].[RuleEvaluationRun_Append] @RuleDefinitionVersionRowId = @RuleDefinitionVersionRowId, @Mode = @Mode, @Trigger = @Trigger,
         @StartedAt = @StartedAt, @ActorId = @ActorId, @RunId = @RunId OUTPUT;
END;
GO
GRANT EXECUTE ON [compliance].[StartEvaluationRun] TO [app_execute];
GO
