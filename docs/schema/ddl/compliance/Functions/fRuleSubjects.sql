-- SCHEMA-DESIGN §12.2 (162), decision 56. The candidate subjects of an obligation rule for its admitted subject
-- kinds (a JSON array of kind names). Shared by RunRulePreview and RunRuleEffective so both modes scope
-- identically. Physical kinds: Asset, Device, Line, Station, Node, Scheme, ProtectionFunction. Non-physical
-- (PROCEDURES.md #35, 2026-09-06): Person, Entity, Document, Definition, and Platform — one subject with no
-- entity id (the platform itself; its facts are the platform.* rows of the catalogue).
CREATE FUNCTION [compliance].[fRuleSubjects] (@kinds NVARCHAR(MAX))
RETURNS TABLE
AS
RETURN
    SELECT N'Asset' AS [SubjectKind], a.[EntityId], a.[Name] FROM [asset].[vAsset] a WHERE EXISTS (SELECT 1 FROM OPENJSON(@kinds) WHERE [value] = N'Asset')
    UNION ALL
    SELECT N'Device', a.[EntityId], a.[Name] FROM [asset].[vAsset] a JOIN [device].[vDevice] d ON d.[EntityId] = a.[EntityId] WHERE EXISTS (SELECT 1 FROM OPENJSON(@kinds) WHERE [value] = N'Device')
    UNION ALL
    SELECT N'Line', a.[EntityId], a.[Name] FROM [asset].[vAsset] a WHERE a.[AssetTypeCode] = N'Line' AND EXISTS (SELECT 1 FROM OPENJSON(@kinds) WHERE [value] = N'Line')
    UNION ALL
    SELECT N'Station', n.[EntityId], n.[Name] FROM [location].[vNode] n WHERE n.[NodeTypeCode] = N'Station' AND EXISTS (SELECT 1 FROM OPENJSON(@kinds) WHERE [value] = N'Station')
    UNION ALL
    SELECT N'Node', n.[EntityId], n.[Name] FROM [location].[vNode] n WHERE EXISTS (SELECT 1 FROM OPENJSON(@kinds) WHERE [value] = N'Node')
    UNION ALL
    SELECT N'ProtectionFunction', n.[EntityId], n.[Name] FROM [location].[vNode] n WHERE n.[NodeTypeCode] = N'ProtectionFunction' AND EXISTS (SELECT 1 FROM OPENJSON(@kinds) WHERE [value] = N'ProtectionFunction')
    UNION ALL
    SELECT N'Scheme', s.[EntityId], s.[Name] FROM [scheme].[vScheme] s WHERE EXISTS (SELECT 1 FROM OPENJSON(@kinds) WHERE [value] = N'Scheme')
    UNION ALL
    SELECT N'Person', p.[EntityId], p.[DisplayName] FROM [personnel].[vPerson] p WHERE EXISTS (SELECT 1 FROM OPENJSON(@kinds) WHERE [value] = N'Person')
    UNION ALL
    SELECT N'Entity', e.[EntityId], e.[Name] FROM [party].[vEntity] e WHERE EXISTS (SELECT 1 FROM OPENJSON(@kinds) WHERE [value] = N'Entity')
    UNION ALL
    SELECT N'Document', d.[EntityId], d.[Title] FROM [document].[vDocument] d WHERE EXISTS (SELECT 1 FROM OPENJSON(@kinds) WHERE [value] = N'Document')
    UNION ALL
    SELECT N'Definition', d.[EntityId], d.[Name] FROM [config].[vDefinition] d WHERE EXISTS (SELECT 1 FROM OPENJSON(@kinds) WHERE [value] = N'Definition')
    UNION ALL
    SELECT N'Platform', CONVERT(UNIQUEIDENTIFIER, NULL), N'Platform' WHERE EXISTS (SELECT 1 FROM OPENJSON(@kinds) WHERE [value] = N'Platform');
GO
