-- docs/design/IDENTITY.md §5 (W2). Does the user hold @permissionCode at @at through any grant or delegation in force,
-- in ANY scope? The question a LIST read asks before its rows are scoped one by one by security.fReadableSubjects:
-- a scoped engineer may list assets (and see only those in scope); a person with no such role may not list at all.
-- fHasPermission answers the same question for one subject; with a null subject it is Global-only by design, which
-- is right for a single read and wrong for a list whose rows the function filters. Same role gathering as there.
CREATE FUNCTION [security].[fHoldsPermission]
    (@userEntityId UNIQUEIDENTIFIER, @permissionCode NVARCHAR(80), @at DATETIMEOFFSET(7))
RETURNS BIT
AS
BEGIN
    IF @userEntityId IS NULL OR @permissionCode IS NULL RETURN 0;
    DECLARE @nowUtc DATETIME2(7) = SYSUTCDATETIME();
    DECLARE @person UNIQUEIDENTIFIER = (SELECT TOP (1) [PersonEntityId] FROM [security].[User] WHERE [EntityId] = @userEntityId AND [IsDeleted] = 0 AND [IsEnabled] = 1 AND [ValidTo] IS NULL);
    IF @person IS NULL RETURN 0;
    IF EXISTS (
        SELECT 1 FROM [security].[fGrantAsOf](@at, @nowUtc) g
        JOIN [security].[RolePermission] rp ON rp.[RoleCode] = g.[RoleCode] AND rp.[PermissionCode] = @permissionCode AND rp.[IsActive] = 1
        WHERE g.[RevokedByActorId] IS NULL
          AND ((g.[GranteeKind] = N'User' AND g.[GranteeEntityId] = @userEntityId)
            OR (g.[GranteeKind] = N'Group' AND EXISTS (SELECT 1 FROM [security].[GroupMember] gm
                                                       WHERE gm.[GroupEntityId] = g.[GranteeEntityId] AND gm.[UserEntityId] = @userEntityId AND gm.[IsDeleted] = 0
                                                         AND gm.[ValidFrom] <= @at AND (gm.[ValidTo] IS NULL OR gm.[ValidTo] > @at))))
    ) RETURN 1;
    IF EXISTS (
        SELECT 1 FROM [security].[fDelegationAsOf](@at, @nowUtc) d
        JOIN [security].[RolePermission] rp ON rp.[RoleCode] = d.[RoleCode] AND rp.[PermissionCode] = @permissionCode AND rp.[IsActive] = 1
        WHERE d.[ToPersonEntityId] = @person AND d.[RevokedByActorId] IS NULL AND d.[StartsAt] <= @at AND (d.[EndsAt] IS NULL OR d.[EndsAt] > @at)
    ) RETURN 1;
    RETURN 0;
END;
GO
GRANT EXECUTE ON [security].[fHoldsPermission] TO [app_execute];
GO
