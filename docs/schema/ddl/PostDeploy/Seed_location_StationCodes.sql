-- #175 (2026-09-17). Every station already carries its number, as a location.AlternateKey row of kind
-- StationNumber: the number an engineer says out loud and the second segment of the FLOC. This gives each
-- station that number as its location.Node.Code, so the platform composes the FLOC from what it already knows
-- rather than asking anyone to type 250 numbers again. Nothing is invented here — the value is the station's
-- own key, copied across.
--
-- Measured on PnCPlatform_V2_DEV, 2026-09-17: 256 current Station nodes, 250 of them with a current
-- StationNumber. The six without one get no code, and so no FLOC, which is the right answer until someone
-- gives them one. No station carries two numbers and no number is shared, so the new UX_Node_ParentCode
-- cannot be breached by this seed; every value is four to seven characters with no '-' and no whitespace, so
-- location.AssertNodeCode's rule is not breached either.
--
-- EXPECTED AFTER THIS SEED: a station's Code reads 4403 and its FlocCode reads NULL. The FLOC is the unbroken
-- run of coded ancestors, and no division has been given a code yet — nobody has typed TN. That is correct,
-- not a fault: the platform never invents a missing segment. The moment the owner gives Transmission its code
-- on the location screen, location.RenameNode rewrites FlocCode for the division and its whole subtree, and
-- the stations read TN-4403 from then on.
--
-- Idempotent: only a station whose Code is still NULL is touched, so a code a person has set by hand is never
-- disturbed and a second publish changes nothing. Audited the way the other seeds are — the system actor on
-- ModifiedBy/ModifiedAt, and system versioning keeps the prior row in location.Node_History. This is an
-- in-place update of a derived column, not a new fact about the station: nothing about the station changed,
-- the platform merely learned to write down what it already held (the same reasoning location.RenameNode
-- gives for rewriting a subtree's FlocCode in place).
IF OBJECT_ID(N'[location].[fComposeFloc]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @sys UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();

WITH candidate AS (
    SELECT n.[RowSeq],
           [ParentFloc] = p.[FlocCode],
           [NewCode]    = k.[KeyValue],
           -- two stations under one parent claiming one number would break UX_Node_ParentCode, and a seed must
           -- never be the thing that fails a deployment. There are none today (checked on DEV, 2026-09-17);
           -- if one ever appears, both are left uncoded for a person to settle rather than one chosen at random.
           [Claims]     = COUNT(*) OVER (PARTITION BY n.[ParentEntityId], k.[KeyValue])
    FROM [location].[Node] n
    -- the parent (a Division today) read from the base table in the current-row form the filtered indexes use (#169)
    LEFT JOIN [location].[Node] p ON p.[EntityId] = n.[ParentEntityId] AND p.[ValidTo] IS NULL AND p.[IsDeleted] = 0
    CROSS APPLY (SELECT TOP (1) ak.[KeyValue] FROM [location].[AlternateKey] ak
                 WHERE ak.[SubjectEntityId] = n.[EntityId] AND ak.[KeyKindCode] = N'StationNumber'
                   AND ak.[ValidTo] IS NULL AND ak.[IsDeleted] = 0
                 ORDER BY ak.[IsPrimaryLabel] DESC, ak.[RowSeq]) k
    WHERE n.[NodeTypeCode] = N'Station' AND n.[ValidTo] IS NULL AND n.[IsDeleted] = 0
      AND n.[Code] IS NULL                                  -- idempotent; never disturbs a code a person set
      AND LEN(k.[KeyValue]) BETWEEN 1 AND 40
      AND k.[KeyValue] NOT LIKE N'%[-]%'                     -- the rule location.AssertNodeCode enforces, held to here too
      AND k.[KeyValue] NOT LIKE N'%[' + NCHAR(9) + NCHAR(10) + NCHAR(11) + NCHAR(12) + NCHAR(13) + N' ]%'
      AND NOT EXISTS (SELECT 1 FROM [location].[Node] sib
                      WHERE sib.[ValidTo] IS NULL AND sib.[IsDeleted] = 0 AND sib.[Code] = k.[KeyValue]
                        AND (sib.[ParentEntityId] = n.[ParentEntityId]
                             OR (sib.[ParentEntityId] IS NULL AND n.[ParentEntityId] IS NULL)))
)
UPDATE n
SET [Code]       = c.[NewCode],
    [FlocCode]   = [location].[fComposeFloc](c.[ParentFloc], c.[NewCode]),
    [ModifiedBy] = @sys,
    [ModifiedAt] = @now
FROM [location].[Node] n JOIN candidate c ON c.[RowSeq] = n.[RowSeq]
WHERE c.[Claims] = 1;
GO
