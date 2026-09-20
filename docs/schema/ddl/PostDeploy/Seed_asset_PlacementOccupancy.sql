-- #206 (2026-09-20): a placement row says whether it shares its node (asset.Placement.SharesNode; NULL = holds it alone). A DevicePosition holds
-- one device and an EquipmentPosition one piece of primary plant (UX_Placement_InstalledAtNode); a Yard holds every CT and PT
-- in it (#202), a Panel every auxiliary mounted on it. asset.PlaceAsset sets the flag from the node type from now on; this
-- corrects the rows written before it existed (on DEV, 2026-09-20: 263 at panels, 6 in yards, 1 at a station). Idempotent.
IF COL_LENGTH(N'[asset].[Placement]', N'SharesNode') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
UPDATE p SET [SharesNode] = 1
FROM [asset].[Placement] p
JOIN [location].[Node] n ON n.[EntityId] = p.[NodeEntityId] AND n.[ValidTo] IS NULL AND n.[IsDeleted] = 0
WHERE p.[SharesNode] IS NULL AND p.[ValidTo] IS NULL AND p.[IsDeleted] = 0
  AND n.[NodeTypeCode] NOT IN (N'DevicePosition', N'EquipmentPosition');
GO
