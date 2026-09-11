-- SCHEMA-DESIGN §7.2 (decision 116); PROCEDURES.md #12. The "protection system" of vision §5.3:
-- a scheme with every current member resolved — a ProtectionFunction to its node, its parent
-- DevicePosition and the device installed there now; an Asset or Channel to the asset; a
-- Connection to its endpoints, realisation and carrier. One row per member.
CREATE VIEW [scheme].[vSchemeExpanded] AS
SELECT s.[EntityId]            AS [SchemeEntityId],
       s.[Name]                AS [SchemeName],
       s.[Status]              AS [SchemeStatus],
       m.[EntityId]            AS [MemberEntityId],
       m.[RowId]               AS [MemberRowId],
       m.[MemberKind],
       m.[MemberEntityId]      AS [MemberSubjectEntityId],
       m.[MemberRoleCode],
       m.[IsInService],
       [MemberName] = CASE m.[MemberKind]
                        WHEN N'ProtectionFunction' THEN fn.[Name]
                        WHEN N'Connection'         THEN CONCAT(c.[RealisationCode], N' ', c.[FromKind], N'→', c.[ToKind])
                        ELSE a.[Name] END,
       [FunctionNodeEntityId]   = fn.[EntityId],
       [DevicePositionEntityId] = CASE WHEN dp.[NodeTypeCode] = N'DevicePosition' THEN dp.[EntityId] END,
       [ResolvedDeviceEntityId] = CASE WHEN m.[MemberKind] = N'ProtectionFunction' THEN pl.[AssetEntityId] END,
       [ResolvedAssetEntityId]  = CASE WHEN m.[MemberKind] IN (N'Asset', N'Channel') THEN a.[EntityId]
                                       WHEN m.[MemberKind] = N'ProtectionFunction' THEN pl.[AssetEntityId] END,
       [AssetTypeCode]          = COALESCE(a.[AssetTypeCode], da.[AssetTypeCode]),
       [ConnectionEntityId]     = c.[EntityId],
       [RealisationCode]        = c.[RealisationCode],
       [FromKind] = c.[FromKind], [FromEntityId] = c.[FromEntityId], [ToKind] = c.[ToKind], [ToEntityId] = c.[ToEntityId],
       [CarrierAssetEntityId]   = c.[CarrierAssetEntityId],
       [ConnectionDesignStatus] = c.[DesignStatus]
FROM [scheme].[vScheme] s
JOIN [scheme].[vSchemeMember] m ON m.[SchemeEntityId] = s.[EntityId]
LEFT JOIN [location].[vNode] fn ON m.[MemberKind] = N'ProtectionFunction' AND fn.[EntityId] = m.[MemberEntityId]
LEFT JOIN [location].[vNode] dp ON dp.[EntityId] = fn.[ParentEntityId]
LEFT JOIN [asset].[vPlacement] pl ON pl.[NodeEntityId] = dp.[EntityId] AND pl.[PlacementKind] = N'Installed' AND dp.[NodeTypeCode] = N'DevicePosition'
LEFT JOIN [asset].[vAsset] da ON da.[EntityId] = pl.[AssetEntityId]
LEFT JOIN [asset].[vAsset] a ON m.[MemberKind] IN (N'Asset', N'Channel') AND a.[EntityId] = m.[MemberEntityId]
LEFT JOIN [connection].[vConnection] c ON m.[MemberKind] = N'Connection' AND c.[EntityId] = m.[MemberEntityId];
GO
GRANT SELECT ON [scheme].[vSchemeExpanded] TO [app_execute];
GO
