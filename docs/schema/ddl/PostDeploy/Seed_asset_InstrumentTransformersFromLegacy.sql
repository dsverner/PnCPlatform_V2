-- #206 (2026-09-20): the instrument transformers a protection needs exist. The owner: "when a particular device indicates
-- migration-rule: #206 a scheme's CT and PT sets are made from its in-service devices' legacy CT_MAIN/PT_MAIN strings (one set per distinct ratio) and from the inputs the devices' functions need (a set with the ratio unknown; a single-phase sync PT for a 25); each device's CT_AUX/PT_AUX strings become auxiliary transformers at its panel; never a duplicate of a source the scheme already has; a set stands unplaced until a person places it
-- that it has CT and PT inputs, it is reasonable to assume that they exist because without them, the protection is useless
-- ... a KD relay is a distance protection which requires voltage and current inputs"; and, of the ratio settings, "there are
-- three sets of instrument transformers ... a three phase set of CTs feeding the protection, a three phase set of PTs feeding
-- the protection and a single phase PT feeding the sync input ... the application should create those three devices and
-- assign them to this protection. There may be no formal FLOC set for them yet and this will require user input." Ruled the
-- scheme's (one set per distinct declared ratio), the user correcting reality afterwards (paralleled CTs, separate
-- secondary windings). This reverses #201's "no transformer is invented from a string": the string is now the ratio of a
-- set the device's own inputs prove exists.
--
-- What it reads (all migrated data): the in-service settings records (document.vSettingsRecord, GridState Active) of
-- each scheme; the CT_MAIN1..4 / PT_MAIN / CT_AUX1..4 / PT_AUX segments the importer put in the revision record's summary
-- (record.Record, kind ConfigurationFileRevision: "...; CT_MAIN1=1200-5; PT_MAIN=2000-1"); and what the device's
-- commissioned functions need (scheme.vPositionFunction.NeedsCurrent / NeedsVoltage / NeedsSyncVoltage, ruled on
-- ref.AnsiFunction.AnalogInputs). Measured on DEV 2026-09-20: 5 666 in-service records in 1 031 schemes; CT_MAIN1 on
-- 3 054, CT_MAIN2 580, PT_MAIN 1 600, CT_AUX1 160, PT_AUX 290; 396 schemes with devices declaring different CT ratios;
-- 25 on devices of 44 schemes; no migrated station has a Yard, so nothing here is placed except the auxiliaries (a
-- CT_AUX / VT_AUX stands at a Panel, #202, and the device's panel is known).
--
-- What it writes, per scheme: one CT asset per distinct declared CT ratio (name "<scheme> CTs <ratio>", Phases 3,
-- RatioInUse, role CtSource); one VT per distinct PT ratio ("<scheme> PTs <ratio>", VtSource); when no CT set came from a
-- string but a device's functions need current, "<scheme> CTs (ratio unknown)" — likewise "PTs (ratio unknown)" for
-- voltage; when a device has a 25, "<scheme> sync PT" (Phases 1, role SyncVtSource, ratio unknown); per device, its
-- aux strings as CT_AUX / VT_AUX assets placed at its panel (a panel holds every auxiliary on it, #206 SharesNode; the
-- first run, before that, left the second auxiliary on a panel unplaced — step 7 places those). A declared value that is not <n>:<m> (the legacy "1",
-- "????", "NA") makes nothing and is counted. A scheme that already has a live source of the role with the same ratio
-- (to half a percent) — or, for an unknown-ratio set, any live source of the role — gets none.
--
-- Idempotent and never re-creating what a person retired: every asset made here carries asset.AlternateKey kind
-- MigrationSource = <scheme>/<role>/<ratio | unknown | sync>  (aux: <position>/aux/<KEY>), checked in the base table
-- regardless of IsDeleted or ValidTo. Written as the system actor with the source record's MigrationRunId.
IF OBJECT_ID(N'[asset].[Asset_Add]') IS NULL OR OBJECT_ID(N'[scheme].[vPositionFunction]') IS NULL OR OBJECT_ID(N'[document].[vSettingsRecord]') IS NULL RETURN;
GO
SET NOCOUNT ON;
DECLARE @sys UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';

-- the nameplate keys of the two templates (the Effective version; #206 added Phases to it)
DECLARE @ctRatio UNIQUEIDENTIFIER, @ctPhases UNIQUEIDENTIFIER, @vtRatio UNIQUEIDENTIFIER, @vtPhases UNIQUEIDENTIFIER;
SELECT @ctRatio  = MAX(CASE WHEN d.[DefinitionKey] = N'CT_Template' AND cd.[CharacteristicKey] = N'RatioInUse' THEN cd.[RowId] END),
       @ctPhases = MAX(CASE WHEN d.[DefinitionKey] = N'CT_Template' AND cd.[CharacteristicKey] = N'Phases'     THEN cd.[RowId] END),
       @vtRatio  = MAX(CASE WHEN d.[DefinitionKey] = N'VT_Template' AND cd.[CharacteristicKey] = N'RatioInUse' THEN cd.[RowId] END),
       @vtPhases = MAX(CASE WHEN d.[DefinitionKey] = N'VT_Template' AND cd.[CharacteristicKey] = N'Phases'     THEN cd.[RowId] END)
FROM [config].[Definition] d
JOIN [config].[DefinitionVersion] v ON v.[DefinitionEntityId] = d.[EntityId] AND v.[IsDeleted] = 0 AND v.[Status] = N'Effective'
JOIN [config].[CharacteristicDefinition] cd ON cd.[DefinitionVersionRowId] = v.[RowId]
WHERE d.[DefinitionKind] = N'CharacteristicSchema.AssetTemplate' AND d.[DefinitionKey] IN (N'CT_Template', N'VT_Template') AND d.[IsDeleted] = 0;
IF @ctRatio IS NULL OR @vtRatio IS NULL OR @ctPhases IS NULL OR @vtPhases IS NULL
BEGIN PRINT N'#206: the CT_Template / VT_Template nameplate keys are not all Effective; nothing made.'; RETURN; END
IF NOT EXISTS (SELECT 1 FROM [ref].[AlternateKeyKind] WHERE [KeyKindCode] = N'MigrationSource')
BEGIN PRINT N'#206: the MigrationSource key kind is missing; nothing made.'; RETURN; END

-- 1. the in-service migrated records with their scheme, position, panel and the summary the importer wrote
SELECT r.[RevisionRowId], r.[DeviceEntityId], r.[DeviceName], r.[SchemeEntityId], r.[SchemeName], r.[PositionNodeEntityId], r.[PositionName], r.[PanelNodeEntityId],
       rec.[Summary], rec.[MigrationRunId]
INTO #rec
FROM [document].[vSettingsRecord] r
JOIN [record].[Record] rec ON rec.[RecordKindCode] = N'ConfigurationFileRevision' AND rec.[SecondSubjectEntityId] = r.[RevisionRowId]
                          AND rec.[ValidTo] IS NULL AND rec.[IsDeleted] = 0 AND rec.[MigrationRunId] IS NOT NULL
WHERE r.[GridState] = N'Active' AND r.[SchemeEntityId] IS NOT NULL;

-- 2. the declared strings, one row per (record, key), the ratio read as a number where it is one
DECLARE @keys TABLE ([Key] NVARCHAR(10), [Kind] NVARCHAR(6), [N] INT);
INSERT @keys VALUES (N'CT_MAIN1', N'CT', 1), (N'CT_MAIN2', N'CT', 2), (N'CT_MAIN3', N'CT', 3), (N'CT_MAIN4', N'CT', 4), (N'PT_MAIN', N'PT', 1),
                    (N'CT_AUX1', N'CTAUX', 1), (N'CT_AUX2', N'CTAUX', 2), (N'CT_AUX3', N'CTAUX', 3), (N'CT_AUX4', N'CTAUX', 4), (N'PT_AUX', N'PTAUX', 1);
SELECT x.*, k.[Key], k.[Kind], k.[N], v.[Raw], nrm.[Norm],
       [RatioNum] = CASE WHEN p.[Primary] > 0 AND p.[Secondary] > 0 THEN ROUND(p.[Primary] / p.[Secondary], 3) END
INTO #decl
FROM #rec x
CROSS JOIN @keys k
CROSS APPLY (SELECT CHARINDEX(N'; ' + k.[Key] + N'=', x.[Summary]) AS [P]) f
CROSS APPLY (SELECT CASE WHEN f.[P] > 0 THEN LTRIM(RTRIM(SUBSTRING(x.[Summary], f.[P] + LEN(k.[Key]) + 3,
                         CHARINDEX(N';', x.[Summary] + N';', f.[P] + LEN(k.[Key]) + 3) - (f.[P] + LEN(k.[Key]) + 3)))) END AS [Raw]) v
CROSS APPLY (SELECT REPLACE(REPLACE(REPLACE(v.[Raw], N'-', N':'), N'/', N':'), N' ', N'') AS [Norm]) nrm
CROSS APPLY (SELECT CASE WHEN CHARINDEX(N':', nrm.[Norm]) > 1 THEN TRY_CONVERT(DECIMAL(18,4), LEFT(nrm.[Norm], CHARINDEX(N':', nrm.[Norm]) - 1)) END AS [Primary],
                    CASE WHEN CHARINDEX(N':', nrm.[Norm]) > 1 THEN TRY_CONVERT(DECIMAL(18,4), SUBSTRING(nrm.[Norm], CHARINDEX(N':', nrm.[Norm]) + 1, 40)) END AS [Secondary]) p
WHERE f.[P] > 0 AND v.[Raw] <> N'';

DECLARE @notRatio INT = (SELECT COUNT(*) FROM #decl WHERE [RatioNum] IS NULL);

-- 3. what each scheme's devices need, by their commissioned functions
SELECT x.[SchemeEntityId],
       MAX(CONVERT(INT, pf.[NeedsCurrent]))     AS [NeedsCurrent],
       MAX(CONVERT(INT, pf.[NeedsVoltage]))     AS [NeedsVoltage],
       MAX(CONVERT(INT, pf.[NeedsSyncVoltage])) AS [NeedsSync]
INTO #need
FROM #rec x
JOIN [scheme].[vPositionFunction] pf ON pf.[PositionNodeEntityId] = x.[PositionNodeEntityId]
GROUP BY x.[SchemeEntityId];

-- 4. the sets to make
CREATE TABLE #make ([Seq] INT IDENTITY(1,1), [SchemeEntityId] UNIQUEIDENTIFIER, [Name] NVARCHAR(200), [TypeCode] NVARCHAR(40), [Role] NVARCHAR(40),
                    [RatioText] NVARCHAR(40) NULL, [RatioNum] DECIMAL(18,3) NULL, [Phases] INT, [Notes] NVARCHAR(MAX), [SourceKey] NVARCHAR(200),
                    [PanelNodeEntityId] UNIQUEIDENTIFIER NULL, [MigrationRunId] UNIQUEIDENTIFIER, [Step] NVARCHAR(20));
-- 4a. main CT and PT sets, one per distinct ratio per scheme
INSERT #make ([SchemeEntityId], [Name], [TypeCode], [Role], [RatioText], [RatioNum], [Phases], [Notes], [SourceKey], [MigrationRunId], [Step])
SELECT g.[SchemeEntityId],
       g.[SchemeName] + CASE g.[Kind] WHEN N'CT' THEN N' CTs ' ELSE N' PTs ' END + g.[RatioText],
       CASE g.[Kind] WHEN N'CT' THEN N'CT' ELSE N'VT' END,
       CASE g.[Kind] WHEN N'CT' THEN N'CtSource' ELSE N'VtSource' END,
       g.[RatioText], g.[RatioNum], 3,
       N'From the legacy record: ' + g.[Sources],
       LOWER(CONVERT(NVARCHAR(36), g.[SchemeEntityId])) + N'/' + CASE g.[Kind] WHEN N'CT' THEN N'CtSource' ELSE N'VtSource' END + N'/' + g.[RatioText],
       g.[MigrationRunId], N'declared'
FROM (SELECT d.[SchemeEntityId], MIN(d.[SchemeName]) AS [SchemeName], d.[Kind], d.[RatioNum], MIN(d.[Norm]) AS [RatioText], MIN(d.[MigrationRunId]) AS [MigrationRunId],
             STRING_AGG(d.[Key] + N' = ' + d.[Raw] + N' of ' + d.[DeviceName], N'; ') WITHIN GROUP (ORDER BY d.[DeviceName], d.[N]) AS [Sources]
      FROM #decl d WHERE d.[Kind] IN (N'CT', N'PT') AND d.[RatioNum] IS NOT NULL
      GROUP BY d.[SchemeEntityId], d.[Kind], d.[RatioNum]) g;
-- 4b. the functions' floor: a set with the ratio unknown where a device needs the input and no string named one
INSERT #make ([SchemeEntityId], [Name], [TypeCode], [Role], [RatioText], [RatioNum], [Phases], [Notes], [SourceKey], [MigrationRunId], [Step])
SELECT n.[SchemeEntityId], sc.[SchemeName] + N' CTs (ratio unknown)', N'CT', N'CtSource', NULL, NULL, 3,
       N'A relay of this scheme needs current for its functions, and no legacy record names the CT ratio. Record the ratio here.',
       LOWER(CONVERT(NVARCHAR(36), n.[SchemeEntityId])) + N'/CtSource/unknown', sc.[MigrationRunId], N'floor'
FROM #need n
CROSS APPLY (SELECT TOP (1) x.[SchemeName], x.[MigrationRunId] FROM #rec x WHERE x.[SchemeEntityId] = n.[SchemeEntityId] ORDER BY x.[DeviceName]) sc
WHERE n.[NeedsCurrent] = 1 AND NOT EXISTS (SELECT 1 FROM #make m WHERE m.[SchemeEntityId] = n.[SchemeEntityId] AND m.[Role] = N'CtSource');
INSERT #make ([SchemeEntityId], [Name], [TypeCode], [Role], [RatioText], [RatioNum], [Phases], [Notes], [SourceKey], [MigrationRunId], [Step])
SELECT n.[SchemeEntityId], sc.[SchemeName] + N' PTs (ratio unknown)', N'VT', N'VtSource', NULL, NULL, 3,
       N'A relay of this scheme needs voltage for its functions, and no legacy record names the PT ratio. Record the ratio here.',
       LOWER(CONVERT(NVARCHAR(36), n.[SchemeEntityId])) + N'/VtSource/unknown', sc.[MigrationRunId], N'floor'
FROM #need n
CROSS APPLY (SELECT TOP (1) x.[SchemeName], x.[MigrationRunId] FROM #rec x WHERE x.[SchemeEntityId] = n.[SchemeEntityId] ORDER BY x.[DeviceName]) sc
WHERE n.[NeedsVoltage] = 1 AND NOT EXISTS (SELECT 1 FROM #make m WHERE m.[SchemeEntityId] = n.[SchemeEntityId] AND m.[Role] = N'VtSource');
-- 4c. the sync PT: single-phase, feeding the 25's sync input
INSERT #make ([SchemeEntityId], [Name], [TypeCode], [Role], [RatioText], [RatioNum], [Phases], [Notes], [SourceKey], [MigrationRunId], [Step])
SELECT n.[SchemeEntityId], sc.[SchemeName] + N' sync PT', N'VT', N'SyncVtSource', NULL, NULL, 1,
       N'A relay of this scheme has a synchronism-check (25) element, which needs a single-phase voltage for its sync input — the ratio (the relay''s SPTR) is to be recorded; it may be a winding of a second PT set feeding an adjacent protection',
       LOWER(CONVERT(NVARCHAR(36), n.[SchemeEntityId])) + N'/SyncVtSource/sync', sc.[MigrationRunId], N'sync'
FROM #need n
CROSS APPLY (SELECT TOP (1) x.[SchemeName], x.[MigrationRunId] FROM #rec x WHERE x.[SchemeEntityId] = n.[SchemeEntityId] ORDER BY x.[DeviceName]) sc
WHERE n.[NeedsSync] = 1;
-- 4d. the auxiliaries, per device, at its panel
INSERT #make ([SchemeEntityId], [Name], [TypeCode], [Role], [RatioText], [RatioNum], [Phases], [Notes], [SourceKey], [PanelNodeEntityId], [MigrationRunId], [Step])
SELECT d.[SchemeEntityId],
       LEFT(ISNULL(d.[PositionName], d.[DeviceName]), 150) + CASE d.[Kind] WHEN N'CTAUX' THEN N' aux CT ' + CONVERT(NVARCHAR(2), d.[N]) ELSE N' aux PT' END + CASE WHEN d.[RatioNum] IS NOT NULL THEN N' ' + d.[Norm] ELSE N'' END,
       CASE d.[Kind] WHEN N'CTAUX' THEN N'CT_AUX' ELSE N'VT_AUX' END,
       CASE d.[Kind] WHEN N'CTAUX' THEN N'CtSource' ELSE N'VtSource' END,
       CASE WHEN d.[RatioNum] IS NOT NULL THEN d.[Norm] END, d.[RatioNum], 3,
       N'From the legacy record: ' + d.[Key] + N' = ' + d.[Raw] + N' of ' + d.[DeviceName] + N' (auxiliary, at the device''s panel)',
       LOWER(CONVERT(NVARCHAR(36), d.[PositionNodeEntityId])) + N'/aux/' + d.[Key],
       d.[PanelNodeEntityId], d.[MigrationRunId], N'aux'
FROM #decl d
WHERE d.[Kind] IN (N'CTAUX', N'PTAUX') AND d.[PositionNodeEntityId] IS NOT NULL;

-- 5. never a duplicate: the rule's own key, and a live source the scheme already has
DECLARE @already INT, @existing INT;
DELETE m FROM #make m WHERE EXISTS (SELECT 1 FROM [asset].[AlternateKey] k WHERE k.[KeyKindCode] = N'MigrationSource' AND k.[KeyValue] = m.[SourceKey]);
SET @already = @@ROWCOUNT;
DELETE m FROM #make m
WHERE m.[Step] IN (N'declared', N'floor', N'sync')
  AND EXISTS (SELECT 1 FROM [scheme].[vSchemeSource] src
              WHERE src.[SchemeEntityId] = m.[SchemeEntityId] AND src.[MemberRoleCode] = m.[Role]
                AND (m.[RatioNum] IS NULL OR (src.[Ratio] IS NOT NULL AND ABS(src.[Ratio] - m.[RatioNum]) <= 0.005 * m.[RatioNum])));
SET @existing = @@ROWCOUNT;

-- 6. make them
DECLARE @seq INT, @scheme UNIQUEIDENTIFIER, @name NVARCHAR(200), @type NVARCHAR(40), @role NVARCHAR(40), @ratio NVARCHAR(40), @phases INT,
        @notes NVARCHAR(MAX), @key NVARCHAR(200), @panel UNIQUEIDENTIFIER, @run UNIQUEIDENTIFIER, @step NVARCHAR(20), @asset UNIQUEIDENTIFIER;
DECLARE @made TABLE ([Step] NVARCHAR(20), [N] INT);
DECLARE @failed INT = 0, @unplacedAux INT = 0, @rdef UNIQUEIDENTIFIER, @pdef UNIQUEIDENTIFIER, @mnotes NVARCHAR(MAX);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT [Seq], [SchemeEntityId], [Name], [TypeCode], [Role], [RatioText], [Phases], [Notes], [SourceKey], [PanelNodeEntityId], [MigrationRunId], [Step] FROM #make ORDER BY [Seq];
OPEN c; FETCH NEXT FROM c INTO @seq, @scheme, @name, @type, @role, @ratio, @phases, @notes, @key, @panel, @run, @step;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;
        SET @asset = NULL;
        EXEC [asset].[Asset_Add] @AssetTypeCode = @type, @Name = @name, @Status = N'InService', @Notes = @notes, @ActorId = @sys, @MigrationRunId = @run, @EntityId = @asset OUTPUT;
        EXEC [asset].[AlternateKey_Add] @SubjectEntityId = @asset, @KeyKindCode = N'MigrationSource', @KeyValue = @key, @ActorId = @sys, @MigrationRunId = @run;
        IF @ratio IS NOT NULL
        BEGIN
            SET @rdef = CASE WHEN @type IN (N'CT', N'CT_AUX') THEN @ctRatio ELSE @vtRatio END;
            EXEC [asset].[CharacteristicValue_Add] @HostEntityId = @asset, @CharacteristicDefinitionRowId = @rdef, @TextValue = @ratio, @ActorId = @sys, @MigrationRunId = @run;
        END
        SET @pdef = CASE WHEN @type IN (N'CT', N'CT_AUX') THEN @ctPhases ELSE @vtPhases END;
        EXEC [asset].[CharacteristicValue_Add] @HostEntityId = @asset, @CharacteristicDefinitionRowId = @pdef, @IntegerValue = @phases, @ActorId = @sys, @MigrationRunId = @run;
        SET @mnotes = CASE WHEN @step = N'aux' THEN N'auxiliary, brought in from the legacy record' ELSE N'brought in from the legacy record' END;
        EXEC [scheme].[AddSchemeMember] @SchemeEntityId = @scheme, @MemberKind = N'Asset', @MemberEntityId = @asset, @MemberRoleCode = @role, @IsInService = 1,
             @Notes = @mnotes, @ActorId = @sys, @MigrationRunId = @run;
        COMMIT TRANSACTION;
        INSERT @made VALUES (@step, 1);
        -- an auxiliary stands at the device's panel when the panel is a current Panel node (a panel holds every auxiliary mounted
        -- on it, #206 SharesNode). Checked here, never thrown: the publish runs its post-deploy in one transaction and a THROW
        -- under XACT_ABORT would doom all of it.
        IF @panel IS NOT NULL
        BEGIN
            IF EXISTS (SELECT 1 FROM [location].[Node] pn WHERE pn.[EntityId] = @panel AND pn.[NodeTypeCode] = N'Panel' AND pn.[ValidTo] IS NULL AND pn.[IsDeleted] = 0)
                EXEC [asset].[PlaceAsset] @AssetEntityId = @asset, @NodeEntityId = @panel, @PlacementKind = N'Installed', @ActorId = @sys, @MigrationRunId = @run;
            ELSE
                SET @unplacedAux += 1;
        END
    END TRY
    BEGIN CATCH
        -- never reached when the pre-checks hold; a failure here under the publish's transaction ends the publish, which is the honest outcome
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @failed += 1;
        PRINT N'#206: could not make ' + @name + N': ' + ERROR_MESSAGE();
    END CATCH
    FETCH NEXT FROM c INTO @seq, @scheme, @name, @type, @role, @ratio, @phases, @notes, @key, @panel, @run, @step;
END
CLOSE c; DEALLOCATE c;

-- 7. the auxiliaries this rule made and left unplaced (the first run refused a second on a panel) stand at their panel now
DECLARE @placedLater INT = 0;
DECLARE @aAsset UNIQUEIDENTIFIER, @aPanel UNIQUEIDENTIFIER, @aRun UNIQUEIDENTIFIER;
DECLARE c7 CURSOR LOCAL FAST_FORWARD FOR
    SELECT a.[EntityId], x.[PanelNodeEntityId], a.[MigrationRunId]
    FROM [asset].[AlternateKey] k
    JOIN [asset].[Asset] a ON a.[EntityId] = k.[SubjectEntityId] AND a.[ValidTo] IS NULL AND a.[IsDeleted] = 0 AND a.[AssetTypeCode] IN (N'CT_AUX', N'VT_AUX')
    CROSS APPLY (SELECT TOP (1) r.[PanelNodeEntityId] FROM #rec r WHERE LOWER(CONVERT(NVARCHAR(36), r.[PositionNodeEntityId])) = LEFT(k.[KeyValue], 36) AND r.[PanelNodeEntityId] IS NOT NULL) x
    WHERE k.[KeyKindCode] = N'MigrationSource' AND k.[KeyValue] LIKE N'%/aux/%' AND k.[IsDeleted] = 0
      AND NOT EXISTS (SELECT 1 FROM [asset].[Placement] p WHERE p.[AssetEntityId] = a.[EntityId] AND p.[ValidTo] IS NULL AND p.[IsDeleted] = 0)
      AND EXISTS (SELECT 1 FROM [location].[Node] pn WHERE pn.[EntityId] = x.[PanelNodeEntityId] AND pn.[NodeTypeCode] = N'Panel' AND pn.[ValidTo] IS NULL AND pn.[IsDeleted] = 0);
OPEN c7; FETCH NEXT FROM c7 INTO @aAsset, @aPanel, @aRun;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC [asset].[PlaceAsset] @AssetEntityId = @aAsset, @NodeEntityId = @aPanel, @PlacementKind = N'Installed', @ActorId = @sys, @MigrationRunId = @aRun;
    SET @placedLater += 1;
    FETCH NEXT FROM c7 INTO @aAsset, @aPanel, @aRun;
END
CLOSE c7; DEALLOCATE c7;

DECLARE @nDecl INT, @nFloor INT, @nSync INT, @nAux INT;
SELECT @nDecl = ISNULL(SUM(CASE WHEN [Step] = N'declared' THEN [N] END), 0), @nFloor = ISNULL(SUM(CASE WHEN [Step] = N'floor' THEN [N] END), 0),
       @nSync = ISNULL(SUM(CASE WHEN [Step] = N'sync' THEN [N] END), 0), @nAux = ISNULL(SUM(CASE WHEN [Step] = N'aux' THEN [N] END), 0) FROM @made;
DECLARE @report NVARCHAR(1000) = N'#206: instrument transformers from the legacy record — declared sets ' + CONVERT(NVARCHAR(10), @nDecl)
    + N', functions'' floor sets ' + CONVERT(NVARCHAR(10), @nFloor) + N', sync PTs ' + CONVERT(NVARCHAR(10), @nSync)
    + N', auxiliaries ' + CONVERT(NVARCHAR(10), @nAux) + N' (unplaced ' + CONVERT(NVARCHAR(10), @unplacedAux) + N')'
    + N'; skipped: already made ' + CONVERT(NVARCHAR(10), @already) + N', the scheme already had the source ' + CONVERT(NVARCHAR(10), @existing)
    + N', declared values that are not a ratio ' + CONVERT(NVARCHAR(10), @notRatio) + N'; failed ' + CONVERT(NVARCHAR(10), @failed) + N'; auxiliaries placed later ' + CONVERT(NVARCHAR(10), @placedLater);
PRINT @report;
DROP TABLE #rec; DROP TABLE #decl; DROP TABLE #need; DROP TABLE #make;
GO
-- migration-rule: #221 the notes these rows carry are read on the Analog inputs tab, so they are written in the words a P&C
-- person would use (docs/design/UI-WORDING.md): no decision number on a screen. Rows made before this correction are brought
-- into line here, by their text, so a re-run and the cutover both end in the same place.
UPDATE m SET m.[Notes] = N'brought in from the legacy record', m.[ModifiedAt] = SYSDATETIMEOFFSET()
  FROM [scheme].[SchemeMember] m WHERE m.[Notes] = N'made by the migration rule (#206)' AND m.[IsDeleted] = 0 AND m.[ValidTo] IS NULL;
UPDATE m SET m.[Notes] = N'auxiliary, brought in from the legacy record', m.[ModifiedAt] = SYSDATETIMEOFFSET()
  FROM [scheme].[SchemeMember] m WHERE m.[Notes] = N'auxiliary (#206)' AND m.[IsDeleted] = 0 AND m.[ValidTo] IS NULL;
UPDATE a SET a.[Notes] = REPLACE(a.[Notes], N'#206: from the legacy record — ', N'From the legacy record: '), a.[ModifiedAt] = SYSDATETIMEOFFSET()
  FROM [asset].[Asset] a WHERE a.[Notes] LIKE N'#206: from the legacy record — %' AND a.[IsDeleted] = 0 AND a.[ValidTo] IS NULL;
UPDATE a SET a.[Notes] = N'A relay of this scheme needs current for its functions, and no legacy record names the CT ratio. Record the ratio here.', a.[ModifiedAt] = SYSDATETIMEOFFSET()
  FROM [asset].[Asset] a WHERE a.[Notes] LIKE N'#206: a device of the scheme needs current%' AND a.[IsDeleted] = 0 AND a.[ValidTo] IS NULL;
UPDATE a SET a.[Notes] = N'A relay of this scheme needs voltage for its functions, and no legacy record names the PT ratio. Record the ratio here.', a.[ModifiedAt] = SYSDATETIMEOFFSET()
  FROM [asset].[Asset] a WHERE a.[Notes] LIKE N'#206: a device of the scheme needs voltage%' AND a.[IsDeleted] = 0 AND a.[ValidTo] IS NULL;
UPDATE a SET a.[Notes] = REPLACE(a.[Notes], N'#206: a device of the scheme has a synchronism-check', N'A relay of this scheme has a synchronism-check'), a.[ModifiedAt] = SYSDATETIMEOFFSET()
  FROM [asset].[Asset] a WHERE a.[Notes] LIKE N'#206: a device of the scheme has a synchronism-check%' AND a.[IsDeleted] = 0 AND a.[ValidTo] IS NULL;
GO
