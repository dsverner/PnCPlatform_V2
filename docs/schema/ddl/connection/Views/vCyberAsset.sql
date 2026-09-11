-- SCHEMA-DESIGN §6.8 (115). The cyber-asset inventory (vision §9.2): every device with at least one
-- network port, with its firmware in force, its network ports and services, its perimeter membership,
-- its placement and its classifications. No second table exists. The design calls this a generated
-- view; its shape is domain-specific, so it is hand-written here and listed in STEPS.md as such.
-- One row per device × network port; device-level facts repeat on each row.
CREATE VIEW [connection].[vCyberAsset] AS
SELECT
    a.[EntityId]                       AS [DeviceEntityId],
    a.[Name]                           AS [DeviceName],
    a.[AssetTypeCode],
    a.[ModelId],
    a.[Status]                         AS [AssetStatus],
    fw.[FirmwareVersionId]             AS [FirmwareVersionInForceId],
    p.[EntityId]                       AS [PortEntityId],
    p.[PortDesignator],
    p.[PortKindCode],
    np.[MacAddress], np.[IpAddress], np.[SubnetMask], np.[Gateway], np.[VlanId], np.[IsEnabled],
    (SELECT STRING_AGG(ps.[Protocol] + N':' + ISNULL(CONVERT(NVARCHAR(10), ps.[LogicalPort]), N''), N', ')
       FROM [connection].[vPortService] ps WHERE ps.[NetworkPortEntityId] = p.[EntityId]) AS [Services],
    (SELECT STRING_AGG(CONVERT(NVARCHAR(36), m.[PerimeterEntityId]) + N':' + m.[Role], N', ')
       FROM [connection].[vSecurityPerimeterMember] m WHERE m.[DeviceEntityId] = a.[EntityId]) AS [PerimeterMembership],
    pl.[NodeEntityId]                  AS [PlacementNodeEntityId],
    pl.[CustodyLocationEntityId]       AS [PlacementCustodyLocationEntityId],
    pl.[PlacementKind],
    (SELECT STRING_AGG(c.[ClassificationKindCode] + N'=' + c.[ClassificationValue], N', ')
       FROM [asset].[vClassification] c WHERE c.[SubjectKind] = N'Asset' AND c.[SubjectEntityId] = a.[EntityId]) AS [Classifications]
FROM [asset].[vAsset] a
JOIN [connection].[vPort] p ON p.[AssetEntityId] = a.[EntityId]
JOIN [connection].[vNetworkPort] np ON np.[EntityId] = p.[EntityId]
LEFT JOIN [device].[vFirmwareHistory] fw ON fw.[DeviceEntityId] = a.[EntityId]
LEFT JOIN [asset].[vPlacement] pl ON pl.[AssetEntityId] = a.[EntityId];
GO
GRANT SELECT ON [connection].[vCyberAsset] TO [app_execute];
GO
