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
-- Correlated lookups read the base tables with the current-row predicate in the filtered indexes' own form (ValidTo IS NULL AND IsDeleted = 0): an OUTER APPLY ... TOP (1) against a
-- generated current view (ROW_NUMBER over the entity) is evaluated over the whole table per outer row — 26 s a page on the
-- migrated estate, measured in W7 — where the same lookup on the base table seeks. The joins to the current views stay.
CREATE VIEW [document].[vSettingsRecord] AS
SELECT r.[RowSeq],
       cf.[RevisionRowId],
       cf.[DeviceEntityId],
       [GridState] = CASE
           WHEN r.[Status] IN (N'Superseded', N'Withdrawn') OR lc.[CurrentState] IN (N'Superseded', N'Withdrawn') THEN N'Archived'   -- the letters first (W7: a retired device's last revision keeps an open period)
           WHEN cf.[InServiceFrom] IS NOT NULL AND cf.[InServiceTo] IS NULL THEN N'Active'
           WHEN cf.[InServiceTo] IS NOT NULL THEN N'Archived'
           WHEN left_change.[BlockInstanceEntityId] IS NOT NULL THEN N'Withdrawn'
           ELSE N'Outstanding' END,
       lc.[CurrentState]            AS [LifecycleState],
       lc.[EntityId]                AS [LifecycleWorkflowInstanceEntityId],
       r.[RevisionLabel],
       r.[Status]                   AS [RevisionStatus],
       r.[DocumentEntityId],
       cf.[FileKind], cf.[CaptureKind], cf.[ParseStatus], cf.[ParseError], cf.[SettingsGroupCount],   -- ParseError: the names the template did not know (#168)
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
       fn.[Functions],
       sch.[SchemeEntityId], sch.[SchemeName]          -- W8 (#158): the functional scheme the device belongs to — the grid's group
FROM [document].[vConfigurationFile] cf
JOIN [document].[vRevision] r ON r.[RowId] = cf.[RevisionRowId]
LEFT JOIN [document].[vSettingsIssuePackageItem] it ON it.[ConfigurationFileRevisionRowId] = cf.[RevisionRowId]
OUTER APPLY (SELECT TOP (1) lc.[EntityId], lc.[CurrentState] FROM [process].[WorkflowInstance] lc
             WHERE lc.[IsDeleted] = 0 AND lc.[SubjectKind] = N'SettingsIssuePackage' AND lc.[SubjectEntityId] = it.[PackageRevisionRowId] ORDER BY lc.[RowSeq] DESC) lc
OUTER APPLY (SELECT TOP (1) x.[WorkRequestEntityId] FROM [record].[Record] x
             WHERE x.[ValidTo] IS NULL AND x.[IsDeleted] = 0 AND x.[SecondSubjectKind] = N'ConfigurationFileRevision' AND x.[SecondSubjectEntityId] = cf.[RevisionRowId]
             ORDER BY x.[OccurredAt]) rec
-- #168 (2026-09-16): the request and the package's lifecycle read from the base tables in the current-row form, like the other lookups here:
-- on the reloaded DEV the optimizer evaluated the generated current view of work requests once per outer row (the whole table scanned and
-- sorted 11 572 times, 137 million rows, 48 s for the view)
OUTER APPLY (SELECT TOP (1) x.[WorkRequestEntityId] FROM [record].[Record] x
             WHERE x.[ValidTo] IS NULL AND x.[IsDeleted] = 0 AND x.[SecondSubjectKind] = N'SettingsIssuePackage' AND x.[SecondSubjectEntityId] = it.[PackageRevisionRowId]
             ORDER BY x.[OccurredAt]) prec
OUTER APPLY (SELECT TOP (1) w.[EntityId], w.[Title], w.[WorkTypeDefinitionVersionRowId] FROM [work].[WorkRequest] w
             WHERE w.[ValidTo] IS NULL AND w.[IsDeleted] = 0 AND w.[EntityId] = COALESCE(rec.[WorkRequestEntityId], prec.[WorkRequestEntityId]) ORDER BY w.[RowSeq] DESC) w   -- #168: a copy made at the request step belongs to its request before any record points at it
LEFT JOIN [config].[vDefinitionVersion] wtv ON wtv.[RowId] = w.[WorkTypeDefinitionVersionRowId]
LEFT JOIN [config].[vDefinition] wt ON wt.[EntityId] = wtv.[DefinitionEntityId]
OUTER APPLY (SELECT TOP (1) p.[EntityId], p.[State] FROM [process].[ProcedureInstance] p
             WHERE p.[IsDeleted] = 0 AND p.[SubjectKind] = N'WorkRequest' AND p.[SubjectEntityId] = w.[EntityId] AND p.[ParentInstanceEntityId] IS NULL
               AND TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(p.[Produced], '$.package')) = it.[PackageRevisionRowId]
             ORDER BY p.[StartedAt] DESC) pi
OUTER APPLY (SELECT TOP (1) s.[EntityId] AS [StepInstanceEntityId], s.[State], s.[CommittedAt]
             FROM [process].[BlockInstance] b JOIN [process].[StepInstance] s ON s.[BlockInstanceEntityId] = b.[EntityId]
             WHERE b.[IsDeleted] = 0 AND s.[IsDeleted] = 0 AND b.[ProcedureInstanceEntityId] = pi.[EntityId] AND s.[StepId] = N'RETURN_TO_SERVICE'
             ORDER BY s.[CommittedAt] DESC, s.[RowSeq] DESC) rts
OUTER APPLY (SELECT TOP (1) b.[EntityId] AS [BlockInstanceEntityId] FROM [process].[BlockInstance] b
             WHERE b.[IsDeleted] = 0 AND b.[ProcedureInstanceEntityId] = pi.[EntityId] AND b.[MemberSubjectEntityId] = cf.[DeviceEntityId] AND b.[Outcome] = N'Superseded') left_change
JOIN [asset].[vAsset] a ON a.[EntityId] = cf.[DeviceEntityId]
LEFT JOIN [device].[vDevice] dv ON dv.[EntityId] = a.[EntityId]
LEFT JOIN [ref].[vModel] m ON m.[ModelId] = a.[ModelId]
LEFT JOIN [ref].[vManufacturer] mf ON mf.[ManufacturerId] = m.[ManufacturerId]
LEFT JOIN [party].[vEntity] mfe ON mfe.[EntityId] = mf.[EntityEntityId]
LEFT JOIN [ref].[vFirmwareVersion] fw ON fw.[FirmwareVersionId] = COALESCE(cf.[FirmwareVersionId], dv.[CurrentFirmwareVersionId])
OUTER APPLY (SELECT TOP (1) k.[KeyValue] FROM [asset].[AlternateKey] k WHERE k.[ValidTo] IS NULL AND k.[IsDeleted] = 0 AND k.[SubjectEntityId] = a.[EntityId] AND k.[KeyKindCode] = N'SerialNumber' ORDER BY k.[IsPrimaryLabel] DESC, k.[RowSeq]) sn
OUTER APPLY (SELECT TOP (1) p.[NodeEntityId] FROM [asset].[Placement] p WHERE p.[ValidTo] IS NULL AND p.[IsDeleted] = 0 AND p.[AssetEntityId] = a.[EntityId] AND p.[PlacementKind] = N'Installed' ORDER BY p.[ValidFrom] DESC) pl
LEFT JOIN [location].[vNode] dp  ON dp.[EntityId]  = pl.[NodeEntityId]
LEFT JOIN [location].[vNode] pnl ON pnl.[EntityId] = dp.[ParentEntityId]
LEFT JOIN [location].[vNode] h2  ON h2.[EntityId]  = pnl.[ParentEntityId]
LEFT JOIN [location].[vNode] h3  ON h3.[EntityId]  = h2.[ParentEntityId]
LEFT JOIN [location].[vNode] h4  ON h4.[EntityId]  = h3.[ParentEntityId]
OUTER APPLY (SELECT TOP (1) x.[StationEntityId], x.[StationName]
             FROM (VALUES (1, pnl.[EntityId], pnl.[NodeTypeCode], pnl.[Name]), (2, h2.[EntityId], h2.[NodeTypeCode], h2.[Name]),
                          (3, h3.[EntityId], h3.[NodeTypeCode], h3.[Name]), (4, h4.[EntityId], h4.[NodeTypeCode], h4.[Name])) x ([o], [StationEntityId], [T], [StationName])
             WHERE x.[T] = N'Station' ORDER BY x.[o]) st
OUTER APPLY (SELECT TOP (1) k.[KeyValue] FROM [location].[AlternateKey] k WHERE k.[ValidTo] IS NULL AND k.[IsDeleted] = 0 AND k.[SubjectEntityId] = st.[StationEntityId] AND k.[KeyKindCode] = N'StationNumber' ORDER BY k.[IsPrimaryLabel] DESC, k.[RowSeq]) stno
OUTER APPLY (SELECT STRING_AGG(f.[AnsiCode], N', ') WITHIN GROUP (ORDER BY f.[IsPrincipal] DESC, f.[AnsiCode]) AS [Functions]
             FROM [location].[Node] pf JOIN [scheme].[CommissionedFunction] f ON f.[ProtectionFunctionNodeEntityId] = pf.[EntityId]
             WHERE pf.[ValidTo] IS NULL AND pf.[IsDeleted] = 0 AND f.[ValidTo] IS NULL AND f.[IsDeleted] = 0 AND pf.[ParentEntityId] = dp.[EntityId] AND pf.[NodeTypeCode] = N'ProtectionFunction') fn
-- W8 (#158): the scheme through the asset's own membership first (the migration's equipment group), else through a
-- protection function under the position. Three seeks on the base tables in the filtered indexes' own form
-- (IX_SchemeMember_Member on (MemberKind, MemberEntityId)); one combined OR/EXISTS apply measured 28 s for the whole
-- estate against 1.8 s without it (2026-09-14, typed parameters as the API binds them), these three 1.9 s.
OUTER APPLY (SELECT TOP (1) sm.[SchemeEntityId] FROM [scheme].[SchemeMember] sm
             WHERE sm.[ValidTo] IS NULL AND sm.[IsDeleted] = 0 AND sm.[MemberKind] = N'Asset' AND sm.[MemberEntityId] = a.[EntityId]
             ORDER BY sm.[RowSeq]) sma
OUTER APPLY (SELECT TOP (1) sm.[SchemeEntityId] FROM [location].[Node] pf
             JOIN [scheme].[SchemeMember] sm ON sm.[MemberKind] = N'ProtectionFunction' AND sm.[MemberEntityId] = pf.[EntityId] AND sm.[ValidTo] IS NULL AND sm.[IsDeleted] = 0
             WHERE sma.[SchemeEntityId] IS NULL AND pf.[ParentEntityId] = dp.[EntityId] AND pf.[NodeTypeCode] = N'ProtectionFunction' AND pf.[ValidTo] IS NULL AND pf.[IsDeleted] = 0
             ORDER BY sm.[RowSeq]) smf
OUTER APPLY (SELECT TOP (1) s.[EntityId] AS [SchemeEntityId], s.[Name] AS [SchemeName] FROM [scheme].[Scheme] s
             WHERE s.[EntityId] = COALESCE(sma.[SchemeEntityId], smf.[SchemeEntityId]) AND s.[ValidTo] IS NULL AND s.[IsDeleted] = 0
             ORDER BY s.[ValidFrom] DESC, s.[RowSeq] DESC) sch
LEFT JOIN [personnel].[vActor] ca ON ca.[ActorId] = r.[PreparedByActorId]
LEFT JOIN [personnel].[vPerson] cp ON cp.[EntityId] = ca.[PersonEntityId]
WHERE cf.[CaptureKind] = N'Designed' AND cf.[FileKind] IN (N'NativeSettings', N'SettingsText');
GO
GRANT SELECT ON [document].[vSettingsRecord] TO [app_execute];
GO
