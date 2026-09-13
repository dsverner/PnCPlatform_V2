-- PLATFORM-ARCHITECTURE §2.4 (204), decision 237; vision §9.4; SCHEMA-DESIGN §11.3–11.5. The access decision as
-- one function the API calls on every request: does the user hold, at @at, a role that carries the permission,
-- through a grant (to the user or a group it belongs to) or a delegation in force, whose scope covers the subject?
-- Deny by default. Scope kinds: Global; NodeSubtree (the subject's node lies under the scope node by Path, with
-- the asset-class / device-category filters when the subject is an asset); WorkRequest (the subject is that
-- request, or a record or asset scoped to it); OwnershipRelation (an OwnershipLink of the scope role to the scope
-- entity on the subject). Subjects with no node mapping (Document, Definition, Obligation, Grant, Platform, or a
-- null subject) are covered only by Global — except Definition.Read, held class-wide by any scope (W6 card H, #134).
-- Reads are decided as strictly as writes (decision 59).
CREATE FUNCTION [security].[fHasPermission]
    (@userEntityId UNIQUEIDENTIFIER, @permissionCode NVARCHAR(80), @subjectKind NVARCHAR(40), @subjectEntityId UNIQUEIDENTIFIER, @at DATETIMEOFFSET(7))
RETURNS BIT
AS
BEGIN
    IF @userEntityId IS NULL OR @permissionCode IS NULL RETURN 0;
    DECLARE @nowUtc DATETIME2(7) = SYSUTCDATETIME();
    DECLARE @person UNIQUEIDENTIFIER = (SELECT TOP (1) [PersonEntityId] FROM [security].[User] WHERE [EntityId] = @userEntityId AND [IsDeleted] = 0 AND [IsEnabled] = 1 AND [ValidTo] IS NULL);
    IF @person IS NULL RETURN 0;

    -- roles in force: grants to the user or its groups, and positional roles delegated to the person
    DECLARE @roles TABLE ([RoleCode] NVARCHAR(40), [ScopeKind] NVARCHAR(40), [ScopeNodeEntityId] UNIQUEIDENTIFIER, [ScopeAssetClassCode] NVARCHAR(40),
                          [ScopeDeviceCategory] NVARCHAR(40), [ScopeWorkRequestEntityId] UNIQUEIDENTIFIER, [ScopeEntityEntityId] UNIQUEIDENTIFIER, [ScopeOwnershipRole] NVARCHAR(20));
    INSERT @roles
    SELECT g.[RoleCode], g.[ScopeKind], g.[ScopeNodeEntityId], g.[ScopeAssetClassCode], g.[ScopeDeviceCategory], g.[ScopeWorkRequestEntityId], g.[ScopeEntityEntityId], g.[ScopeOwnershipRole]
    FROM [security].[fGrantAsOf](@at, @nowUtc) g
    WHERE g.[RevokedByActorId] IS NULL
      AND ((g.[GranteeKind] = N'User' AND g.[GranteeEntityId] = @userEntityId)
        OR (g.[GranteeKind] = N'Group' AND EXISTS (SELECT 1 FROM [security].[GroupMember] gm
                                                   WHERE gm.[GroupEntityId] = g.[GranteeEntityId] AND gm.[UserEntityId] = @userEntityId AND gm.[IsDeleted] = 0
                                                     AND gm.[ValidFrom] <= @at AND (gm.[ValidTo] IS NULL OR gm.[ValidTo] > @at))));
    INSERT @roles
    SELECT d.[RoleCode], N'Global', NULL, NULL, NULL, NULL, NULL, NULL
    FROM [security].[fDelegationAsOf](@at, @nowUtc) d
    WHERE d.[ToPersonEntityId] = @person AND d.[RevokedByActorId] IS NULL AND d.[StartsAt] <= @at AND (d.[EndsAt] IS NULL OR d.[EndsAt] > @at);
    -- keep only roles that carry the permission
    DELETE @roles WHERE [RoleCode] NOT IN (SELECT rp.[RoleCode] FROM [security].[RolePermission] rp WHERE rp.[PermissionCode] = @permissionCode AND rp.[IsActive] = 1);
    IF NOT EXISTS (SELECT 1 FROM @roles) RETURN 0;
    IF EXISTS (SELECT 1 FROM @roles WHERE [ScopeKind] = N'Global') RETURN 1;
    -- W6 card H (decision #134): definitions and reference data (config.*, ref.* — class Definition) are read class-wide by
    -- any role that carries Definition.Read, whatever the grant's scope: they have no place in the tree and every screen
    -- needs them (work types, models, procedures). Writes and approvals of definitions stay Global-only.
    IF @permissionCode = N'Definition.Read' AND (@subjectKind IS NULL OR @subjectKind IN (N'Definition', N'DefinitionVersion')) RETURN 1;
    IF @subjectEntityId IS NULL RETURN 0;

    -- the subject's places: (node entity, asset entity) pairs the scopes are tested against
    DECLARE @places TABLE ([NodeEntityId] UNIQUEIDENTIFIER, [AssetEntityId] UNIQUEIDENTIFIER, [WorkRequestEntityId] UNIQUEIDENTIFIER);
    DECLARE @kind NVARCHAR(40) = @subjectKind, @subj UNIQUEIDENTIFIER = @subjectEntityId, @wr UNIQUEIDENTIFIER = NULL;
    IF @kind = N'Record'
    BEGIN
        SELECT TOP (1) @kind = r.[SubjectKind], @subj = r.[SubjectEntityId], @wr = r.[WorkRequestEntityId] FROM [record].[Record] r
        WHERE r.[EntityId] = @subjectEntityId AND r.[IsDeleted] = 0 AND r.[ValidTo] IS NULL ORDER BY r.[RowSeq] DESC;
    END
    IF @kind = N'WorkRequest'
    BEGIN
        SET @wr = @subj;
        SELECT TOP (1) @kind = w.[ScopeKind], @subj = w.[ScopeEntityId] FROM [work].[WorkRequest] w
        WHERE w.[EntityId] = @subj AND w.[IsDeleted] = 0 AND w.[ValidTo] IS NULL ORDER BY w.[RowSeq] DESC;
    END
    IF @kind IN (N'Node', N'Station', N'Panel', N'DevicePosition', N'ProtectionFunction', N'Structure', N'RightOfWay', N'Region')
        INSERT @places VALUES (@subj, NULL, @wr);
    ELSE IF @kind IN (N'Asset', N'Device', N'Line', N'Channel', N'Instrument')
        INSERT @places
        SELECT pl.[NodeEntityId], @subj, @wr FROM [asset].[Placement] pl
        WHERE pl.[AssetEntityId] = @subj AND pl.[IsDeleted] = 0 AND pl.[ValidFrom] <= @at AND (pl.[ValidTo] IS NULL OR pl.[ValidTo] > @at) AND pl.[NodeEntityId] IS NOT NULL
        UNION ALL SELECT NULL, @subj, @wr;
    ELSE IF @kind = N'Scheme'
        INSERT @places
        SELECT pl.[NodeEntityId], m.[MemberEntityId], @wr FROM [scheme].[SchemeMember] m
        JOIN [asset].[Placement] pl ON pl.[AssetEntityId] = m.[MemberEntityId] AND pl.[IsDeleted] = 0 AND pl.[ValidFrom] <= @at AND (pl.[ValidTo] IS NULL OR pl.[ValidTo] > @at)
        WHERE m.[SchemeEntityId] = @subj AND m.[MemberKind] = N'Asset' AND m.[IsDeleted] = 0 AND m.[ValidFrom] <= @at AND (m.[ValidTo] IS NULL OR m.[ValidTo] > @at)
        UNION ALL
        SELECT m.[MemberEntityId], NULL, @wr FROM [scheme].[SchemeMember] m
        WHERE m.[SchemeEntityId] = @subj AND m.[MemberKind] = N'ProtectionFunction' AND m.[IsDeleted] = 0 AND m.[ValidFrom] <= @at AND (m.[ValidTo] IS NULL OR m.[ValidTo] > @at);
    ELSE IF @wr IS NOT NULL
        INSERT @places VALUES (NULL, NULL, @wr);

    -- WorkRequest scope: the subject is, or is scoped to, that request
    IF EXISTS (SELECT 1 FROM @roles r JOIN @places p ON p.[WorkRequestEntityId] = r.[ScopeWorkRequestEntityId] WHERE r.[ScopeKind] = N'WorkRequest') RETURN 1;

    -- NodeSubtree scope: a place's node lies under the scope node; asset filters apply when the place is an asset
    IF EXISTS (SELECT 1 FROM @roles r
               JOIN [location].[Node] sn ON sn.[EntityId] = r.[ScopeNodeEntityId] AND sn.[IsDeleted] = 0 AND sn.[ValidTo] IS NULL
               JOIN @places p ON p.[NodeEntityId] IS NOT NULL
               JOIN [location].[Node] n ON n.[EntityId] = p.[NodeEntityId] AND n.[IsDeleted] = 0 AND n.[ValidTo] IS NULL
               -- V2 W2: a node's Path holds its ancestors' ids only (location.AddNode), so "under sn" is
               -- sn itself or a Path that continues with sn's own id. The carried predicate (n.Path LIKE sn.Path + '%')
               -- also matched every sibling subtree — a Transmission scope would have covered Distribution.
               WHERE r.[ScopeKind] = N'NodeSubtree' AND (n.[EntityId] = sn.[EntityId] OR n.[Path] LIKE sn.[Path] + CONVERT(NVARCHAR(36), sn.[EntityId]) + N'/%')
                 AND (r.[ScopeAssetClassCode] IS NULL OR p.[AssetEntityId] IS NULL OR EXISTS (
                        SELECT 1 FROM [asset].[Asset] a JOIN [ref].[AssetType] t ON t.[AssetTypeCode] = a.[AssetTypeCode]
                        WHERE a.[EntityId] = p.[AssetEntityId] AND a.[IsDeleted] = 0 AND a.[ValidTo] IS NULL AND t.[AssetClassCode] = r.[ScopeAssetClassCode]))
                 AND (r.[ScopeDeviceCategory] IS NULL OR p.[AssetEntityId] IS NULL OR EXISTS (
                        SELECT 1 FROM [asset].[Asset] a JOIN [ref].[Model] m ON m.[ModelId] = a.[ModelId]
                        WHERE a.[EntityId] = p.[AssetEntityId] AND a.[IsDeleted] = 0 AND a.[ValidTo] IS NULL AND m.[DeviceCategory] = r.[ScopeDeviceCategory])))
        RETURN 1;

    -- OwnershipRelation scope: the subject (or its asset) is owned in that role by the scope entity
    IF EXISTS (SELECT 1 FROM @roles r
               JOIN [asset].[OwnershipLink] o ON o.[EntityEntityId] = r.[ScopeEntityEntityId] AND o.[OwnershipRole] = r.[ScopeOwnershipRole]
                    AND o.[IsDeleted] = 0 AND o.[ValidFrom] <= @at AND (o.[ValidTo] IS NULL OR o.[ValidTo] > @at)
               WHERE r.[ScopeKind] = N'OwnershipRelation'
                 AND (o.[SubjectEntityId] = @subjectEntityId OR o.[SubjectEntityId] IN (SELECT [AssetEntityId] FROM @places WHERE [AssetEntityId] IS NOT NULL)
                      OR o.[SubjectEntityId] IN (SELECT [NodeEntityId] FROM @places WHERE [NodeEntityId] IS NOT NULL)))
        RETURN 1;
    RETURN 0;
END;
GO
