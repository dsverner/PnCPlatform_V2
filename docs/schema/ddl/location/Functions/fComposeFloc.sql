-- #175 (2026-09-17): the FLOC rule, in the one place the platform holds it. A node's FlocCode is the unbroken
-- run of coded ancestors ending at that node, so:
--   @code IS NULL       -> NULL          (a node with no code has no FLOC)
--   @parentFloc IS NULL -> @code         (the chain starts fresh at the first coded ancestor)
--   otherwise           -> @parentFloc + '-' + @code
-- NB Power carries no code, so the FLOC begins at the division: TN, TN-4403, TN-4403-Y230, TN-4403-Y230-T3.
-- The platform never invents a missing segment: withdraw Y230's code and its transformer reads T3 — a gap a
-- person can see — not the guessed TN-4403-T3, and not nothing at all.
-- location.AddNode, location.RenameNode and location.MoveNode all compose through here; nothing else writes
-- location.Node.FlocCode. '-' is the separator, which is why location.AssertNodeCode refuses a code holding one.
CREATE FUNCTION [location].[fComposeFloc] (@parentFloc NVARCHAR(400), @code NVARCHAR(40))
RETURNS NVARCHAR(400)
AS
BEGIN
    IF @code IS NULL RETURN NULL;
    IF @parentFloc IS NULL RETURN @code;
    RETURN @parentFloc + N'-' + @code;
END;
GO
