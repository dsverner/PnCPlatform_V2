-- docs/design/IDENTITY.md §5 (W2, decision D). Read scope is as strict as write scope (FR-6.2, #66; PnCPlatform #59):
-- the set of subjects of one kind the user may read at @at, computed forwards from the same grants
-- security.fHasPermission walks backwards. The API joins a list read to this set; the rule stays here.
--
--   @subjectKind is a FAMILY: Node (every location node kind), Asset (every asset kind), Record, WorkRequest, Scheme.
--   Kinds with no node mapping (Definition, Document, Obligation, Grant, Platform) are decided on the class by
--   fHasPermission and are not served here.
--
--   Global                → every registered subject of the family
--   NodeSubtree           → nodes under the scope node's Path; assets placed under them (asset-class and
--                           device-category filters as fHasPermission applies them); records and work requests
--                           whose subject is one of those; schemes with such a member
--   WorkRequest           → that request, and records scoped to it
--   OwnershipRelation     → assets and nodes the scope entity owns in the scope role, and records/requests on them
CREATE FUNCTION [security].[fReadableSubjects]
    (@userEntityId UNIQUEIDENTIFIER, @permissionCode NVARCHAR(80), @subjectKind NVARCHAR(40), @at DATETIMEOFFSET(7))
RETURNS TABLE
AS RETURN
WITH person AS (
    SELECT TOP (1) [PersonEntityId] FROM [security].[User]
    WHERE [EntityId] = @userEntityId AND [IsDeleted] = 0 AND [IsEnabled] = 1 AND [ValidTo] IS NULL
),
roles AS (
    SELECT g.[RoleCode], g.[ScopeKind], g.[ScopeNodeEntityId], g.[ScopeAssetClassCode], g.[ScopeDeviceCategory],
           g.[ScopeWorkRequestEntityId], g.[ScopeEntityEntityId], g.[ScopeOwnershipRole]
    FROM [security].[fGrantAsOf](@at, SYSUTCDATETIME()) g
    WHERE g.[RevokedByActorId] IS NULL
      AND ((g.[GranteeKind] = N'User' AND g.[GranteeEntityId] = @userEntityId)
        OR (g.[GranteeKind] = N'Group' AND EXISTS (SELECT 1 FROM [security].[GroupMember] gm
                                                   WHERE gm.[GroupEntityId] = g.[GranteeEntityId] AND gm.[UserEntityId] = @userEntityId AND gm.[IsDeleted] = 0
                                                     AND gm.[ValidFrom] <= @at AND (gm.[ValidTo] IS NULL OR gm.[ValidTo] > @at))))
    UNION ALL
    SELECT d.[RoleCode], N'Global', NULL, NULL, NULL, NULL, NULL, NULL
    FROM [security].[fDelegationAsOf](@at, SYSUTCDATETIME()) d
    CROSS JOIN person p
    WHERE d.[ToPersonEntityId] = p.[PersonEntityId] AND d.[RevokedByActorId] IS NULL AND d.[StartsAt] <= @at AND (d.[EndsAt] IS NULL OR d.[EndsAt] > @at)
),
held AS (
    SELECT r.* FROM roles r
    WHERE EXISTS (SELECT 1 FROM [security].[RolePermission] rp WHERE rp.[RoleCode] = r.[RoleCode] AND rp.[PermissionCode] = @permissionCode AND rp.[IsActive] = 1)
),
is_global AS (SELECT TOP (1) 1 AS g FROM held WHERE [ScopeKind] = N'Global'),
-- nodes under NodeSubtree scopes
scope_nodes AS (
    SELECT DISTINCT n.[EntityId], r.[ScopeAssetClassCode], r.[ScopeDeviceCategory]
    FROM held r
    JOIN [location].[Node] sn ON sn.[EntityId] = r.[ScopeNodeEntityId] AND sn.[IsDeleted] = 0 AND sn.[ValidTo] IS NULL
    -- "under sn": sn itself, or a Path that continues with sn's own id (a node's Path holds its ancestors only)
    JOIN [location].[Node] n ON n.[IsDeleted] = 0 AND n.[ValidTo] IS NULL AND (n.[EntityId] = sn.[EntityId] OR n.[Path] LIKE sn.[Path] + CONVERT(NVARCHAR(36), sn.[EntityId]) + N'/%')
    WHERE r.[ScopeKind] = N'NodeSubtree'
),
-- assets placed under those nodes, with the grant's filters
scope_assets AS (
    SELECT DISTINCT pl.[AssetEntityId]
    FROM scope_nodes sn
    JOIN [asset].[Placement] pl ON pl.[NodeEntityId] = sn.[EntityId] AND pl.[IsDeleted] = 0 AND pl.[ValidFrom] <= @at AND (pl.[ValidTo] IS NULL OR pl.[ValidTo] > @at)
    WHERE (sn.[ScopeAssetClassCode] IS NULL OR EXISTS (
              SELECT 1 FROM [asset].[Asset] a JOIN [ref].[AssetType] t ON t.[AssetTypeCode] = a.[AssetTypeCode]
              WHERE a.[EntityId] = pl.[AssetEntityId] AND a.[IsDeleted] = 0 AND a.[ValidTo] IS NULL AND t.[AssetClassCode] = sn.[ScopeAssetClassCode]))
      AND (sn.[ScopeDeviceCategory] IS NULL OR EXISTS (
              SELECT 1 FROM [asset].[Asset] a JOIN [ref].[Model] m ON m.[ModelId] = a.[ModelId]
              WHERE a.[EntityId] = pl.[AssetEntityId] AND a.[IsDeleted] = 0 AND a.[ValidTo] IS NULL AND m.[DeviceCategory] = sn.[ScopeDeviceCategory]))
),
-- assets and nodes the scope entity owns in the scope role
owned AS (
    SELECT DISTINCT o.[SubjectEntityId]
    FROM held r
    JOIN [asset].[OwnershipLink] o ON o.[EntityEntityId] = r.[ScopeEntityEntityId] AND o.[OwnershipRole] = r.[ScopeOwnershipRole]
         AND o.[IsDeleted] = 0 AND o.[ValidFrom] <= @at AND (o.[ValidTo] IS NULL OR o.[ValidTo] > @at)
    WHERE r.[ScopeKind] = N'OwnershipRelation'
),
readable_nodes AS (
    SELECT [EntityId] FROM [location].[NodeRegistry] WHERE EXISTS (SELECT 1 FROM is_global)
    UNION SELECT [EntityId] FROM scope_nodes
    UNION SELECT o.[SubjectEntityId] FROM owned o JOIN [location].[NodeRegistry] nr ON nr.[EntityId] = o.[SubjectEntityId]
),
readable_assets AS (
    SELECT [EntityId] FROM [asset].[AssetRegistry] WHERE EXISTS (SELECT 1 FROM is_global)
    UNION SELECT [AssetEntityId] FROM scope_assets
    UNION SELECT o.[SubjectEntityId] FROM owned o JOIN [asset].[AssetRegistry] ar ON ar.[EntityId] = o.[SubjectEntityId]
),
readable_workrequests AS (
    SELECT [EntityId] FROM [work].[WorkRequestRegistry] WHERE EXISTS (SELECT 1 FROM is_global)
    UNION SELECT r.[ScopeWorkRequestEntityId] FROM held r WHERE r.[ScopeKind] = N'WorkRequest'
    UNION SELECT w.[EntityId] FROM [work].[WorkRequest] w
          WHERE w.[IsDeleted] = 0 AND w.[ValidTo] IS NULL
            AND (w.[ScopeEntityId] IN (SELECT [EntityId] FROM scope_nodes) OR w.[ScopeEntityId] IN (SELECT [AssetEntityId] FROM scope_assets)
                 OR w.[ScopeEntityId] IN (SELECT [SubjectEntityId] FROM owned))
),
readable_records AS (
    SELECT [EntityId] FROM [record].[RecordRegistry] WHERE EXISTS (SELECT 1 FROM is_global)
    UNION SELECT rc.[EntityId] FROM [record].[Record] rc
          WHERE rc.[IsDeleted] = 0 AND rc.[ValidTo] IS NULL
            AND (rc.[SubjectEntityId] IN (SELECT [EntityId] FROM scope_nodes) OR rc.[SubjectEntityId] IN (SELECT [AssetEntityId] FROM scope_assets)
                 OR rc.[SubjectEntityId] IN (SELECT [SubjectEntityId] FROM owned)
                 OR rc.[WorkRequestEntityId] IN (SELECT r.[ScopeWorkRequestEntityId] FROM held r WHERE r.[ScopeKind] = N'WorkRequest'))
),
readable_schemes AS (
    SELECT [EntityId] FROM [scheme].[SchemeRegistry] WHERE EXISTS (SELECT 1 FROM is_global)
    UNION SELECT m.[SchemeEntityId] FROM [scheme].[SchemeMember] m
          WHERE m.[IsDeleted] = 0 AND m.[ValidFrom] <= @at AND (m.[ValidTo] IS NULL OR m.[ValidTo] > @at)
            AND ((m.[MemberKind] = N'Asset' AND m.[MemberEntityId] IN (SELECT [AssetEntityId] FROM scope_assets))
              OR (m.[MemberKind] = N'ProtectionFunction' AND m.[MemberEntityId] IN (SELECT [EntityId] FROM scope_nodes)))
)
SELECT [EntityId] AS [SubjectEntityId] FROM readable_nodes        WHERE @subjectKind = N'Node'
UNION ALL SELECT [EntityId] FROM readable_assets                  WHERE @subjectKind = N'Asset'
UNION ALL SELECT [EntityId] FROM readable_workrequests            WHERE @subjectKind = N'WorkRequest'
UNION ALL SELECT [EntityId] FROM readable_records                 WHERE @subjectKind = N'Record'
UNION ALL SELECT [EntityId] FROM readable_schemes                 WHERE @subjectKind = N'Scheme';
GO
GRANT SELECT ON [security].[fReadableSubjects] TO [app_execute];
GO
