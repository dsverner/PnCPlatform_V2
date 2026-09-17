-- #171 (2026-09-16): a run row is appended when the pass starts (compliance.ObligationInstance.EvaluationRunId references it, so it
-- must exist before the first instance is written) and completed here with its counts when the pass ends. The table stays
-- append-only in the sense that matters — no row is ever deleted and a completed run is never reopened.
CREATE PROCEDURE [compliance].[RuleEvaluationRun_Complete]
    @RunId UNIQUEIDENTIFIER,
    @CompletedAt DATETIMEOFFSET(7),
    @SubjectsScoped INT = NULL,
    @InstancesOpened INT = NULL,
    @InstancesClosed INT = NULL,
    @InstancesUnchanged INT = NULL,
    @ResultDocumentEntityId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE [compliance].[RuleEvaluationRun]
       SET [CompletedAt] = @CompletedAt, [SubjectsScoped] = @SubjectsScoped, [InstancesOpened] = @InstancesOpened,
           [InstancesClosed] = @InstancesClosed, [InstancesUnchanged] = @InstancesUnchanged, [ResultDocumentEntityId] = @ResultDocumentEntityId
     WHERE [RunId] = @RunId AND [CompletedAt] IS NULL;
    IF @@ROWCOUNT = 0 THROW 50172, N'RuleEvaluationRun_Complete: no open run has that id.', 1;
END;
GO
GRANT EXECUTE ON [compliance].[RuleEvaluationRun_Complete] TO [app_execute];
GO
