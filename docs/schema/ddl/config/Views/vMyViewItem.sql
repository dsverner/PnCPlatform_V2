-- Decision #226 (2026-09-22). What the person at this session sees, one row per part of every screen, already resolved.
--
-- Three layers, each overriding the one before:
--   1. the screen's own default (config.ViewItem.ShownByDefault)
--   2. the default for each role the person holds — the widest wins, so a second role never takes anything away
--   3. the person's own choice, which nobody else can set or see
-- Source says which layer answered, so the screen can offer "back to my roles' default" only when there is one to go
-- back to. An item marked IsAlways is shown whatever the layers say: it is the screen's reason for being.
CREATE VIEW [config].[vMyViewItem] AS
WITH [me] AS (
    SELECT TOP (1) u.[EntityId], u.[PersonEntityId]
    FROM [security].[User] u
    WHERE u.[UserPrincipalName] = TRY_CONVERT(NVARCHAR(200), SESSION_CONTEXT(N'UserPrincipalName'))
      AND u.[IsEnabled] = 1 AND u.[IsDeleted] = 0
      AND u.[ValidFrom] <= SYSDATETIMEOFFSET() AND (u.[ValidTo] IS NULL OR u.[ValidTo] > SYSDATETIMEOFFSET())
    ORDER BY u.[ValidFrom] DESC, u.[RowSeq] DESC
),
[myroles] AS (
    SELECT DISTINCT g.[RoleCode]
    FROM [security].[fGrantAsOf](SYSDATETIMEOFFSET(), SYSUTCDATETIME()) g
    JOIN [me] ON g.[GranteeKind] = N'User' AND g.[GranteeEntityId] = [me].[EntityId]
    WHERE g.[RevokedByActorId] IS NULL AND g.[IsDeleted] = 0
    UNION
    SELECT DISTINCT d.[RoleCode]
    FROM [security].[fDelegationAsOf](SYSDATETIMEOFFSET(), SYSUTCDATETIME()) d
    JOIN [me] ON d.[ToPersonEntityId] = [me].[PersonEntityId]
    WHERE d.[RevokedByActorId] IS NULL AND d.[IsDeleted] = 0
      AND d.[StartsAt] <= SYSDATETIMEOFFSET() AND (d.[EndsAt] IS NULL OR d.[EndsAt] > SYSDATETIMEOFFSET())
)
SELECT i.[ScreenKey], i.[ItemKey], i.[Name], i.[Description], i.[ItemKind], i.[DisplayOrder], i.[IsAlways],
       i.[ShownByDefault],
       CONVERT(BIT, CASE WHEN i.[IsAlways] = 1 THEN 1
                         WHEN [mine].[IsShown] IS NOT NULL THEN [mine].[IsShown]
                         WHEN [role].[AnyShown] IS NOT NULL THEN [role].[AnyShown]
                         ELSE i.[ShownByDefault] END) AS [IsShown],
       CONVERT(NVARCHAR(10), CASE WHEN [mine].[IsShown] IS NOT NULL THEN N'mine'
                                  WHEN [role].[AnyShown] IS NOT NULL THEN N'role'
                                  ELSE N'screen' END) AS [Source]
FROM [config].[ViewItem] i
OUTER APPLY (SELECT TOP (1) uvi.[IsShown]
             FROM [config].[UserViewItem] uvi
             JOIN [me] ON uvi.[UserEntityId] = [me].[EntityId]
             WHERE uvi.[ScreenKey] = i.[ScreenKey] AND uvi.[ItemKey] = i.[ItemKey]
               AND uvi.[ValidFrom] <= SYSDATETIMEOFFSET() AND uvi.[ValidTo] IS NULL AND uvi.[IsDeleted] = 0
             ORDER BY uvi.[RowSeq] DESC) AS [mine]
OUTER APPLY (SELECT MAX(CONVERT(TINYINT, rvi.[IsShown])) AS [AnyShown]
             FROM [config].[RoleViewItem] rvi
             JOIN [myroles] ON rvi.[RoleCode] = [myroles].[RoleCode]
             WHERE rvi.[ScreenKey] = i.[ScreenKey] AND rvi.[ItemKey] = i.[ItemKey] AND rvi.[IsActive] = 1) AS [role]
WHERE i.[IsActive] = 1;
GO
GRANT SELECT ON [config].[vMyViewItem] TO [app_execute];
GO
