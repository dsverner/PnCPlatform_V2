-- PROCEDURE-ENGINE §4 (W4). One row per block activation of an instance with its step (if the block is a step) and the
-- projected step facts screens want (title, role, sign-off, witness, record kind, advances, produces). The interpreter
-- reads the tree from here; the API lists it. Draft is NOT here (its reads are logged on vStepInstance, #68).
CREATE VIEW [process].[vProcedureInstanceTree] AS
SELECT b.[ProcedureInstanceEntityId], b.[EntityId] AS [BlockInstanceEntityId], b.[ParentBlockInstanceEntityId], b.[BlockPath], b.[BlockKind],
       b.[IterationKey], b.[Pass], b.[MemberSubjectKind], b.[MemberSubjectEntityId], b.[State] AS [BlockState], b.[Outcome] AS [BlockOutcome],
       b.[StartedAt] AS [BlockStartedAt], b.[CompletedAt] AS [BlockCompletedAt], b.[RowSeq] AS [BlockRowSeq],
       s.[EntityId] AS [StepInstanceEntityId], s.[StepId], s.[State] AS [StepState], s.[AssignedRoleCode],
       s.[ClaimedByActorId], s.[ClaimedAt], s.[ClaimExpiresAt], s.[DraftModifiedAt], s.[CapturedAt], s.[CapturedByActorId], s.[CaptureSource],
       s.[CommittedRecordEntityId], s.[CommittedByActorId], s.[WitnessedByActorId], s.[AcceptedIntoPlatformByActorId], s.[CommittedAt], s.[Outcome] AS [StepOutcome],
       s.[DeviationFindingEntityId], s.[HeldReason],
       ps.[Ordinal] AS [StepOrdinal], ps.[Title], ps.[RoleAlias], ps.[RecordKindCode], ps.[SignoffAction], ps.[RequiresWitness], ps.[HasPrecondition], ps.[HasDue], ps.[AllowsDeviation],
       ps.[AdvancesWorkflowKey], ps.[AdvancesTransition], ps.[ProducesName], ps.[ProducesKind]
FROM [process].[BlockInstance] b
JOIN [process].[ProcedureInstance] i ON i.[EntityId] = b.[ProcedureInstanceEntityId] AND i.[IsDeleted] = 0
LEFT JOIN [process].[StepInstance] s ON s.[BlockInstanceEntityId] = b.[EntityId] AND s.[IsDeleted] = 0
LEFT JOIN [process].[ProcedureStep] ps ON ps.[DefinitionVersionRowId] = i.[DefinitionVersionRowId] AND ps.[StepId] = s.[StepId] AND ps.[IsDeleted] = 0
WHERE b.[IsDeleted] = 0;
GO
GRANT SELECT ON [process].[vProcedureInstanceTree] TO [app_execute];
GO
