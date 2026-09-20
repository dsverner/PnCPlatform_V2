-- #214 (2026-09-20): leave a request that the compliance rules be re-evaluated for a subject (or for everything, kind All).
-- Called by the API after a write that changed a fact the rules read (Engine/ComplianceTriggers.cs), on the writer's own
-- session, so the request carries the actor whose write caused it. Not callable over HTTP (api-permissions.json: null).
--   50281 unknown subject kind   50282 a subject is required unless the kind is All
CREATE PROCEDURE [compliance].[RequestEvaluation]
    @SubjectKind NVARCHAR(20),
    @SubjectEntityId UNIQUEIDENTIFIER = NULL,
    @Reason NVARCHAR(200),
    @ActorId UNIQUEIDENTIFIER = NULL,
    @RequestId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @SubjectKind NOT IN (N'Device', N'Asset', N'Node', N'Scheme', N'All') THROW 50281, N'compliance.RequestEvaluation: the subject kind must be Device, Asset, Node, Scheme or All.', 1;
    IF @SubjectKind <> N'All' AND @SubjectEntityId IS NULL THROW 50282, N'compliance.RequestEvaluation: a subject is required unless the kind is All.', 1;
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    SET @RequestId = ISNULL(@RequestId, NEWID());
    INSERT [compliance].[EvaluationRequest] ([RequestId], [SubjectKind], [SubjectEntityId], [Reason], [RequestedAt], [ActorId])
    VALUES (@RequestId, @SubjectKind, CASE WHEN @SubjectKind = N'All' THEN NULL ELSE @SubjectEntityId END, @Reason, SYSDATETIMEOFFSET(), @ActorId);
END;
GO
GRANT EXECUTE ON [compliance].[RequestEvaluation] TO [app_execute];
GO
