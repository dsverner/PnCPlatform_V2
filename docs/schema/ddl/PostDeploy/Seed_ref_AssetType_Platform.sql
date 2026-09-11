-- PLATFORM-ARCHITECTURE §8.1 (226): the platform's own hosts (Application VM, application server, database
-- server, DMZ satellite hosts) are assets of type PlatformHost, so their ports and services — the
-- boundary-flow register of §1.2 — are connection.Port / NetworkPort / PortService rows like a relay's.
-- Idempotent through ref.AssetType_Upsert.
IF OBJECT_ID(N'[ref].[AssetType_Upsert]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'PlatformHost', @Name = N'Platform host',
     @Description = N'A host of the PnC platform itself (application VM, application server, database server, DMZ satellite); its ports and services are the boundary-flow register (PLATFORM-ARCHITECTURE §1.2, §8.1)',
     @AssetClassCode = N'NonEnergised', @IsDevice = 0, @ActorId = @actor;
GO
