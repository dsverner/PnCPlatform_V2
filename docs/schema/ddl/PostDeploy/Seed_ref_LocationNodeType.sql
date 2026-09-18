-- SCHEMA-DESIGN §3.1 (80): node types with geometry (only Raceway and RightOfWay are Linear,
-- decision 30) and the Cascade-supplied flag (Region, Station, Building, Room, Panel — decision 24).
-- MeteringPosition and NetworkSwitchPosition are listed in §3.1's code list "as device-position
-- subtypes"; they are seeded as codes per the list, with no allowed-parent pairs (none stated) —
-- STEPS.md flags this. Subtype lists are attached by Seed_config_Enumerations.sql.
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [ref].[LocationNodeType] AS t
USING (VALUES
    -- The FLOC spine above the station (MIGRATION-FLOC-PLAN sections 4.1 and 10, owner 2026-09-08).
    -- A functional location reads <division>-<asset number>[-...], so the division is a real level and
    -- the owner sits above it. Region is deliberately NOT their parent: the owner's ruling is that a
    -- region is a management grouping that changes with reorganisations and has no place in the FLOC.
    (N'Owner',                 N'Owner',                  N'Point',  1),
    (N'Division',              N'Division',               N'Point',  1),
    (N'Region',                N'Region',                 N'Point',  1),
    (N'Station',               N'Station',                N'Point',  1),
    (N'Building',              N'Building',               N'Point',  1),
    (N'Room',                  N'Room',                   N'Point',  1),
    (N'Panel',                 N'Panel',                  N'Point',  1),
    (N'DevicePosition',        N'Device position',        N'Point',  0),
    -- #180: a protection function adds NO segment to the FLOC. A relay's tag ends at its position (21A), and the
    -- elements inside it are recorded but never tagged — see ref.LocationNodeType.CarriesFlocSegment.
    (N'ProtectionFunction',    N'Protection function',    N'Point',  0),
    (N'TerminalBlock',         N'Terminal block',         N'Point',  0),
    (N'Stud',                  N'Stud',                   N'Point',  0),
    (N'Yard',                  N'Yard',                   N'Point',  0),
    (N'Bay',                   N'Bay',                    N'Point',  0),
    (N'EquipmentPosition',     N'Equipment position',     N'Point',  0),
    (N'JunctionBox',           N'Junction box',           N'Point',  0),
    (N'Raceway',               N'Raceway',                N'Linear', 0),
    (N'Segment',               N'Segment',                N'Point',  0),
    (N'RightOfWay',            N'Right of way',           N'Linear', 0),
    (N'Structure',             N'Structure',              N'Point',  0),
    (N'AttachmentPoint',       N'Attachment point',       N'Point',  0),
    (N'MeteringPosition',      N'Metering position (predecessor; device-position subtype)',       N'Point', 0),
    (N'NetworkSwitchPosition', N'Network switch position (predecessor; device-position subtype)', N'Point', 0)
) AS s ([NodeTypeCode], [Name], [Geometry], [IsCascadeSupplied])
ON t.[NodeTypeCode] = s.[NodeTypeCode]
WHEN MATCHED AND (t.[Name] <> s.[Name] OR t.[Geometry] <> s.[Geometry] OR t.[IsCascadeSupplied] <> s.[IsCascadeSupplied])
    THEN UPDATE SET [Name] = s.[Name], [Geometry] = s.[Geometry], [IsCascadeSupplied] = s.[IsCascadeSupplied], [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET
    THEN INSERT ([NodeTypeCode], [Name], [Geometry], [IsCascadeSupplied], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
         VALUES (s.[NodeTypeCode], s.[Name], s.[Geometry], s.[IsCascadeSupplied], @actor, @now, @actor, @now);
GO

-- #180 (2026-09-17): the types whose nodes add no segment to the FLOC. Only the protection function today: the owner
-- ruled that a relay's tag ends at the position it stands in. Set here rather than in the MERGE's VALUES so the one
-- exception reads as an exception, and so a later ruling is one row to change.
DECLARE @actor1 UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now1 DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
UPDATE [ref].[LocationNodeType] SET [CarriesFlocSegment] = 0, [ModifiedBy] = @actor1, [ModifiedAt] = @now1
WHERE [NodeTypeCode] = N'ProtectionFunction' AND ISNULL([CarriesFlocSegment], 1) = 1;
UPDATE [ref].[LocationNodeType] SET [CarriesFlocSegment] = 1, [ModifiedBy] = @actor1, [ModifiedAt] = @now1
WHERE [NodeTypeCode] <> N'ProtectionFunction' AND [CarriesFlocSegment] IS NULL;
GO

-- and the rule made true of the data, not only of new writes: a node of such a type keeps no code and no FLOC
DECLARE @actor2 UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now2 DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
UPDATE n SET [Code] = NULL, [FlocCode] = NULL, [ModifiedBy] = @actor2, [ModifiedAt] = @now2
FROM [location].[Node] n
JOIN [ref].[LocationNodeType] ty ON ty.[NodeTypeCode] = n.[NodeTypeCode] AND ISNULL(ty.[CarriesFlocSegment], 1) = 0
WHERE n.[ValidTo] IS NULL AND n.[IsDeleted] = 0 AND (n.[Code] IS NOT NULL OR n.[FlocCode] IS NOT NULL);
GO
