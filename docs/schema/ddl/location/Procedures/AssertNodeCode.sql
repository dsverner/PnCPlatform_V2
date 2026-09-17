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
CREATE PROCEDURE [location].[AssertNodeCode]
    @Caller NVARCHAR(40),
    @Code NVARCHAR(40) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @Code IS NULL RETURN;
    SET @Code = LTRIM(RTRIM(@Code));
    IF @Code = N'' RETURN;                      -- the clear sentinel; the caller turns it into NULL
    IF @Code LIKE N'%[-]%' OR @Code LIKE N'%[' + NCHAR(9) + NCHAR(10) + NCHAR(11) + NCHAR(12) + NCHAR(13) + N' ]%'
    BEGIN
        DECLARE @m NVARCHAR(400) = CONCAT(@Caller, N': ', @Code,
            N' is not a usable code — a code may not contain ''-'', which separates the FLOC''s segments, nor any whitespace.');
        THROW 50213, @m, 1;
    END
END;
GO
