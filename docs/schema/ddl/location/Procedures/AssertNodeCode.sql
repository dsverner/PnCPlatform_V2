-- #175 (2026-09-17): the one place a node's Code is checked, so location.AddNode and location.RenameNode
-- cannot drift apart on what a code may be. @Caller is the calling procedure's own name, so the message reads
-- in that procedure's voice the way its neighbours' messages do.
--
-- A code may not hold '-' — that is the FLOC separator, and a code containing one would make the composed
-- FLOC ambiguous (TN-4403-Y230 could not be read back into its segments) — nor any whitespace, which no field
-- tag carries and which nobody can see on a screen.
--
-- @Code comes back trimmed. NULL comes back NULL and an empty string comes back empty: the two must stay
-- distinguishable, because to the callers NULL means "not given, keep what is there" and empty means "clear
-- it" (src/PnC.Api/Data/SqlSession.cs maps a JSON null to an omitted parameter, so a client cannot send NULL).
-- The callers collapse empty to NULL themselves, after they have read that difference.
--
-- #176 (2026-09-17): the sibling check. One parent's children may not repeat a code, or the FLOC would name two
-- nodes. UX_Node_ParentCode already forbids it, but an index refuses in SQL Server's words — the owner met
-- "Cannot insert duplicate key row in object 'location.Node' with unique index 'UX_Node_ParentCode'. The duplicate
-- key value is (20d4c714-..., 4416)", which names neither the code nor the node that holds it. So the code is
-- checked here first and the refusal NAMES THE SIBLING, and the index stays as the guarantee behind it (a race
-- between two sessions still lands on the index, which is the point of having it).
-- @SelfEntityId is the node being renamed, excluded from the search so that saving a node without changing its
-- code is not a collision with itself. AddNode passes none, because the node does not exist yet.
-- #180 (2026-09-17): a type that adds no segment to the FLOC takes no code either. The owner: "the device FLOC should
-- stop at TN-4134-BDG1-PNL12-21A and that FLOC position should be assigned to the device (SEL-411L etc.)" — his client
-- shortened the tag to the position on purpose, so schematic drawings would not get busy, and everyone there knows a 21
-- element covers more than distance. The elements are still recorded as nodes (a scheme's members ARE protection
-- functions, which is what lets a relay be swapped without touching the scheme); they simply never appear in a tag.
-- Refused here rather than hidden on a screen, so no path into the platform can put one there.
CREATE PROCEDURE [location].[AssertNodeCode]
    @Caller NVARCHAR(40),
    @Code NVARCHAR(40) OUTPUT,
    @ParentEntityId UNIQUEIDENTIFIER = NULL,
    @SelfEntityId UNIQUEIDENTIFIER = NULL,
    @NodeTypeCode NVARCHAR(40) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @Code IS NULL RETURN;
    SET @Code = LTRIM(RTRIM(@Code));
    IF @Code = N'' RETURN;                      -- the clear sentinel; the caller turns it into NULL

    -- #180: the FLOC stops here, so there is nothing for a code to be a segment of
    IF @NodeTypeCode IS NOT NULL AND EXISTS (SELECT 1 FROM [ref].[LocationNodeType]
                                             WHERE [NodeTypeCode] = @NodeTypeCode AND ISNULL([CarriesFlocSegment], 1) = 0)
    BEGIN
        DECLARE @t NVARCHAR(400) = CONCAT(@Caller, N': a ', @NodeTypeCode,
            N' carries no code, because the FLOC ends at the position the device stands in. Record what it does in its name.');
        THROW 50215, @t, 1;
    END
    IF @Code LIKE N'%[-]%' OR @Code LIKE N'%[' + NCHAR(9) + NCHAR(10) + NCHAR(11) + NCHAR(12) + NCHAR(13) + N' ]%'
    BEGIN
        DECLARE @m NVARCHAR(400) = CONCAT(@Caller, N': ', @Code,
            N' is not a usable code — a code may not contain ''-'', which separates the FLOC''s segments, nor any whitespace.');
        THROW 50213, @m, 1;
    END

    -- #176: a sibling already carrying this code, named so the person knows which one
    IF @ParentEntityId IS NOT NULL
    BEGIN
        DECLARE @twin NVARCHAR(200) = (
            SELECT TOP (1) n.[Name] FROM [location].[Node] n
            WHERE n.[ParentEntityId] = @ParentEntityId AND n.[Code] = @Code
              AND n.[ValidTo] IS NULL AND n.[IsDeleted] = 0
              AND (@SelfEntityId IS NULL OR n.[EntityId] <> @SelfEntityId)
            ORDER BY n.[RowSeq] DESC);
        IF @twin IS NOT NULL
        BEGIN
            DECLARE @d NVARCHAR(400) = CONCAT(@Caller, N': the code ', @Code, N' is already used by ', @twin,
                N' here. One code names one node, so pick another.');
            THROW 50214, @d, 1;
        END
    END
END;
GO
