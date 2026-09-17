-- #179 (2026-09-17). Every building gets a code and a name it can be recognised by.
--
-- The owner, 2026-09-17, on the settings book: "It would be helpful for the engineers and techs if the 'Locations'
-- list box at the left, actually displayed the BDGx Names and filtered the data on those. That way there would be
-- three 'buildings'", and "the lettering should be all capital letters as well".
--
-- Why there is anything to seed. The importer creates one Station AND one placeholder building from each distinct
-- legacy LOCATION string, because the legacy database models no building at all; the placeholder is named
-- 'Building (unknown ... legacy has no buildings)' and carries no code. Measured on PnCPlatform_V2_DEV,
-- 2026-09-17: 232 current Building nodes, 228 of them still that placeholder. A list of 228 identical names is no
-- use to anyone, so each is given its own station's name -- a derivation from what the platform already holds, not
-- an invention -- and the code BDG1, the first building at that station. #178 already named Eel River's three,
-- which are the only ones where a station has more than one building.
--
-- EXPECTED AFTER THIS SEED: a lone building reads the same as its station, so the settings book's list reads as it
-- always did except at Eel River, where one entry becomes three. That repetition is deliberate: the list is the
-- buildings now, and a station with one building has one entry whose name a person already recognises.
--
-- Idempotent twice over: only a building still carrying the placeholder name and no code is renamed, and the
-- upper-casing pass matches only a name that is not already upper case. A second publish changes nothing, and a
-- name a person has set by hand is never disturbed. Audited like the other seeds -- the system actor on
-- ModifiedBy/ModifiedAt, with system versioning keeping the prior row in location.Node_History. This is the
-- platform writing down what it already held, the same reasoning Seed_location_StationCodes gives (#175).
IF OBJECT_ID(N'[location].[fComposeFloc]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @sys UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();

-- 1. the placeholder buildings take their station's name and the code BDG1
WITH candidate AS (
    SELECT n.[RowSeq],
           [ParentFloc] = p.[FlocCode],
           [NewName]    = p.[Name],
           -- two placeholders under one station would both want BDG1 and breach UX_Node_ParentCode, and a seed
           -- must never be the thing that fails a deployment. There are none today (checked on DEV, 2026-09-17);
           -- if one ever appears both are left alone for a person to settle rather than one chosen at random.
           [Claims]     = COUNT(*) OVER (PARTITION BY n.[ParentEntityId])
    FROM [location].[Node] n
    -- the parent station, read from the base table in the current-row form the filtered indexes use (#169)
    JOIN [location].[Node] p ON p.[EntityId] = n.[ParentEntityId] AND p.[ValidTo] IS NULL AND p.[IsDeleted] = 0
    WHERE n.[NodeTypeCode] = N'Building' AND n.[ValidTo] IS NULL AND n.[IsDeleted] = 0
      AND n.[Code] IS NULL                                   -- idempotent; never disturbs a code a person set
      AND n.[Name] LIKE N'Building (unknown%'                 -- only the importer's placeholder
      AND p.[Name] IS NOT NULL AND LEN(LTRIM(RTRIM(p.[Name]))) BETWEEN 1 AND 200
      AND NOT EXISTS (SELECT 1 FROM [location].[Node] sib
                      WHERE sib.[ValidTo] IS NULL AND sib.[IsDeleted] = 0 AND sib.[Code] = N'BDG1'
                        AND sib.[ParentEntityId] = n.[ParentEntityId])
)
UPDATE n
SET [Code]       = N'BDG1',
    [Name]       = c.[NewName],
    [FlocCode]   = [location].[fComposeFloc](c.[ParentFloc], N'BDG1'),
    [ModifiedBy] = @sys,
    [ModifiedAt] = @now
FROM [location].[Node] n JOIN candidate c ON c.[RowSeq] = n.[RowSeq]
WHERE c.[Claims] = 1;
GO

-- 2. the owner, 2026-09-17: "the lettering should be all capital letters as well". Every other name in the list
-- came out of the legacy database in capitals; the names typed since have not, and a list that mixes the two reads
-- as though the new entries belong to something else. Stations and buildings only -- the level the settings book
-- lists. A smoke fixture's name is left alone: it is not a place, and the fixtures assert their own names.
DECLARE @sys2 UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now2 DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
UPDATE [location].[Node]
SET [Name]       = UPPER([Name]),
    [ModifiedBy] = @sys2,
    [ModifiedAt] = @now2
WHERE [NodeTypeCode] IN (N'Station', N'Building')
  AND [ValidTo] IS NULL AND [IsDeleted] = 0
  AND [Name] COLLATE Latin1_General_BIN2 <> UPPER([Name]) COLLATE Latin1_General_BIN2
  AND [Name] NOT LIKE N'Building (unknown%'                  -- a placeholder nobody has named yet stays as it is
  AND [Name] NOT LIKE N'W4[_]%' AND [Name] NOT LIKE N'Smoke%';
GO
