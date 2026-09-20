-- SCHEMA-DESIGN §4.4 (decision 92), §5.4 (99), §5.7 (101); PROCEDURES.md #5, #6.
-- The one way to say where an asset is. Checks: exactly one of node / custody; a routed asset
-- type has no placement (its location is its route); a device (asset type IsDevice) goes to a
-- DevicePosition node or to custody; a device whose ref.Model.DeviceCategory does not match the
-- position's subtype is refused unless the actor holds the PlacementOverride role (a security.Grant,
-- Global or NodeSubtree covering the position), in which case the override is logged.
-- Writes the placement (Add, or Revise closing the prior fact) and, for a device, the Installed /
-- Removed lifecycle events in the same transaction so the two never disagree (§5.4).
-- Implementation choices (STEPS.md step 4): the override role name; no category check when either
-- side is null; lifecycle TimeSourceQuality defaults to 3 (manual entry).
CREATE PROCEDURE [asset].[PlaceAsset]
    @AssetEntityId UNIQUEIDENTIFIER,
    @NodeEntityId UNIQUEIDENTIFIER = NULL,
    @CustodyLocationEntityId UNIQUEIDENTIFIER = NULL,
    @PlacementKind NVARCHAR(20),               -- Attached, Installed, Stored, AtVendor, Retained
    @WorkRequestEntityId UNIQUEIDENTIFIER = NULL,
    @OccurredAt DATETIMEOFFSET(7) = NULL,      -- valid-from of the placement and instant of the lifecycle event
    @ValidFromQuality TINYINT = 0,
    @TimeSourceQuality TINYINT = 3,
    @OverrideReason NVARCHAR(400) = NULL,
    @Notes NVARCHAR(MAX) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,
    @PlacementEntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @RowId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @OccurredAt = ISNULL(@OccurredAt, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;

    IF NOT ((@NodeEntityId IS NOT NULL AND @CustodyLocationEntityId IS NULL) OR (@NodeEntityId IS NULL AND @CustodyLocationEntityId IS NOT NULL))
        THROW 50211, N'asset.PlaceAsset: exactly one of @NodeEntityId / @CustodyLocationEntityId (§4.4).', 1;

    DECLARE @typeCode NVARCHAR(40), @modelId UNIQUEIDENTIFIER, @isDevice BIT, @isRouted BIT;
    SELECT @typeCode = a.[AssetTypeCode], @modelId = a.[ModelId], @isDevice = t.[IsDevice], @isRouted = t.[IsRouted]
    FROM [asset].[vAsset] a JOIN [ref].[AssetType] t ON t.[AssetTypeCode] = a.[AssetTypeCode]
    WHERE a.[EntityId] = @AssetEntityId;
    IF @typeCode IS NULL THROW 50212, N'asset.PlaceAsset: the asset is not a current asset.', 1;
    IF @isRouted = 1 THROW 50213, N'asset.PlaceAsset: a routed asset has no placement; its location is its route (§4.4).', 1;

    DECLARE @nodeType NVARCHAR(40), @nodeSubtype NVARCHAR(40), @nodePath NVARCHAR(900);
    IF @NodeEntityId IS NOT NULL
    BEGIN
        SELECT @nodeType = [NodeTypeCode], @nodeSubtype = [SubtypeCode], @nodePath = [Path] FROM [location].[vNode] WHERE [EntityId] = @NodeEntityId;
        IF @nodeType IS NULL THROW 50214, N'asset.PlaceAsset: the node is not a current node.', 1;
        IF @isDevice = 1 AND @nodeType <> N'DevicePosition'
        BEGIN
            DECLARE @m1 NVARCHAR(400) = CONCAT(N'asset.PlaceAsset: a device is placed at a DevicePosition or in custody, not at a ', @nodeType, N' (§4.4).');
            THROW 50215, @m1, 1;
        END;
        -- #202 (the owner, 2026-09-19): "instrument transformers on a transmission network are not installed in a bay, as they
        -- are on a distribution network. On the transmission network they are located in a yard, so they are a child of the
        -- Yard … later on we may place bays within buildings and then auxiliaries could also be placed as a child of bays, but
        -- for now they are in the yards only." A CT, VT, CVT, CCPD or metering unit stands in a Yard; a panel-mounted auxiliary
        -- CT or VT stands at a Panel. Widening this to bays is one line here when that day comes.
        IF @typeCode IN (N'CT', N'VT', N'COUPLING_CAPACITOR_VT', N'CCPD', N'METERING_UNIT') AND @nodeType <> N'Yard'
        BEGIN
            DECLARE @m3 NVARCHAR(400) = CONCAT(N'asset.PlaceAsset: an instrument transformer stands in a Yard on the transmission network, not at a ', @nodeType, N' (the owner, 2026-09-19).');
            THROW 50218, @m3, 1;
        END;
        IF @typeCode IN (N'CT_AUX', N'VT_AUX') AND @nodeType <> N'Panel'
        BEGIN
            DECLARE @m4 NVARCHAR(400) = CONCAT(N'asset.PlaceAsset: an auxiliary CT or VT is panel-mounted — it stands at a Panel, not at a ', @nodeType, N'.');
            THROW 50218, @m4, 1;
        END;
    END
    ELSE IF NOT EXISTS (SELECT 1 FROM [location].[vCustodyLocation] WHERE [EntityId] = @CustodyLocationEntityId)
        THROW 50214, N'asset.PlaceAsset: the custody location is not current.', 1;

    -- device category versus position subtype (§5.7), override by grant
    DECLARE @category NVARCHAR(40), @overrode BIT = 0;
    IF @isDevice = 1 AND @NodeEntityId IS NOT NULL AND @modelId IS NOT NULL
        SELECT @category = [DeviceCategory] FROM [ref].[Model] WHERE [ModelId] = @modelId;
    -- vocabularies differ in form (ref.Model.DeviceCategory 'LOGIC_PROCESSOR' from the predecessor vs DevicePositionKind 'LogicProcessor'): compare without case or underscores
    IF @category IS NOT NULL AND @nodeSubtype IS NOT NULL AND UPPER(REPLACE(@category, N'_', N'')) <> UPPER(REPLACE(@nodeSubtype, N'_', N''))
    BEGIN
        DECLARE @person UNIQUEIDENTIFIER = (SELECT [PersonEntityId] FROM [personnel].[Actor] WHERE [ActorId] = @ActorId);
        IF NOT EXISTS (
            SELECT 1 FROM [security].[vGrant] g
            WHERE g.[RoleCode] = N'PlacementOverride'
              AND (g.[ScopeKind] = N'Global'
                OR (g.[ScopeKind] = N'NodeSubtree' AND (g.[ScopeNodeEntityId] = @NodeEntityId OR @nodePath LIKE N'%/' + CONVERT(NVARCHAR(36), g.[ScopeNodeEntityId]) + N'/%')))
              AND ((g.[GranteeKind] = N'User'  AND g.[GranteeEntityId] IN (SELECT [EntityId] FROM [security].[vUser] WHERE [PersonEntityId] = @person))
                OR (g.[GranteeKind] = N'Group' AND g.[GranteeEntityId] IN (SELECT gm.[GroupEntityId] FROM [security].[vGroupMember] gm
                                                                          JOIN [security].[vUser] u ON u.[EntityId] = gm.[UserEntityId] WHERE u.[PersonEntityId] = @person))))
        BEGIN
            DECLARE @m2 NVARCHAR(400) = CONCAT(N'asset.PlaceAsset: device category ', @category, N' does not match the position subtype ', @nodeSubtype, N' and the actor holds no PlacementOverride grant (§5.7).');
            THROW 50216, @m2, 1;
        END;
        IF @OverrideReason IS NULL THROW 50217, N'asset.PlaceAsset: an override needs @OverrideReason (§11.7: every override is logged with authority).', 1;
        SET @overrode = 1;
    END;

    -- prior placement of this asset
    DECLARE @priorEntity UNIQUEIDENTIFIER, @priorKind NVARCHAR(20), @priorNode UNIQUEIDENTIFIER, @priorCustody UNIQUEIDENTIFIER;
    SELECT @priorEntity = [EntityId], @priorKind = [PlacementKind], @priorNode = [NodeEntityId], @priorCustody = [CustodyLocationEntityId]
    FROM [asset].[vPlacement] WHERE [AssetEntityId] = @AssetEntityId;

    BEGIN TRANSACTION;
    IF @overrode = 1
    BEGIN
        DECLARE @detail NVARCHAR(MAX) = (SELECT @category AS [deviceCategory], @nodeSubtype AS [positionSubtype], @OverrideReason AS [reason] FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [audit].[LogAction] @ActionKindCode = N'Override', @SubjectSchema = N'asset', @SubjectTable = N'Placement',
                                 @SubjectEntityId = @AssetEntityId, @Detail = @detail, @ActorId = @ActorId, @OccurredAt = @OccurredAt;
    END;

    DECLARE @installedBy UNIQUEIDENTIFIER = CASE WHEN @PlacementKind = N'Installed' THEN @ActorId END;
    IF @priorEntity IS NULL
        EXEC [asset].[Placement_Add] @AssetEntityId = @AssetEntityId, @NodeEntityId = @NodeEntityId, @CustodyLocationEntityId = @CustodyLocationEntityId,
             @PlacementKind = @PlacementKind, @InstalledByActorId = @installedBy, @WorkRequestEntityId = @WorkRequestEntityId,
             @ValidFrom = @OccurredAt, @ValidFromQuality = @ValidFromQuality, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId,
             @EntityId = @PlacementEntityId OUTPUT, @RowId = @RowId OUTPUT;
    ELSE
    BEGIN
        SET @PlacementEntityId = @priorEntity;
        DECLARE @removedBy UNIQUEIDENTIFIER = CASE WHEN @priorKind = N'Installed' AND (@PlacementKind <> N'Installed' OR ISNULL(@NodeEntityId, '00000000-0000-0000-0000-000000000000') <> ISNULL(@priorNode, '00000000-0000-0000-0000-000000000000')) THEN @ActorId END;
        EXEC [asset].[Placement_Revise] @EntityId = @priorEntity, @AssetEntityId = @AssetEntityId, @NodeEntityId = @NodeEntityId, @CustodyLocationEntityId = @CustodyLocationEntityId,
             @PlacementKind = @PlacementKind, @InstalledByActorId = @installedBy, @RemovedByActorId = @removedBy, @WorkRequestEntityId = @WorkRequestEntityId,
             @ValidFrom = @OccurredAt, @ValidFromQuality = @ValidFromQuality, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @RowId = @RowId OUTPUT;
    END;

    -- #206 (2026-09-20): how many may stand at the node. A DevicePosition holds one device and an EquipmentPosition one piece of
    -- primary plant (UX_Placement_InstalledAtNode, the predecessor's rule); a Yard holds every CT and PT in it (#202), a Panel every
    -- auxiliary mounted on it, a Station or Building whatever stands there. The row is written as holding alone (SharesNode NULL) and
    -- corrected here in the same transaction (SharesNode = 1 where many stand), so the generated Placement_Add needs no new parameter; the first deploy found a
    -- second transformer in the 230 kV yard refused by the index.
    IF @NodeEntityId IS NOT NULL AND @nodeType NOT IN (N'DevicePosition', N'EquipmentPosition')
        UPDATE [asset].[Placement] SET [SharesNode] = 1
        WHERE [RowId] = @RowId AND [SharesNode] IS NULL;

    -- lifecycle events for devices, in the same transaction (§5.4)
    IF @isDevice = 1
    BEGIN
        IF @priorKind = N'Installed' AND (@PlacementKind <> N'Installed' OR ISNULL(@NodeEntityId, '00000000-0000-0000-0000-000000000000') <> ISNULL(@priorNode, '00000000-0000-0000-0000-000000000000'))
            EXEC [device].[LifecycleEvent_Append] @DeviceEntityId = @AssetEntityId, @EventKind = N'Removed', @OccurredAt = @OccurredAt, @TimeSourceQuality = @TimeSourceQuality,
                 @ActorId = @ActorId, @NodeEntityId = @priorNode, @CustodyLocationEntityId = @priorCustody, @WorkRequestEntityId = @WorkRequestEntityId, @Notes = @Notes;
        IF @PlacementKind = N'Installed' AND (ISNULL(@priorKind, N'') <> N'Installed' OR ISNULL(@NodeEntityId, '00000000-0000-0000-0000-000000000000') <> ISNULL(@priorNode, '00000000-0000-0000-0000-000000000000'))
            EXEC [device].[LifecycleEvent_Append] @DeviceEntityId = @AssetEntityId, @EventKind = N'Installed', @OccurredAt = @OccurredAt, @TimeSourceQuality = @TimeSourceQuality,
                 @ActorId = @ActorId, @NodeEntityId = @NodeEntityId, @CustodyLocationEntityId = @CustodyLocationEntityId, @WorkRequestEntityId = @WorkRequestEntityId, @Notes = @Notes;
    END;
    COMMIT TRANSACTION;
END;
GO
