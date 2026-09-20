-- #214 (2026-09-20): a request that the compliance rules be re-evaluated, left by a write that changed something a rule reads.
-- The owner: "Should the evaluation be an automatic function of what is presently known about the system?" — it is: the API
-- leaves one of these after a classification, rating, placement, scheme membership, protects link, commissioned function
-- or in-service settings change (Engine/ComplianceTriggers.cs names the procedures), and after a rule, formula or derivation
-- is approved (SubjectKind All). The compliance worker takes the pending rows within seconds, expands each to the devices
-- affected (compliance.ExpandEvaluationRequests), runs one Effective pass over them (trigger FactChanged / RuleApproved) and marks
-- the rows processed with the run that served them. Append-only: a request is never deleted; the queue is its own audit.
CREATE TABLE [compliance].[EvaluationRequest] (
    [RequestId]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [PK_EvaluationRequest] PRIMARY KEY CLUSTERED,
    [SubjectKind]      NVARCHAR(20)      NOT NULL CONSTRAINT [CK_EvaluationRequest_Kind] CHECK ([SubjectKind] IN (N'Device', N'Asset', N'Node', N'Scheme', N'All')),
    [SubjectEntityId]  UNIQUEIDENTIFIER  NULL,
    [Reason]           NVARCHAR(200)     NOT NULL,   -- the procedure that changed the fact: "asset.RecordClassification"
    [RequestedAt]      DATETIMEOFFSET(7) NOT NULL,
    [ActorId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_EvaluationRequest_Actor] REFERENCES [personnel].[Actor] ([ActorId]),
    [ProcessedAt]      DATETIMEOFFSET(7) NULL,
    [RunId]            UNIQUEIDENTIFIER  NULL CONSTRAINT [FK_EvaluationRequest_Run] REFERENCES [compliance].[RuleEvaluationRun] ([RunId]),
    [DevicesFound]     INT               NULL,
    CONSTRAINT [CK_EvaluationRequest_Subject] CHECK ([SubjectKind] = N'All' OR [SubjectEntityId] IS NOT NULL)
);
GO
CREATE INDEX [IX_EvaluationRequest_Pending] ON [compliance].[EvaluationRequest] ([RequestedAt]) WHERE [ProcessedAt] IS NULL;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'compliance', @level1type = N'TABLE', @level1name = N'EvaluationRequest';
GO
