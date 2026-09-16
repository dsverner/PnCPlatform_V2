-- #170 (2026-09-16): the primary assets a protection scheme protects — the subjects of the applicability classifications
-- (CIP impact, BES status, NPCC A-10, PRC-023), which belong to the primary asset, not to the relay (the owner, 2026-09-16).
-- A thin registry for this phase: a name, a type and the station it is placed at; no connectivity, no impedances — the
-- power-system model (the TLM project for lines, the transformers, busses and connectivity) is a project of its own.
-- A line is not routed here yet (a routed asset has no placement, asset.PlaceAsset 50213); when the TLM project joins,
-- the line becomes routed and its terminals come from there. The system itself is the asset a RAS / system-protection
-- scheme protects. Idempotent through ref.AssetType_Upsert.
IF OBJECT_ID(N'[ref].[AssetType_Upsert]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'Line', @Name = N'Transmission line', @Description = N'A transmission or distribution line (placed at its home station in this phase; routed when the TLM project supplies its structures)', @AssetClassCode = N'Primary', @IsDevice = 0, @IsRouted = 0, @ActorId = @actor;
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'Transformer', @Name = N'Transformer', @Description = N'A power transformer (or autotransformer)', @AssetClassCode = N'Primary', @IsDevice = 0, @ActorId = @actor;
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'Bus', @Name = N'Bus', @Description = N'A station bus (the subject of the NPCC A-10 impactful-bus list)', @AssetClassCode = N'Primary', @IsDevice = 0, @ActorId = @actor;
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'Breaker', @Name = N'Circuit breaker', @Description = N'A circuit breaker (the subject of breaker-failure protection)', @AssetClassCode = N'Primary', @IsDevice = 0, @ActorId = @actor;
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'Generator', @Name = N'Generator', @Description = N'A generating unit', @AssetClassCode = N'Primary', @IsDevice = 0, @ActorId = @actor;
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'Capacitor', @Name = N'Capacitor bank', @Description = N'A shunt or series capacitor bank', @AssetClassCode = N'Primary', @IsDevice = 0, @ActorId = @actor;
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'Reactor', @Name = N'Reactor', @Description = N'A shunt or series reactor', @AssetClassCode = N'Primary', @IsDevice = 0, @ActorId = @actor;
EXEC [ref].[AssetType_Upsert] @AssetTypeCode = N'System', @Name = N'Power system', @Description = N'The system itself — what a remedial action scheme or other system-protection scheme protects (the owner, 2026-09-16: a system protection has no single primary element)', @AssetClassCode = N'Primary', @IsDevice = 0, @ActorId = @actor;
GO
