-- SCHEMA-DESIGN §12.3. Reads a Fixed fact (a column the schema holds) for a subject, as text, at @at.
-- One CASE arm per fixed fact in compliance.vFactCatalogue; adding a fixed fact is a change here and
-- in the view (fixed facts are the design's own list; published facts need no code).
CREATE FUNCTION [compliance].[fFixedFactValue]
    (@subjectEntityId UNIQUEIDENTIFIER, @factName NVARCHAR(200), @at DATETIMEOFFSET(7))
RETURNS NVARCHAR(400)
AS
BEGIN
    DECLARE @v NVARCHAR(400);
    IF @factName = N'asset.voltage_class'
        SELECT TOP (1) @v = a.[VoltageClassCode] FROM [asset].[Asset] a
        WHERE a.[EntityId] = @subjectEntityId AND a.[IsDeleted] = 0 AND a.[ValidFrom] <= @at AND (a.[ValidTo] IS NULL OR a.[ValidTo] > @at)
        ORDER BY a.[ValidFrom] DESC, a.[RowSeq] DESC;
    ELSE IF @factName IN (N'device.model', N'device.technology')
        SELECT TOP (1) @v = CASE @factName WHEN N'device.model' THEN m.[ModelCode] ELSE m.[Technology] END
        FROM [asset].[Asset] a JOIN [ref].[Model] m ON m.[ModelId] = a.[ModelId]
        WHERE a.[EntityId] = @subjectEntityId AND a.[IsDeleted] = 0 AND a.[ValidFrom] <= @at AND (a.[ValidTo] IS NULL OR a.[ValidTo] > @at)
        ORDER BY a.[ValidFrom] DESC, a.[RowSeq] DESC;
    ELSE IF @factName = N'device.firmware'
        SELECT TOP (1) @v = fv.[VersionString]
        FROM [device].[FirmwareHistory] h JOIN [ref].[FirmwareVersion] fv ON fv.[FirmwareVersionId] = h.[FirmwareVersionId]
        WHERE h.[DeviceEntityId] = @subjectEntityId AND h.[IsDeleted] = 0 AND h.[ValidFrom] <= @at AND (h.[ValidTo] IS NULL OR h.[ValidTo] > @at)
        ORDER BY h.[ValidFrom] DESC, h.[RowSeq] DESC;
    ELSE IF @factName = N'station.type'
        SELECT TOP (1) @v = n.[SubtypeCode] FROM [location].[Node] n
        WHERE n.[EntityId] = @subjectEntityId AND n.[NodeTypeCode] = N'Station' AND n.[IsDeleted] = 0 AND n.[ValidFrom] <= @at AND (n.[ValidTo] IS NULL OR n.[ValidTo] > @at)
        ORDER BY n.[ValidFrom] DESC, n.[RowSeq] DESC;
    ELSE IF @factName = N'scheme.type'
        SELECT TOP (1) @v = d.[DefinitionKey]
        FROM [scheme].[Scheme] s
        JOIN [config].[DefinitionVersion] dv ON dv.[RowId] = s.[SchemeTypeDefinitionVersionRowId]
        JOIN [config].[Definition] d ON d.[EntityId] = dv.[DefinitionEntityId] AND d.[IsDeleted] = 0
        WHERE s.[EntityId] = @subjectEntityId AND s.[IsDeleted] = 0 AND s.[ValidFrom] <= @at AND (s.[ValidTo] IS NULL OR s.[ValidTo] > @at)
        ORDER BY s.[ValidFrom] DESC, s.[RowSeq] DESC;
    ELSE IF @factName = N'function.commissioned'
        -- the principal commissioned function at this protection-function node (vision §4.3)
        SELECT TOP (1) @v = cf.[AnsiCode] FROM [scheme].[CommissionedFunction] cf
        WHERE cf.[ProtectionFunctionNodeEntityId] = @subjectEntityId AND cf.[IsDeleted] = 0 AND cf.[ValidFrom] <= @at AND (cf.[ValidTo] IS NULL OR cf.[ValidTo] > @at)
        ORDER BY cf.[IsPrincipal] DESC, cf.[ValidFrom] DESC, cf.[RowSeq] DESC;
    ELSE IF @factName LIKE N'station.classification.%' OR @factName LIKE N'line.classification.%'
        SELECT TOP (1) @v = c.[ClassificationValue] FROM [asset].[Classification] c
        WHERE c.[SubjectEntityId] = @subjectEntityId
          AND c.[ClassificationKindCode] = SUBSTRING(@factName, CHARINDEX(N'.classification.', @factName) + 16, 40)
          AND c.[IsDeleted] = 0 AND c.[ValidFrom] <= @at AND (c.[ValidTo] IS NULL OR c.[ValidTo] > @at)
        ORDER BY c.[ValidFrom] DESC, c.[RowSeq] DESC;
    ELSE IF @factName LIKE N'platform.backup.last.%'
        -- §15.2: the completion instant of the last succeeded backup of that kind, at or before @at
        SELECT @v = CONVERT(NVARCHAR(40), MAX(b.[CompletedAt]), 127) FROM [audit].[BackupRun] b
        WHERE b.[BackupKind] = SUBSTRING(@factName, 22, 40) AND b.[Outcome] = N'Succeeded' AND b.[CompletedAt] <= @at;
    ELSE IF @factName = N'platform.restore_test.last'
        SELECT @v = CONVERT(NVARCHAR(40), MAX(r.[CompletedAt]), 127) FROM [audit].[RestoreTest] r
        WHERE r.[CompletedAt] <= @at AND r.[Outcome] = N'Succeeded';
    RETURN @v;
END;
GO
