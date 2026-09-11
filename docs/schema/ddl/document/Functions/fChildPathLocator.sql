-- SCHEMA-DESIGN §8.1 (125). A new path_locator for a child of @Parent in the document.FileStore FileTable,
-- derived from a GUID the caller supplies (NEWID() is not allowed inside a function). This is the
-- FileTable convention for T-SQL inserts: three integers from the GUID's bytes form a unique child
-- label under the parent's path. Used by document.File_Write.
CREATE FUNCTION [document].[fChildPathLocator] (@Parent HIERARCHYID, @Seed UNIQUEIDENTIFIER)
RETURNS HIERARCHYID
AS
BEGIN
    DECLARE @b BINARY(16) = CONVERT(BINARY(16), @Seed);
    DECLARE @p HIERARCHYID = ISNULL(@Parent, hierarchyid::GetRoot());
    DECLARE @parentPath NVARCHAR(4000) = @p.ToString();
    RETURN hierarchyid::Parse(@parentPath
        + CONVERT(NVARCHAR(20), CONVERT(BIGINT, CONVERT(VARBINARY(6), SUBSTRING(@b, 1, 6)))) + N'.'
        + CONVERT(NVARCHAR(20), CONVERT(BIGINT, CONVERT(VARBINARY(6), SUBSTRING(@b, 7, 6)))) + N'.'
        + CONVERT(NVARCHAR(20), CONVERT(BIGINT, CONVERT(VARBINARY(4), SUBSTRING(@b, 13, 4)))) + N'/');
END;
GO
