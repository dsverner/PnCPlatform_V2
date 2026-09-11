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
