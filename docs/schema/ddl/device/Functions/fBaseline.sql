-- SCHEMA-DESIGN §5.8 (decision 104), §6.8 (115); PROCEDURES.md #29.
-- The CIP configuration baseline of one device as a function of both clocks: the facts valid at
-- @validAt as the database believed them at @believedAtUtc — the configuration file in service,
-- the firmware in force, the placement, the classifications, the network ports and their services,
-- and the open advisory dispositions. No stored snapshot: an evidence package freezes this by
-- citing the RowIds it read (§12.7). The column set is the union of §5.8 and §6.8 (the two lists
-- differ; STEPS.md step 5 records it). One row per device; the multi-valued parts are aggregated.
CREATE FUNCTION [device].[fBaseline] (@deviceEntityId UNIQUEIDENTIFIER, @validAt DATETIMEOFFSET(7), @believedAtUtc DATETIME2(7))
RETURNS TABLE
AS
RETURN
    SELECT
        a.[EntityId]              AS [DeviceEntityId],
        a.[RowId]                 AS [AssetRowId],
        a.[Name]                  AS [DeviceName],
        a.[AssetTypeCode],
        a.[ModelId],
        d.[RowId]                 AS [DeviceRowId],
        fw.[RowId]                AS [FirmwareHistoryRowId],
        fw.[FirmwareVersionId]    AS [FirmwareVersionInForceId],
        cf.[RevisionRowId]        AS [InServiceConfigurationFileRevisionRowId],
        cf.[InServiceFrom],
        pl.[RowId]                AS [PlacementRowId],
        pl.[NodeEntityId]         AS [PlacementNodeEntityId],
        pl.[CustodyLocationEntityId] AS [PlacementCustodyLocationEntityId],
        pl.[PlacementKind],
        (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), CONCAT(c.[ClassificationKindCode], N'=', c.[ClassificationValue], N' [', CONVERT(NVARCHAR(36), c.[RowId]), N']')), N'; ')
           FROM [asset].[Classification] FOR SYSTEM_TIME AS OF @believedAtUtc c
          WHERE c.[SubjectKind] = N'Asset' AND c.[SubjectEntityId] = a.[EntityId] AND c.[IsDeleted] = 0
            AND c.[ValidFrom] <= @validAt AND (c.[ValidTo] IS NULL OR c.[ValidTo] > @validAt)) AS [Classifications],
        (SELECT STRING_AGG(t.[PortText], N'; ')
           FROM (SELECT CONCAT(p.[PortDesignator], N' ', ISNULL(np.[IpAddress], N''), N' [', CONVERT(NVARCHAR(36), p.[RowId]), N']', ISNULL(N' {' + svc.[Services] + N'}', N'')) AS [PortText]
                   FROM [connection].[Port] FOR SYSTEM_TIME AS OF @believedAtUtc p
                   JOIN [connection].[NetworkPort] FOR SYSTEM_TIME AS OF @believedAtUtc np
                     ON np.[EntityId] = p.[EntityId] AND np.[IsDeleted] = 0 AND np.[ValidFrom] <= @validAt AND (np.[ValidTo] IS NULL OR np.[ValidTo] > @validAt)
                   OUTER APPLY (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), CONCAT(ps.[Protocol], N':', ISNULL(CONVERT(NVARCHAR(10), ps.[LogicalPort]), N''))), N',') AS [Services]
                                  FROM [connection].[PortService] FOR SYSTEM_TIME AS OF @believedAtUtc ps
                                 WHERE ps.[NetworkPortEntityId] = p.[EntityId] AND ps.[IsDeleted] = 0 AND ps.[ValidFrom] <= @validAt AND (ps.[ValidTo] IS NULL OR ps.[ValidTo] > @validAt)) svc
                  WHERE p.[AssetEntityId] = a.[EntityId] AND p.[IsDeleted] = 0 AND p.[ValidFrom] <= @validAt AND (p.[ValidTo] IS NULL OR p.[ValidTo] > @validAt)) t) AS [NetworkPortsAndServices],
        (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), CONCAT(CONVERT(NVARCHAR(36), ad.[AdvisoryEntityId]), N' ', ad.[Action], N' [', CONVERT(NVARCHAR(36), ad.[RowId]), N']')), N'; ')
           FROM [device].[AdvisoryDisposition] FOR SYSTEM_TIME AS OF @believedAtUtc ad
          WHERE ad.[DeviceEntityId] = a.[EntityId] AND ad.[IsDeleted] = 0 AND ad.[CompletedAt] IS NULL
            AND ad.[ValidFrom] <= @validAt AND (ad.[ValidTo] IS NULL OR ad.[ValidTo] > @validAt)) AS [OpenAdvisoryDispositions]
    FROM [asset].[Asset] FOR SYSTEM_TIME AS OF @believedAtUtc a
    JOIN [device].[Device] FOR SYSTEM_TIME AS OF @believedAtUtc d
      ON d.[EntityId] = a.[EntityId] AND d.[IsDeleted] = 0 AND d.[ValidFrom] <= @validAt AND (d.[ValidTo] IS NULL OR d.[ValidTo] > @validAt)
    LEFT JOIN [device].[FirmwareHistory] FOR SYSTEM_TIME AS OF @believedAtUtc fw
      ON fw.[DeviceEntityId] = a.[EntityId] AND fw.[IsDeleted] = 0 AND fw.[ValidFrom] <= @validAt AND (fw.[ValidTo] IS NULL OR fw.[ValidTo] > @validAt)
    LEFT JOIN [document].[ConfigurationFile] FOR SYSTEM_TIME AS OF @believedAtUtc cf
      ON cf.[DeviceEntityId] = a.[EntityId] AND cf.[IsDeleted] = 0 AND cf.[FileKind] = N'NativeSettings'
     AND cf.[InServiceFrom] IS NOT NULL AND cf.[InServiceFrom] <= @validAt AND (cf.[InServiceTo] IS NULL OR cf.[InServiceTo] > @validAt)
    LEFT JOIN [asset].[Placement] FOR SYSTEM_TIME AS OF @believedAtUtc pl
      ON pl.[AssetEntityId] = a.[EntityId] AND pl.[IsDeleted] = 0 AND pl.[ValidFrom] <= @validAt AND (pl.[ValidTo] IS NULL OR pl.[ValidTo] > @validAt)
    WHERE a.[EntityId] = @deviceEntityId AND a.[IsDeleted] = 0 AND a.[ValidFrom] <= @validAt AND (a.[ValidTo] IS NULL OR a.[ValidTo] > @validAt);
GO
GRANT SELECT ON [device].[fBaseline] TO [app_execute];
GO
