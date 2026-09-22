-- PLATFORM-ARCHITECTURE decision 237; SCHEMA-DESIGN §11.3 (154). The only role → permission mappings the vision's
-- role descriptions imply: the Administrator "configures workflows, formulas, compliance rules, templates and
-- reporting" and administers access (every permission); Read-only reads (every <Class>.Read). Every other role's
-- permissions are the Administrator's to assign (owner, 2026-09-06: no other defaults seeded). Idempotent.
IF OBJECT_ID(N'[security].[RolePermission_Upsert]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @code NVARCHAR(80);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT [PermissionCode] FROM [security].[Permission] WHERE [IsActive] = 1;
OPEN c; FETCH NEXT FROM c INTO @code;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM [security].[RolePermission] WHERE [RoleCode] = N'Administrator' AND [PermissionCode] = @code)
        EXEC [security].[RolePermission_Upsert] @RoleCode = N'Administrator', @PermissionCode = @code, @ActorId = @actor;
    IF @code LIKE N'%.Read' AND NOT EXISTS (SELECT 1 FROM [security].[RolePermission] WHERE [RoleCode] = N'ReadOnly' AND [PermissionCode] = @code)
        EXEC [security].[RolePermission_Upsert] @RoleCode = N'ReadOnly', @PermissionCode = @code, @ActorId = @actor;
    FETCH NEXT FROM c INTO @code;
END
CLOSE c; DEALLOCATE c;
GO
-- V2 W2 (decision #66; docs/design/IDENTITY.md §3, the matrix put to the owner on the W2 card). Idempotent upserts;
-- Archive and Administer stay the Administrator's everywhere; Grant.* is the Administrator's alone.
DECLARE @a UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @m TABLE ([RoleCode] NVARCHAR(40), [PermissionCode] NVARCHAR(80));
INSERT @m
SELECT r.[RoleCode], c.[SubjectClass] + N'.' + v.[Verb]
FROM (VALUES (N'PCEngineer'), (N'PCApprover'), (N'PCTechnician')) r ([RoleCode])
CROSS JOIN (VALUES (N'Node'), (N'Asset'), (N'Device'), (N'Scheme'), (N'Connection'), (N'ConfigurationFile'), (N'Document'),
                   (N'WorkRequest'), (N'Record'), (N'Obligation'), (N'Definition')) c ([SubjectClass])
CROSS JOIN (VALUES (N'Read'), (N'Modify'), (N'Approve'), (N'Report')) v ([Verb])
WHERE v.[Verb] = N'Read'
   OR (r.[RoleCode] = N'PCEngineer'   AND v.[Verb] IN (N'Modify', N'Report') AND c.[SubjectClass] NOT IN (N'Definition', N'Obligation'))
   OR (r.[RoleCode] = N'PCEngineer'   AND v.[Verb] = N'Report'  AND c.[SubjectClass] = N'Obligation')
   OR (r.[RoleCode] = N'PCEngineer'   AND v.[Verb] IN (N'Modify', N'Approve') AND c.[SubjectClass] = N'Definition')   -- W5 card F (#126): engineers author and approve procedures; segregation still needs a second person
   OR (r.[RoleCode] = N'PCApprover'   AND v.[Verb] = N'Approve' AND c.[SubjectClass] IN (N'ConfigurationFile', N'Document', N'WorkRequest', N'Record'))
   OR (r.[RoleCode] = N'PCTechnician' AND v.[Verb] = N'Modify'  AND c.[SubjectClass] IN (N'ConfigurationFile', N'WorkRequest', N'Record'));
DECLARE @r NVARCHAR(40), @p NVARCHAR(80);
DECLARE m CURSOR LOCAL FAST_FORWARD FOR SELECT [RoleCode], [PermissionCode] FROM @m;
OPEN m; FETCH NEXT FROM m INTO @r, @p;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF EXISTS (SELECT 1 FROM [security].[Permission] WHERE [PermissionCode] = @p AND [IsActive] = 1)
       AND NOT EXISTS (SELECT 1 FROM [security].[RolePermission] WHERE [RoleCode] = @r AND [PermissionCode] = @p)   -- any row, active or not: a deactivated mapping is an Administrator's decision and survives a deploy (#96)
        EXEC [security].[RolePermission_Upsert] @RoleCode = @r, @PermissionCode = @p, @ActorId = @a;
    FETCH NEXT FROM m INTO @r, @p;
END
CLOSE m; DEALLOCATE m;
GO

-- #226: what a person shows or hides on a screen is theirs. Every active role reads the catalogue of screen items, and
-- every role but ReadOnly sets its own answers — config.SetViewItem writes only the calling person's row, so this gives
-- nobody sight of another person's work. ReadOnly is left out of the Modify: decision 237 says it only reads, and the
-- schema smoke holds the seed to that (a person's view row is still a write). ViewItem.Administer, which edits a role's
-- starting shape, stays the Administrator's (seeded above).
DECLARE @va UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @vr NVARCHAR(40), @vp NVARCHAR(80);
DECLARE v CURSOR LOCAL FAST_FORWARD FOR
    SELECT r.[RoleCode], p.[PermissionCode]
    FROM [security].[Role] r
    CROSS JOIN (VALUES (N'ViewItem.Read'), (N'ViewItem.Modify')) p ([PermissionCode])
    WHERE r.[IsActive] = 1 AND NOT (r.[RoleCode] = N'ReadOnly' AND p.[PermissionCode] <> N'ViewItem.Read');
OPEN v; FETCH NEXT FROM v INTO @vr, @vp;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF EXISTS (SELECT 1 FROM [security].[Permission] WHERE [PermissionCode] = @vp AND [IsActive] = 1)
       AND NOT EXISTS (SELECT 1 FROM [security].[RolePermission] WHERE [RoleCode] = @vr AND [PermissionCode] = @vp)
        EXEC [security].[RolePermission_Upsert] @RoleCode = @vr, @PermissionCode = @vp, @ActorId = @va;
    FETCH NEXT FROM v INTO @vr, @vp;
END
CLOSE v; DEALLOCATE v;
GO
