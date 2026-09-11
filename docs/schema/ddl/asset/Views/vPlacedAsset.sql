-- Hand-written read model. SCHEMA-DESIGN §5; PLATFORM-ARCHITECTURE §2.3, §3.4.
--
-- What is placed at a functional location, with the asset named. The generic dispatcher filters a view
-- by equality on one column and cannot join, so a screen that wants "the assets at this node" either
-- gets a view like this one or a purpose-built endpoint. A view is the cheaper answer: the dispatcher
-- catalogues it automatically, and the permission map derives Asset.Read from the schema, so this file
-- and its GRANT are the whole change.
--
-- Per-node reads are the access pattern (asset.vPlacement is indexed on NodeEntityId). One node on the
-- migrated DEV data holds 940 placements and 79 nodes hold more than 25, which is why the client must
-- not resolve names one asset at a time.
CREATE VIEW [asset].[vPlacedAsset] AS
SELECT p.[RowSeq],
       p.[RowId],
       p.[EntityId],                                   -- the placement
       p.[NodeEntityId],
       p.[AssetEntityId],
       a.[Name]                AS [AssetName],
       a.[AssetTypeCode],
       a.[Status]              AS [AssetStatus],
       a.[VoltageClassCode],
       a.[ModelId],
       a.[ManufacturerEntityId],
       a.[CommissionedAt],
       p.[PlacementKind],
       p.[CustodyLocationEntityId],
       p.[WorkRequestEntityId],
       p.[ValidFrom]           AS [PlacedFrom],
       p.[ValidTo]             AS [PlacedTo]
FROM [asset].[vPlacement] p
JOIN [asset].[vAsset] a ON a.[EntityId] = p.[AssetEntityId];
GO
GRANT SELECT ON [asset].[vPlacedAsset] TO [app_execute];
GO
