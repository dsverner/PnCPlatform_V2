-- #214 (2026-09-20): the compliance worker marks the requests a pass served — the run that served them, when, and how many
-- devices the pass covered. @RequestIds is a JSON array of request ids. A request already processed is left alone.
CREATE PROCEDURE [compliance].[EvaluationRequest_Complete]
    @RequestIds NVARCHAR(MAX),
    @RunId UNIQUEIDENTIFIER = NULL,
    @DevicesFound INT = NULL,
    @Completed INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE r SET [ProcessedAt] = SYSDATETIMEOFFSET(), [RunId] = @RunId, [DevicesFound] = @DevicesFound
      FROM [compliance].[EvaluationRequest] r
      JOIN OPENJSON(@RequestIds) j ON TRY_CONVERT(UNIQUEIDENTIFIER, j.[value]) = r.[RequestId]
     WHERE r.[ProcessedAt] IS NULL;
    SET @Completed = @@ROWCOUNT;
END;
GO
GRANT EXECUTE ON [compliance].[EvaluationRequest_Complete] TO [app_execute];
GO
