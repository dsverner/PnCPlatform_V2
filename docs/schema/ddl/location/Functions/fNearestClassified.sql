-- #173 (2026-09-17): the classification of the nearest node at or above @nodeEntityId that carries one of @kindCode.
-- The owner, 2026-09-17: the CIP requirements follow from the impact rating "of building that the device is in" — so a
-- rating recorded on the building beats one on the station, and while the migrated buildings are placeholders (250 of
-- them, one per station, every one named "Building (unknown — legacy has no buildings)") the station's value still rules.
-- The group classifies at whichever level it models; this function finds the nearest answer.
--
-- The hierarchy is ProtectionFunction → DevicePosition → Panel → Room → Building → Station → Division → Owner, so the
-- walk covers the node itself and seven ancestors. location.fStationOf keeps its own job (it looks for a node type, not
-- a classification) and its own shape; this one is written differently, and deliberately:
--
-- HOW IT PERFORMS. Seven steps up the tree, then one seek per level into the classifications — fifteen index seeks at
-- the worst, no scan of either table, whatever the size of location.Node or asset.Classification:
--   * each step up is a singleton seek of IX_Node_Entity ([EntityId], [ValidFrom]) (with a key lookup for
--     ParentEntityId, and ValidTo / IsDeleted as residuals) — the access path location.fStationOf uses. The steps are
--     written out in sequence rather than as a self-joined chain per level, so the walk costs seven seeks and not the
--     twenty-eight a per-level chain of the fStationOf shape would, and it stops finding ancestors at the root;
--   * the lookup joins the eight ancestors, as a row constructor, to asset.Classification in the current-row form
--     (ValidTo IS NULL AND IsDeleted = 0), which is exactly the filter of UX_Classification_SubjectKind
--     ([SubjectKind], [SubjectEntityId], [ClassificationKindCode]) — so the optimiser seeks that filtered unique index
--     per level and takes the lowest Level that matched.
-- Measured on DEV, 2026-09-17, from a real ProtectionFunction node: the actual plan is Index Seek on IX_Node_Entity,
-- Clustered Index Seek on PK_Node and PK_Classification, Index Seek on UX_Classification_SubjectKind, with the only
-- "scan" being the Constant Scan of the row constructor; the whole batch round-tripped in 22 ms from the build laptop.
-- Decision #172 (2026-09-17: an OR-shaped predicate in the read-scope function cost 19 s) is why the predicates are in
-- that form. There is no (a = b OR c LIKE d) here, and no OR between the temporal columns: writing
-- "(ValidTo IS NULL OR ValidTo > @at)" would disqualify the filtered index and put a scan of asset.Classification under
-- every device on every compliance pass. The consequence, stated plainly: @at bounds ValidFrom only — the answer is the
-- current classification of the nearest ancestor, not the classification as it stood at @at. Asking the historical
-- question needs a second function reading FOR SYSTEM_TIME, not a looser predicate here.
CREATE FUNCTION [location].[fNearestClassified]
    (@nodeEntityId UNIQUEIDENTIFIER, @kindCode NVARCHAR(40), @at DATETIMEOFFSET(7))
RETURNS NVARCHAR(60)
AS
BEGIN
    IF @nodeEntityId IS NULL OR @kindCode IS NULL RETURN NULL;
    DECLARE @a0 UNIQUEIDENTIFIER = @nodeEntityId,
            @a1 UNIQUEIDENTIFIER, @a2 UNIQUEIDENTIFIER, @a3 UNIQUEIDENTIFIER,
            @a4 UNIQUEIDENTIFIER, @a5 UNIQUEIDENTIFIER, @a6 UNIQUEIDENTIFIER, @a7 UNIQUEIDENTIFIER;
    SELECT TOP (1) @a1 = n.[ParentEntityId] FROM [location].[Node] n
    WHERE n.[EntityId] = @a0 AND n.[ValidTo] IS NULL AND n.[IsDeleted] = 0 ORDER BY n.[ValidFrom] DESC, n.[RowSeq] DESC;
    SELECT TOP (1) @a2 = n.[ParentEntityId] FROM [location].[Node] n
    WHERE n.[EntityId] = @a1 AND n.[ValidTo] IS NULL AND n.[IsDeleted] = 0 ORDER BY n.[ValidFrom] DESC, n.[RowSeq] DESC;
    SELECT TOP (1) @a3 = n.[ParentEntityId] FROM [location].[Node] n
    WHERE n.[EntityId] = @a2 AND n.[ValidTo] IS NULL AND n.[IsDeleted] = 0 ORDER BY n.[ValidFrom] DESC, n.[RowSeq] DESC;
    SELECT TOP (1) @a4 = n.[ParentEntityId] FROM [location].[Node] n
    WHERE n.[EntityId] = @a3 AND n.[ValidTo] IS NULL AND n.[IsDeleted] = 0 ORDER BY n.[ValidFrom] DESC, n.[RowSeq] DESC;
    SELECT TOP (1) @a5 = n.[ParentEntityId] FROM [location].[Node] n
    WHERE n.[EntityId] = @a4 AND n.[ValidTo] IS NULL AND n.[IsDeleted] = 0 ORDER BY n.[ValidFrom] DESC, n.[RowSeq] DESC;
    SELECT TOP (1) @a6 = n.[ParentEntityId] FROM [location].[Node] n
    WHERE n.[EntityId] = @a5 AND n.[ValidTo] IS NULL AND n.[IsDeleted] = 0 ORDER BY n.[ValidFrom] DESC, n.[RowSeq] DESC;
    SELECT TOP (1) @a7 = n.[ParentEntityId] FROM [location].[Node] n
    WHERE n.[EntityId] = @a6 AND n.[ValidTo] IS NULL AND n.[IsDeleted] = 0 ORDER BY n.[ValidFrom] DESC, n.[RowSeq] DESC;

    DECLARE @value NVARCHAR(60);
    SELECT TOP (1) @value = c.[ClassificationValue]
    FROM (VALUES (0, @a0), (1, @a1), (2, @a2), (3, @a3), (4, @a4), (5, @a5), (6, @a6), (7, @a7)) AS a ([Level], [EntityId])
    JOIN [asset].[Classification] c
      ON c.[SubjectKind] = N'Node'
     AND c.[SubjectEntityId] = a.[EntityId]
     AND c.[ClassificationKindCode] = @kindCode
     AND c.[ValidTo] IS NULL
     AND c.[IsDeleted] = 0
    WHERE c.[ValidFrom] <= @at
    ORDER BY a.[Level];
    RETURN @value;
END;
GO
