-- #212 (2026-09-20): every instrument transformer has at least one secondary winding, and every source membership names the
-- migration-rule: #212 every instrument transformer without a winding gets S1 (Protection) carrying its RatioInUse characteristic when it has one; every scheme source membership without a winding gets its transformer's lowest-numbered winding; idempotent
-- winding it uses. The transformers made before windings existed (#206's rule, the hand-made and the smoke's) carry the
-- ratio as a nameplate characteristic (RatioInUse) — the owner: the winding "is a physical thing that needs to have a first
-- class place in the database" — so each gets winding S1 (Purpose Protection) with that ratio, and each membership without a
-- winding gets its transformer's lowest-numbered one. Replayed on every deploy; changes nothing the second time. Written
-- as the system actor with the transformer's MigrationRunId, so a rule-made winding is marked as migrated data.
IF OBJECT_ID(N'[asset].[InstrumentWinding_Add]') IS NULL OR COL_LENGTH(N'[scheme].[SchemeMember]', N'WindingEntityId') IS NULL RETURN;   -- the deploy that made the table; its procedures come with the next
GO
SET NOCOUNT ON;
DECLARE @sys UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';

-- 1. S1 for every instrument transformer that has no winding, with its RatioInUse characteristic when it has one
DECLARE @asset UNIQUEIDENTIFIER, @ratio NVARCHAR(40), @run UNIQUEIDENTIFIER, @w UNIQUEIDENTIFIER, @made INT = 0, @assigned INT = 0;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT a.[EntityId], ru.[TextValue], a.[MigrationRunId]
    FROM [asset].[Asset] a
    JOIN [ref].[AssetType] t ON t.[AssetTypeCode] = a.[AssetTypeCode] AND t.[AssetTypeCode] IN (N'CT', N'VT', N'CT_AUX', N'VT_AUX', N'COUPLING_CAPACITOR_VT', N'CCPD', N'METERING_UNIT')
    OUTER APPLY (SELECT TOP (1) cv.[TextValue] FROM [asset].[CharacteristicValue] cv
                 JOIN [config].[CharacteristicDefinition] cd ON cd.[RowId] = cv.[CharacteristicDefinitionRowId] AND cd.[CharacteristicKey] = N'RatioInUse'
                 WHERE cv.[HostEntityId] = a.[EntityId] AND cv.[ValidTo] IS NULL AND cv.[IsDeleted] = 0 ORDER BY cv.[RowSeq] DESC) ru
    WHERE a.[ValidTo] IS NULL AND a.[IsDeleted] = 0
      AND NOT EXISTS (SELECT 1 FROM [asset].[InstrumentWinding] w WHERE w.[AssetEntityId] = a.[EntityId] AND w.[ValidTo] IS NULL AND w.[IsDeleted] = 0);
OPEN c; FETCH NEXT FROM c INTO @asset, @ratio, @run;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @w = NULL;
    EXEC [asset].[InstrumentWinding_Add] @AssetEntityId = @asset, @WindingNo = 1, @Code = N'S1', @Purpose = N'Protection', @RatioInUse = @ratio,
         @Notes = N'#212: the first winding, made from the transformer''s recorded ratio; the nameplate''s others are to be added', @ActorId = @sys, @MigrationRunId = @run, @EntityId = @w OUTPUT;
    SET @made += 1;
    FETCH NEXT FROM c INTO @asset, @ratio, @run;
END
CLOSE c; DEALLOCATE c;

-- 2. every source membership without a winding uses its transformer's lowest-numbered winding
UPDATE sm SET [WindingEntityId] = w.[EntityId], [ModifiedBy] = @sys, [ModifiedAt] = SYSDATETIMEOFFSET()
FROM [scheme].[SchemeMember] sm
CROSS APPLY (SELECT TOP (1) iw.[EntityId] FROM [asset].[InstrumentWinding] iw
             WHERE iw.[AssetEntityId] = sm.[MemberEntityId] AND iw.[ValidTo] IS NULL AND iw.[IsDeleted] = 0 ORDER BY iw.[WindingNo]) w
WHERE sm.[MemberKind] = N'Asset' AND sm.[MemberRoleCode] IN (N'CtSource', N'VtSource', N'SyncVtSource')
  AND sm.[WindingEntityId] IS NULL AND sm.[ValidTo] IS NULL AND sm.[IsDeleted] = 0;
SET @assigned = @@ROWCOUNT;
DECLARE @report NVARCHAR(400) = N'#212: windings made ' + CONVERT(NVARCHAR(10), @made) + N', memberships given a winding ' + CONVERT(NVARCHAR(10), @assigned);
PRINT @report;
GO
