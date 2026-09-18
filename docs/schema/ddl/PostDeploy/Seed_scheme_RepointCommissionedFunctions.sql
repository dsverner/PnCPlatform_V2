-- #181 (2026-09-17): the commissioned functions move from the protection-function NODE to the device POSITION, and the
-- nodes are retired. The owner, asked whether to leave them or repoint them: "repoint them".
--
-- Why. The importer made one ProtectionFunction node per parenthesised fragment of the legacy FUNCTIONS text, so the
-- node's name is a copy of the designation already inside the position's own name (position 'CARRIER KEYING INTERLOCK
-- (85TY-1)' holding a node named '85TY-1'), and 2 886 of the 2 950 positions that hold one hold exactly one. The layer
-- carries nothing the position does not. What IS worth keeping is scheme.CommissionedFunction -- which element is
-- enabled here -- and that reads better hanging off the position: one row per element per position, which is exactly
-- the checklist the owner asked for.
--
-- Checked on DEV before writing this, 2026-09-17:
--   * repointing produces 3 103 distinct (position, AnsiCode) pairs from 3 103 rows -- ZERO collisions, so the unique
--     index UX_CommissionedFunction cannot be breached;
--   * of the 3 103 scheme members that name a protection-function node, 3 007 are redundant because the relay standing
--     at that position is ALREADY an Asset member of the same scheme. The 96 that are not are every one of them a
--     smoke fixture, so no real scheme loses a member by withdrawing them.
--
-- CommissionedFunction.ProtectionFunctionNodeEntityId is a plain location.NodeRegistry reference with no constraint
-- forcing a ProtectionFunction node, so pointing it at the position needs no schema change -- the same situation #174
-- recorded for asset.AssetTerminal.StationNodeEntityId. The column keeps its name: renaming a column on a
-- system-versioned table has no precedent here and the honest read is scheme.vPositionFunction.
--
-- Idempotent: each step matches only rows still in the old shape, so a second publish changes nothing.
IF OBJECT_ID(N'[scheme].[CommissionedFunction]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @sys UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();

-- 1. the commissioned functions point at the position the element is performed at
UPDATE cf
SET [ProtectionFunctionNodeEntityId] = fn.[ParentEntityId],
    [ModifiedBy] = @sys, [ModifiedAt] = @now
FROM [scheme].[CommissionedFunction] cf
JOIN [location].[Node] fn ON fn.[EntityId] = cf.[ProtectionFunctionNodeEntityId]
                         AND fn.[ValidTo] IS NULL AND fn.[IsDeleted] = 0
                         AND fn.[NodeTypeCode] = N'ProtectionFunction'
JOIN [location].[Node] pos ON pos.[EntityId] = fn.[ParentEntityId]
                          AND pos.[ValidTo] IS NULL AND pos.[IsDeleted] = 0
WHERE cf.[ValidTo] IS NULL AND cf.[IsDeleted] = 0
  -- never create a duplicate (position, AnsiCode): there are none today, and this keeps that true if one ever appears
  AND NOT EXISTS (SELECT 1 FROM [scheme].[CommissionedFunction] other
                  WHERE other.[ValidTo] IS NULL AND other.[IsDeleted] = 0
                    AND other.[ProtectionFunctionNodeEntityId] = fn.[ParentEntityId]
                    AND other.[AnsiCode] = cf.[AnsiCode]);
GO

-- 2. a scheme member naming a protection-function node is withdrawn where the relay at that position is already an
--    Asset member of the same scheme, which is every migrated one
DECLARE @sys2 UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now2 DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
UPDATE sm
SET [IsDeleted] = 1, [DeletedBy] = @sys2, [DeletedAt] = @now2, [ModifiedBy] = @sys2, [ModifiedAt] = @now2
FROM [scheme].[SchemeMember] sm
JOIN [location].[Node] fn ON fn.[EntityId] = sm.[MemberEntityId]
                         AND fn.[ValidTo] IS NULL AND fn.[IsDeleted] = 0
                         AND fn.[NodeTypeCode] = N'ProtectionFunction'
WHERE sm.[ValidTo] IS NULL AND sm.[IsDeleted] = 0 AND sm.[MemberKind] = N'ProtectionFunction'
  AND EXISTS (SELECT 1
              FROM [asset].[Placement] p
              JOIN [scheme].[SchemeMember] am ON am.[ValidTo] IS NULL AND am.[IsDeleted] = 0
                                             AND am.[SchemeEntityId] = sm.[SchemeEntityId]
                                             AND am.[MemberKind] = N'Asset'
                                             AND am.[MemberEntityId] = p.[AssetEntityId]
              WHERE p.[ValidTo] IS NULL AND p.[IsDeleted] = 0 AND p.[NodeEntityId] = fn.[ParentEntityId]);
GO

-- 3. a protection-function node that nothing names any more is retired. A node still named by a scheme member is left
--    standing: a soft delete must never orphan a row that points at it.
DECLARE @sys3 UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now3 DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
UPDATE n
SET [IsDeleted] = 1, [DeletedBy] = @sys3, [DeletedAt] = @now3, [ModifiedBy] = @sys3, [ModifiedAt] = @now3
FROM [location].[Node] n
WHERE n.[ValidTo] IS NULL AND n.[IsDeleted] = 0 AND n.[NodeTypeCode] = N'ProtectionFunction'
  AND NOT EXISTS (SELECT 1 FROM [scheme].[SchemeMember] sm
                  WHERE sm.[ValidTo] IS NULL AND sm.[IsDeleted] = 0
                    AND sm.[MemberKind] = N'ProtectionFunction' AND sm.[MemberEntityId] = n.[EntityId])
  AND NOT EXISTS (SELECT 1 FROM [scheme].[CommissionedFunction] cf
                  WHERE cf.[ValidTo] IS NULL AND cf.[IsDeleted] = 0
                    AND cf.[ProtectionFunctionNodeEntityId] = n.[EntityId])
  AND NOT EXISTS (SELECT 1 FROM [location].[Node] kid
                  WHERE kid.[ValidTo] IS NULL AND kid.[IsDeleted] = 0 AND kid.[ParentEntityId] = n.[EntityId]);
GO
