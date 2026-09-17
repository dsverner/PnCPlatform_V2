-- SCHEMA-DESIGN §3.1 (80, 87): the seeded allowed (child → parent) pairs. None IsRequired.
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [ref].[LocationNodeTypeParent] AS t
USING (VALUES
    (N'Division',           N'Owner'),
    (N'Station',            N'Division'),
    (N'RightOfWay',         N'Division'),
    -- Region as a parent is retained only until the stations and rights of way are re-parented onto
    -- their division. It is removed in the same change that moves them; removing it first would leave
    -- 231 stations and 255 rights of way violating the rule.
    (N'Station',            N'Region'),
    (N'RightOfWay',         N'Region'),
    (N'Building',           N'Station'),
    (N'Yard',               N'Station'),
    (N'Raceway',            N'Station'),
    (N'Room',               N'Building'),
    (N'Panel',              N'Building'),
    (N'Panel',              N'Room'),
    (N'DevicePosition',     N'Panel'),
    (N'TerminalBlock',      N'Panel'),
    (N'ProtectionFunction', N'DevicePosition'),
    (N'TerminalBlock',      N'DevicePosition'),
    (N'Stud',               N'TerminalBlock'),
    -- #174 (2026-09-17), the owner: "For the client that I am dealing with, the Bay concept doesn't exist. Transformers, PTs,
    -- CTs etc. would each be labelled onsite and then the FLOC would match that tag, so the FLOC for T3 would be
    -- TN-4134-Y230-T3 with no bay reference at all." So equipment (and a junction box) sits directly in the yard. The bay
    -- pairs are kept here but deactivated below rather than deleted: a site that does use bays is one UPDATE away, and no
    -- bay has ever been created in this estate (0 rows, checked 2026-09-17).
    (N'EquipmentPosition',  N'Yard'),
    (N'JunctionBox',        N'Yard'),
    (N'Bay',                N'Yard'),
    (N'EquipmentPosition',  N'Bay'),
    (N'JunctionBox',        N'Bay'),
    (N'TerminalBlock',      N'JunctionBox'),
    (N'Segment',            N'Raceway'),
    (N'Structure',          N'RightOfWay'),
    (N'AttachmentPoint',    N'Structure')
) AS s ([ChildNodeTypeCode], [ParentNodeTypeCode])
ON t.[ChildNodeTypeCode] = s.[ChildNodeTypeCode] AND t.[ParentNodeTypeCode] = s.[ParentNodeTypeCode]
WHEN NOT MATCHED BY TARGET
    THEN INSERT ([ChildNodeTypeCode], [ParentNodeTypeCode], [IsRequired], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
         VALUES (s.[ChildNodeTypeCode], s.[ParentNodeTypeCode], 0, @actor, @now, @actor, @now);
GO
GO
-- #174: the bay level is not used by this client (see the note above). Deactivated, not removed.
UPDATE [ref].[LocationNodeTypeParent]
   SET [IsActive] = 0, [ModifiedBy] = '00000000-0000-0000-0000-000000000001', [ModifiedAt] = SYSDATETIMEOFFSET()
 WHERE [IsActive] = 1
   AND ([ChildNodeTypeCode] = N'Bay' OR [ParentNodeTypeCode] = N'Bay');
GO
