-- Hand-written read model (W6, decisions #127–#129). The legacy main-window grid: one row per DESIGNED configuration-file
-- revision of a device — the legacy (OLD_NO, Change Request ID) grain (LEGACY-SYSTEM §5) — with the state the legacy
-- toggle filtered on, read from the revision itself, not from the package alone (PROCEDURE-ENGINE §10 rows 1–3, refined):
--   Active      in service now (InServiceFrom set, InServiceTo null — FR-3.3, document.SetInService)
--   Archived    a later revision closed its in-service period, or the revision / package was superseded or withdrawn
--   Withdrawn   never in service and its device's member branch left the change (Superseded — the readback difference
--               resolved by raising a change; the W4 CYL). Legacy dropped such rows (its D prefix); here they stay readable.
--   Outstanding everything else — a change in flight (the legacy M)
-- CDATE = the revision's PreparedAt (the Calculate sign-off's commit); VDATE = InServiceFrom, set from the
-- RETURN_TO_SERVICE commit at BASELINE (process.CommitStep); "Set Verified Date" is that step, exposed as RtsStep*.
-- The subject column is DeviceEntityId (read scope by the Asset family: the relays placed under the grant's subtree);
-- no column is named EntityId, AssetEntityId or NodeEntityId, so the dispatcher picks it (src/PnC.Api/Data/Catalog.cs).
-- The station is found by hopping ParentEntityId (Path holds ancestors only, #94): position → panel → up to three more.
CREATE VIEW [document].[vSettingsRecord] AS
SELECT r.[RowSeq],
       cf.[RevisionRowId],
       cf.[DeviceEntityId],
       [GridState] = CASE
           WHEN cf.[InServiceFrom] IS NOT NULL AND cf.[InServiceTo] IS NULL THEN N'Active'
           WHEN cf.[InServiceTo] IS NOT NULL OR r.[Status] IN (N'Superseded', N'Withdrawn') OR lc.[CurrentState] IN (N'Superseded', N'Withdrawn') THEN N'Archived'
           WHEN left_change.[BlockInstanceEntityId] IS NOT NULL THEN N'Withdrawn'
           ELSE N'Outstanding' END,
       lc.[CurrentState]            AS [LifecycleState],
       lc.[EntityId]                AS [LifecycleWorkflowInstanceEntityId],
       r.[RevisionLabel],
       r.[Status]                   AS [RevisionStatus],
       r.[DocumentEntityId],
       cf.[FileKind], cf.[CaptureKind], cf.[ParseStatus], cf.[SettingsGroupCount],
       it.[PackageRevisionRowId],
       it.[Sequence]                AS [PackageSequence],
       w.[EntityId]                 AS [WorkRequestEntityId],
       w.[Title]                    AS [WorkRequestTitle],
       wt.[DefinitionKey]           AS [WorkTypeKey],
       wt.[Name]                    AS [WorkTypeName],
       pi.[EntityId]                AS [ProcedureInstanceEntityId],
       pi.[State]                   AS [ProcedureState],
       r.[PreparedAt]               AS [CalculatedAt],
       cp.[DisplayName]             AS [CalculatedByDisplayName],
       rts.[CommittedAt]            AS [ReturnToServiceAt],
       rts.[StepInstanceEntityId]   AS [RtsStepInstanceEntityId],
       rts.[State]                  AS [RtsStepState],
       cf.[InServiceFrom]           AS [VerifiedAt],          -- VDATE: set at BASELINE from the return-to-service instant; null until then, null for a withdrawn device
       cf.[InServiceFrom], cf.[InServiceTo], cf.[InServiceFromQuality],
       a.[Name]                     AS [DeviceName],
       a.[AssetTypeCode],
       a.[Status]                   AS [AssetStatus],
       a.[VoltageClassCode],
       sn.[KeyValue]                AS [SerialNumber],
       m.[ModelId], m.[ModelCode], m.[ModelName], m.[Technology],
       mfe.[Name]                   AS [ManufacturerName],
       fw.[VersionString]           AS [FirmwareVersion],
       dp.[EntityId]                AS [PositionNodeEntityId],
       dp.[Name]                    AS [PositionName],
       pnl.[EntityId]               AS [PanelNodeEntityId],
       pnl.[Name]                   AS [PanelName],
       st.[StationEntityId]         AS [StationNodeEntityId],
       st.[StationName],
       stno.[KeyValue]              AS [StationNumber],
       fn.[Functions]
FROM [document].[vConfigurationFile] cf
JOIN [document].[vRevision] r ON r.[RowId] = cf.[RevisionRowId]
LEFT JOIN [document].[vSettingsIssuePackageItem] it ON it.[ConfigurationFileRevisionRowId] = cf.[RevisionRowId]
LEFT JOIN [process].[vWorkflowInstance] lc ON lc.[SubjectKind] = N'SettingsIssuePackage' AND lc.[SubjectEntityId] = it.[PackageRevisionRowId]
OUTER APPLY (SELECT TOP (1) x.[WorkRequestEntityId] FROM [record].[vRecord] x
             WHERE x.[SecondSubjectKind] = N'ConfigurationFileRevision' AND x.[SecondSubjectEntityId] = cf.[RevisionRowId]
             ORDER BY x.[OccurredAt]) rec
LEFT JOIN [work].[vWorkRequest] w ON w.[EntityId] = rec.[WorkRequestEntityId]
LEFT JOIN [config].[vDefinitionVersion] wtv ON wtv.[RowId] = w.[WorkTypeDefinitionVersionRowId]
LEFT JOIN [config].[vDefinition] wt ON wt.[EntityId] = wtv.[DefinitionEntityId]
OUTER APPLY (SELECT TOP (1) p.[EntityId], p.[State] FROM [process].[vProcedureInstance] p
             WHERE p.[SubjectKind] = N'WorkRequest' AND p.[SubjectEntityId] = w.[EntityId] AND p.[ParentInstanceEntityId] IS NULL
               AND TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(p.[Produced], '$.package')) = it.[PackageRevisionRowId]
             ORDER BY p.[StartedAt] DESC) pi
OUTER APPLY (SELECT TOP (1) s.[EntityId] AS [StepInstanceEntityId], s.[State], s.[CommittedAt]
             FROM [process].[vBlockInstance] b JOIN [process].[vStepInstance] s ON s.[BlockInstanceEntityId] = b.[EntityId]
             WHERE b.[ProcedureInstanceEntityId] = pi.[EntityId] AND s.[StepId] = N'RETURN_TO_SERVICE'
             ORDER BY s.[CommittedAt] DESC, s.[RowSeq] DESC) rts
OUTER APPLY (SELECT TOP (1) b.[EntityId] AS [BlockInstanceEntityId] FROM [process].[vBlockInstance] b
             WHERE b.[ProcedureInstanceEntityId] = pi.[EntityId] AND b.[MemberSubjectEntityId] = cf.[DeviceEntityId] AND b.[Outcome] = N'Superseded') left_change
JOIN [asset].[vAsset] a ON a.[EntityId] = cf.[DeviceEntityId]
LEFT JOIN [device].[vDevice] dv ON dv.[EntityId] = a.[EntityId]
LEFT JOIN [ref].[vModel] m ON m.[ModelId] = a.[ModelId]
LEFT JOIN [ref].[vManufacturer] mf ON mf.[ManufacturerId] = m.[ManufacturerId]
LEFT JOIN [party].[vEntity] mfe ON mfe.[EntityId] = mf.[EntityEntityId]
LEFT JOIN [ref].[vFirmwareVersion] fw ON fw.[FirmwareVersionId] = COALESCE(cf.[FirmwareVersionId], dv.[CurrentFirmwareVersionId])
OUTER APPLY (SELECT TOP (1) k.[KeyValue] FROM [asset].[vAlternateKey] k WHERE k.[SubjectEntityId] = a.[EntityId] AND k.[KeyKindCode] = N'SerialNumber' ORDER BY k.[IsPrimaryLabel] DESC, k.[RowSeq]) sn
OUTER APPLY (SELECT TOP (1) p.[NodeEntityId] FROM [asset].[vPlacement] p WHERE p.[AssetEntityId] = a.[EntityId] AND p.[PlacementKind] = N'Installed' ORDER BY p.[ValidFrom] DESC) pl
LEFT JOIN [location].[vNode] dp  ON dp.[EntityId]  = pl.[NodeEntityId]
LEFT JOIN [location].[vNode] pnl ON pnl.[EntityId] = dp.[ParentEntityId]
LEFT JOIN [location].[vNode] h2  ON h2.[EntityId]  = pnl.[ParentEntityId]
LEFT JOIN [location].[vNode] h3  ON h3.[EntityId]  = h2.[ParentEntityId]
LEFT JOIN [location].[vNode] h4  ON h4.[EntityId]  = h3.[ParentEntityId]
OUTER APPLY (SELECT TOP (1) x.[StationEntityId], x.[StationName]
             FROM (VALUES (1, pnl.[EntityId], pnl.[NodeTypeCode], pnl.[Name]), (2, h2.[EntityId], h2.[NodeTypeCode], h2.[Name]),
                          (3, h3.[EntityId], h3.[NodeTypeCode], h3.[Name]), (4, h4.[EntityId], h4.[NodeTypeCode], h4.[Name])) x ([o], [StationEntityId], [T], [StationName])
             WHERE x.[T] = N'Station' ORDER BY x.[o]) st
OUTER APPLY (SELECT TOP (1) k.[KeyValue] FROM [location].[vAlternateKey] k WHERE k.[SubjectEntityId] = st.[StationEntityId] AND k.[KeyKindCode] = N'StationNumber' ORDER BY k.[IsPrimaryLabel] DESC, k.[RowSeq]) stno
OUTER APPLY (SELECT STRING_AGG(f.[AnsiCode], N', ') WITHIN GROUP (ORDER BY f.[IsPrincipal] DESC, f.[AnsiCode]) AS [Functions]
             FROM [location].[vNode] pf JOIN [scheme].[vCommissionedFunction] f ON f.[ProtectionFunctionNodeEntityId] = pf.[EntityId]
             WHERE pf.[ParentEntityId] = dp.[EntityId] AND pf.[NodeTypeCode] = N'ProtectionFunction') fn
LEFT JOIN [personnel].[vActor] ca ON ca.[ActorId] = r.[PreparedByActorId]
LEFT JOIN [personnel].[vPerson] cp ON cp.[EntityId] = ca.[PersonEntityId]
WHERE cf.[CaptureKind] = N'Designed' AND cf.[FileKind] IN (N'NativeSettings', N'SettingsText');
GO
GRANT SELECT ON [document].[vSettingsRecord] TO [app_execute];
GO
