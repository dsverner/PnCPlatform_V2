-- Hand-written read model (W6, decisions #127, #130). The legacy change-request / status window (LEGACY-SYSTEM §8): one
-- row per work request — its header, the request workflow's state, the root SETTINGS_CHANGE run, its package and
-- lifecycle, and the two completion tracks read from the run's parallel branches (PROCEDURE-ENGINE §10 row 4):
--   documentation = MAIN/COMPLETION/DOCUMENTATION (the DRAWING_REVISION child run: its RECORD_REVISION captures are the
--                   legacy link, revision label and date; IDENTIFY_DRAWINGS = NoneAffected is reported as DrawingsOutcome)
--   database      = MAIN/COMPLETION/DATABASE (the BASELINE step)
--   Completed → Complete; Skipped with NotApplicable → NA; Running/Held → In Progress; Cancelled; Pending (the run has not
--   reached COMPLETION yet — the branch rows are materialised when the run starts) or no row → Not Started
-- The software track is not modelled (#58): its legacy rows migrate as notes on the request (W7).
-- Block and step ids are the SETTINGS_CHANGE document's public names, the ones §10 already relies on. Subject column
-- WorkRequestEntityId (read scope by the WorkRequest family); no column is named EntityId/AssetEntityId/NodeEntityId.
-- Correlated lookups read the base tables with the current-row predicate in the filtered indexes' own form (ValidTo IS NULL AND IsDeleted = 0): an OUTER APPLY ... TOP (1) against a
-- generated current view (ROW_NUMBER over the entity) is evaluated over the whole table per outer row — 26 s a page on the
-- migrated estate, measured in W7 — where the same lookup on the base table seeks. The joins to the current views stay.
CREATE VIEW [work].[vChangeRequestStatus] AS
SELECT w.[RowSeq],
       w.[EntityId]                 AS [WorkRequestEntityId],
       w.[Title], w.[Description], w.[Notes], w.[PriorityCode],
       w.[ParentWorkRequestEntityId],
       wt.[DefinitionKey]           AS [WorkTypeKey],
       wt.[Name]                    AS [WorkTypeName],
       rp.[DisplayName]             AS [RequestedByDisplayName],
       w.[CreatedAt]                AS [RequestedAt],
       w.[ScopeKind], w.[ScopeEntityId],
       [ScopeName]                  = COALESCE(sn.[Name], sa.[Name]),
       [ScopeNodeEntityId]          = COALESCE(sn.[EntityId], spl.[NodeEntityId]),
       st.[StationName],
       [EquipmentName]              = COALESCE(sa.[Name], CASE WHEN scope_node.[NodeTypeCode] IN (N'DevicePosition', N'MeteringPosition', N'NetworkSwitchPosition', N'Panel', N'Bay', N'EquipmentPosition') THEN scope_node.[Name] END),
       w.[OutageRequired], w.[OutageWindowStartAt], w.[OutageWindowEndAt],
       rw.[EntityId]                AS [RequestWorkflowInstanceEntityId],
       rwk.[DefinitionKey]          AS [WorkflowKey],
       rw.[CurrentState]            AS [RequestState],
       rw.[StartedAt]               AS [RequestStartedAt],
       rw.[CompletedAt]             AS [RequestCompletedAt],
       rw.[IsCancelled],
       pi.[EntityId]                AS [ProcedureInstanceEntityId],
       pi.[State]                   AS [ProcedureState],
       pi.[Outcome]                 AS [ProcedureOutcome],
       pi.[StartedAt]               AS [ProcedureStartedAt],
       pi.[CompletedAt]             AS [ProcedureCompletedAt],
       pi.[PackageRevisionRowId],
       lc.[CurrentState]            AS [LifecycleState],
       [DeviceCount]                = (SELECT COUNT(*) FROM [document].[vSettingsIssuePackageItem] i WHERE i.[PackageRevisionRowId] = pi.[PackageRevisionRowId]),
       [DocumentationStatus]        = CASE WHEN doc.[State] = N'Completed' THEN N'Complete'
                                           WHEN doc.[State] = N'Skipped' AND doc.[Outcome] = N'NotApplicable' THEN N'NA'
                                           WHEN doc.[State] IN (N'Running', N'Held') THEN N'In Progress'
                                           WHEN doc.[State] = N'Cancelled' THEN N'Cancelled'
                                           ELSE N'Not Started' END,
       doc.[State]                  AS [DocumentationBlockState],
       doc.[Outcome]                AS [DocumentationOutcome],
       doc.[CompletedAt]            AS [DocumentationAt],
       JSON_VALUE(rr.[Draft], '$.documentLink')  AS [DocumentationLink],
       JSON_VALUE(rr.[Draft], '$.revisionLabel') AS [DocumentationRevisionLabel],
       TRY_CONVERT(DATETIMEOFFSET(7), JSON_VALUE(rr.[Draft], '$.revisedOn')) AS [DocumentationRevisedOn],
       JSON_VALUE(rr.[Draft], '$.note')          AS [DocumentationNote],
       rr.[CommittedRecordEntityId] AS [DocumentationRecordEntityId],
       idn.[Outcome]                AS [DrawingsOutcome],
       [DatabaseStatus]             = CASE WHEN db.[State] = N'Completed' THEN N'Complete'
                                           WHEN db.[State] = N'Skipped' AND db.[Outcome] = N'NotApplicable' THEN N'NA'
                                           WHEN db.[State] IN (N'Running', N'Held') THEN N'In Progress'
                                           WHEN db.[State] = N'Cancelled' THEN N'Cancelled'
                                           ELSE N'Not Started' END,
       db.[State]                   AS [DatabaseBlockState],
       db.[Outcome]                 AS [DatabaseOutcome],
       db.[CompletedAt]             AS [DatabaseAt],
       bl.[CommittedRecordEntityId] AS [BaselineRecordEntityId],
       bl.[StepInstanceEntityId]    AS [BaselineStepInstanceEntityId],
       bl.[State]                   AS [BaselineStepState],
       rts.[StepInstanceEntityId]   AS [RtsStepInstanceEntityId],
       rts.[State]                  AS [RtsStepState],
       rts.[CommittedAt]            AS [ReturnToServiceAt]
FROM [work].[vWorkRequest] w
LEFT JOIN [config].[vDefinitionVersion] wtv ON wtv.[RowId] = w.[WorkTypeDefinitionVersionRowId]
LEFT JOIN [config].[vDefinition] wt ON wt.[EntityId] = wtv.[DefinitionEntityId]
LEFT JOIN [personnel].[vActor] ra ON ra.[ActorId] = w.[CreatedBy]
LEFT JOIN [personnel].[vPerson] rp ON rp.[EntityId] = ra.[PersonEntityId]
LEFT JOIN [location].[vNode] sn ON w.[ScopeKind] = N'Node' AND sn.[EntityId] = w.[ScopeEntityId]
LEFT JOIN [asset].[vAsset] sa ON w.[ScopeKind] = N'Asset' AND sa.[EntityId] = w.[ScopeEntityId]
OUTER APPLY (SELECT TOP (1) p.[NodeEntityId] FROM [asset].[Placement] p WHERE p.[ValidTo] IS NULL AND p.[IsDeleted] = 0 AND p.[AssetEntityId] = sa.[EntityId] AND p.[PlacementKind] = N'Installed' ORDER BY p.[ValidFrom] DESC) spl
LEFT JOIN [location].[vNode] scope_node ON scope_node.[EntityId] = COALESCE(sn.[EntityId], spl.[NodeEntityId])
LEFT JOIN [location].[vNode] pnl ON pnl.[EntityId] = scope_node.[ParentEntityId]
LEFT JOIN [location].[vNode] h2  ON h2.[EntityId]  = pnl.[ParentEntityId]
LEFT JOIN [location].[vNode] h3  ON h3.[EntityId]  = h2.[ParentEntityId]
LEFT JOIN [location].[vNode] h4  ON h4.[EntityId]  = h3.[ParentEntityId]
OUTER APPLY (SELECT TOP (1) x.[StationName]
             FROM (VALUES (0, scope_node.[NodeTypeCode], scope_node.[Name]), (1, pnl.[NodeTypeCode], pnl.[Name]), (2, h2.[NodeTypeCode], h2.[Name]),
                          (3, h3.[NodeTypeCode], h3.[Name]), (4, h4.[NodeTypeCode], h4.[Name])) x ([o], [T], [StationName])
             WHERE x.[T] = N'Station' ORDER BY x.[o]) st
OUTER APPLY (SELECT TOP (1) i.[EntityId], i.[CurrentState], i.[StartedAt], i.[CompletedAt], i.[IsCancelled], i.[WorkflowDefinitionVersionRowId]
             FROM [process].[WorkflowInstance] i WHERE i.[IsDeleted] = 0 AND i.[SubjectKind] = N'WorkRequest' AND i.[SubjectEntityId] = w.[EntityId]
             ORDER BY i.[StartedAt] DESC) rw
LEFT JOIN [config].[vDefinitionVersion] rwv ON rwv.[RowId] = rw.[WorkflowDefinitionVersionRowId]
LEFT JOIN [config].[vDefinition] rwk ON rwk.[EntityId] = rwv.[DefinitionEntityId]
OUTER APPLY (SELECT TOP (1) p.[EntityId], p.[State], p.[Outcome], p.[StartedAt], p.[CompletedAt],
                    [PackageRevisionRowId] = TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(p.[Produced], '$.package'))
             FROM [process].[ProcedureInstance] p
             WHERE p.[IsDeleted] = 0 AND p.[SubjectKind] = N'WorkRequest' AND p.[SubjectEntityId] = w.[EntityId] AND p.[ParentInstanceEntityId] IS NULL
             ORDER BY p.[StartedAt] DESC) pi
LEFT JOIN [process].[vWorkflowInstance] lc ON lc.[SubjectKind] = N'SettingsIssuePackage' AND lc.[SubjectEntityId] = pi.[PackageRevisionRowId]
OUTER APPLY (SELECT TOP (1) b.[State], b.[Outcome], b.[CompletedAt] FROM [process].[BlockInstance] b
             WHERE b.[IsDeleted] = 0 AND b.[ProcedureInstanceEntityId] = pi.[EntityId] AND b.[BlockPath] = N'MAIN/COMPLETION/DOCUMENTATION' ORDER BY b.[RowSeq] DESC) doc
OUTER APPLY (SELECT TOP (1) b.[State], b.[Outcome], b.[CompletedAt] FROM [process].[BlockInstance] b
             WHERE b.[IsDeleted] = 0 AND b.[ProcedureInstanceEntityId] = pi.[EntityId] AND b.[BlockPath] = N'MAIN/COMPLETION/DATABASE' ORDER BY b.[RowSeq] DESC) db
OUTER APPLY (SELECT TOP (1) c.[EntityId] FROM [process].[ProcedureInstance] c
             WHERE c.[IsDeleted] = 0 AND c.[ParentInstanceEntityId] = pi.[EntityId] AND c.[CallBlockPath] = N'MAIN/COMPLETION/DOCUMENTATION/UPDATE_DRAWINGS' ORDER BY c.[StartedAt] DESC) child
OUTER APPLY (SELECT TOP (1) s.[Draft], s.[CommittedRecordEntityId], s.[CommittedAt]
             FROM [process].[BlockInstance] b JOIN [process].[StepInstance] s ON s.[BlockInstanceEntityId] = b.[EntityId]
             WHERE b.[IsDeleted] = 0 AND s.[IsDeleted] = 0 AND b.[ProcedureInstanceEntityId] = child.[EntityId] AND s.[StepId] = N'RECORD_REVISION' AND s.[State] = N'Committed' ORDER BY s.[CommittedAt] DESC) rr
OUTER APPLY (SELECT TOP (1) s.[Outcome]
             FROM [process].[BlockInstance] b JOIN [process].[StepInstance] s ON s.[BlockInstanceEntityId] = b.[EntityId]
             WHERE b.[IsDeleted] = 0 AND s.[IsDeleted] = 0 AND b.[ProcedureInstanceEntityId] = child.[EntityId] AND s.[StepId] = N'IDENTIFY_DRAWINGS' AND s.[State] = N'Committed' ORDER BY s.[CommittedAt] DESC) idn
OUTER APPLY (SELECT TOP (1) s.[EntityId] AS [StepInstanceEntityId], s.[State], s.[CommittedRecordEntityId]
             FROM [process].[BlockInstance] b JOIN [process].[StepInstance] s ON s.[BlockInstanceEntityId] = b.[EntityId]
             WHERE b.[IsDeleted] = 0 AND s.[IsDeleted] = 0 AND b.[ProcedureInstanceEntityId] = pi.[EntityId] AND s.[StepId] = N'BASELINE' ORDER BY s.[CommittedAt] DESC, s.[RowSeq] DESC) bl
OUTER APPLY (SELECT TOP (1) s.[EntityId] AS [StepInstanceEntityId], s.[State], s.[CommittedAt]
             FROM [process].[BlockInstance] b JOIN [process].[StepInstance] s ON s.[BlockInstanceEntityId] = b.[EntityId]
             WHERE b.[IsDeleted] = 0 AND s.[IsDeleted] = 0 AND b.[ProcedureInstanceEntityId] = pi.[EntityId] AND s.[StepId] = N'RETURN_TO_SERVICE' ORDER BY s.[CommittedAt] DESC, s.[RowSeq] DESC) rts;
GO
GRANT SELECT ON [work].[vChangeRequestStatus] TO [app_execute];
GO
