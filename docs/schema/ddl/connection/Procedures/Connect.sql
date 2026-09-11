-- SCHEMA-DESIGN §6.2 (decisions 108, 109); PROCEDURES.md #9.
-- Writes a connection after the endpoint / carrier rules of its realisation:
--   PanelWire, CableConductor      — Stud endpoints; a carrier asset is required
--   Goose, SampledValues           — from a Dataset to a Port or ProtectionFunction (§6.4)
--   EthernetLink, FiberLink, SerialLink — NetworkPort endpoints; no carrier
--   OverChannel                    — a channel-asset carrier is required
--   Mms, Serial, Routable          — the design states no endpoint rule (STEPS.md step 6, open):
--                                    endpoints are only checked to exist
-- Endpoint kinds are checked against what they name (a Stud or ProtectionFunction is a node of
-- that type; a NetworkPort has a connection.NetworkPort row). The design gives no asset-type flag
-- that identifies a wire, conductor or channel asset, so "a carrier whose type matches" is checked
-- only for existence (STEPS.md step 6, open).
CREATE PROCEDURE [connection].[Connect]
    @FromKind NVARCHAR(40),
    @FromEntityId UNIQUEIDENTIFIER,
    @ToKind NVARCHAR(40),
    @ToEntityId UNIQUEIDENTIFIER,
    @RealisationCode NVARCHAR(40),
    @CarrierAssetEntityId UNIQUEIDENTIFIER = NULL,
    @DesignStatus NVARCHAR(20) = N'Designed',
    @VerifiedByRecordEntityId UNIQUEIDENTIFIER = NULL,
    @WorkRequestEntityId UNIQUEIDENTIFIER = NULL,
    @DrawingKey NVARCHAR(100) = NULL,
    @Notes NVARCHAR(MAX) = NULL,
    @ValidFrom DATETIMEOFFSET(7) = NULL,
    @ValidFromQuality TINYINT = 0,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,
    @EntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @RowId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM [ref].[ConnectionRealisation] WHERE [RealisationCode] = @RealisationCode AND [IsActive] = 1)
        THROW 50260, N'connection.Connect: unknown or inactive realisation.', 1;

    DECLARE @m NVARCHAR(400);
    IF @RealisationCode IN (N'PanelWire', N'CableConductor')
    BEGIN
        IF @FromKind <> N'Stud' OR @ToKind <> N'Stud' BEGIN SET @m = CONCAT(N'connection.Connect: ', @RealisationCode, N' joins stud to stud (§6.2).'); THROW 50261, @m, 1; END;
        IF @CarrierAssetEntityId IS NULL BEGIN SET @m = CONCAT(N'connection.Connect: ', @RealisationCode, N' requires the wire or conductor asset as carrier (§6.2).'); THROW 50262, @m, 1; END;
    END
    ELSE IF @RealisationCode IN (N'Goose', N'SampledValues')
    BEGIN
        IF @FromKind <> N'Dataset' OR @ToKind NOT IN (N'Port', N'ProtectionFunction')
        BEGIN SET @m = CONCAT(N'connection.Connect: ', @RealisationCode, N' runs from a Dataset to a Port or ProtectionFunction (§6.4).'); THROW 50263, @m, 1; END;
    END
    ELSE IF @RealisationCode IN (N'EthernetLink', N'FiberLink', N'SerialLink')
    BEGIN
        IF @FromKind <> N'NetworkPort' OR @ToKind <> N'NetworkPort' BEGIN SET @m = CONCAT(N'connection.Connect: ', @RealisationCode, N' joins network ports (§6.2).'); THROW 50264, @m, 1; END;
        IF @CarrierAssetEntityId IS NOT NULL BEGIN SET @m = CONCAT(N'connection.Connect: ', @RealisationCode, N' has no carrier (§6.2).'); THROW 50265, @m, 1; END;
    END
    ELSE IF @RealisationCode = N'OverChannel' AND @CarrierAssetEntityId IS NULL
        THROW 50266, N'connection.Connect: OverChannel requires the channel asset as carrier (§6.2).', 1;

    -- endpoints name what their kind says
    IF @FromKind IN (N'Stud', N'ProtectionFunction') AND NOT EXISTS (SELECT 1 FROM [location].[vNode] WHERE [EntityId] = @FromEntityId AND [NodeTypeCode] = @FromKind)
        THROW 50267, N'connection.Connect: the from-endpoint is not a current node of the stated kind.', 1;
    IF @ToKind IN (N'Stud', N'ProtectionFunction') AND NOT EXISTS (SELECT 1 FROM [location].[vNode] WHERE [EntityId] = @ToEntityId AND [NodeTypeCode] = @ToKind)
        THROW 50267, N'connection.Connect: the to-endpoint is not a current node of the stated kind.', 1;
    IF @FromKind = N'NetworkPort' AND NOT EXISTS (SELECT 1 FROM [connection].[vNetworkPort] WHERE [EntityId] = @FromEntityId)
        THROW 50268, N'connection.Connect: the from-endpoint is not a current network port.', 1;
    IF @ToKind = N'NetworkPort' AND NOT EXISTS (SELECT 1 FROM [connection].[vNetworkPort] WHERE [EntityId] = @ToEntityId)
        THROW 50268, N'connection.Connect: the to-endpoint is not a current network port.', 1;
    IF @FromKind = N'Port' AND NOT EXISTS (SELECT 1 FROM [connection].[vPort] WHERE [EntityId] = @FromEntityId)
        THROW 50268, N'connection.Connect: the from-endpoint is not a current port.', 1;
    IF @ToKind = N'Port' AND NOT EXISTS (SELECT 1 FROM [connection].[vPort] WHERE [EntityId] = @ToEntityId)
        THROW 50268, N'connection.Connect: the to-endpoint is not a current port.', 1;
    IF @FromKind = N'Dataset' AND NOT EXISTS (SELECT 1 FROM [connection].[vDataset] WHERE [EntityId] = @FromEntityId)
        THROW 50268, N'connection.Connect: the from-endpoint is not a current dataset.', 1;
    IF @CarrierAssetEntityId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [asset].[vAsset] WHERE [EntityId] = @CarrierAssetEntityId)
        THROW 50269, N'connection.Connect: the carrier is not a current asset.', 1;

    EXEC [connection].[Connection_Add] @FromKind = @FromKind, @FromEntityId = @FromEntityId, @ToKind = @ToKind, @ToEntityId = @ToEntityId,
         @RealisationCode = @RealisationCode, @CarrierAssetEntityId = @CarrierAssetEntityId, @DesignStatus = @DesignStatus,
         @VerifiedByRecordEntityId = @VerifiedByRecordEntityId, @WorkRequestEntityId = @WorkRequestEntityId, @DrawingKey = @DrawingKey, @Notes = @Notes,
         @ValidFrom = @ValidFrom, @ValidFromQuality = @ValidFromQuality, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId,
         @EntityId = @EntityId OUTPUT, @RowId = @RowId OUTPUT;
END;
GO
