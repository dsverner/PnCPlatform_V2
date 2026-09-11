-- a typed value as the grammar's value JSON from a catalogue DataType and a text reading
CREATE FUNCTION [compliance].[fTypedValue] (@dataType NVARCHAR(20), @text NVARCHAR(400), @unit NVARCHAR(20), @base NVARCHAR(20), @refKind NVARCHAR(60), @why NVARCHAR(200))
RETURNS NVARCHAR(MAX)
AS
BEGIN
    IF @text IS NULL RETURN CONCAT(N'{"k":"unk","why":["', STRING_ESCAPE(@why, 'json'), N'"]}');
    IF @dataType IN (N'Integer', N'Decimal')
    BEGIN
        DECLARE @n DECIMAL(28,10) = TRY_CONVERT(DECIMAL(28,10), @text);
        IF @n IS NULL RETURN CONCAT(N'{"k":"unk","why":["', STRING_ESCAPE(@why, 'json'), N': not numeric"]}');
        RETURN CONCAT(N'{"k":"num","v":"', [compliance].[fDecText](@n), N'"',
                      CASE WHEN @unit IS NULL THEN N'' ELSE N',"u":"' + STRING_ESCAPE(@unit, 'json') + N'"' END,
                      CASE WHEN @base IS NULL THEN N'' ELSE N',"b":"' + @base + N'"' END, N'}');
    END
    IF @dataType = N'Boolean' RETURN CONCAT(N'{"k":"bool","v":', CASE WHEN @text IN (N'true', N'1') THEN N'true' ELSE N'false' END, N'}');
    IF @dataType = N'DateTime'
    BEGIN
        DECLARE @d DATETIMEOFFSET(7) = TRY_CONVERT(DATETIMEOFFSET(7), @text);
        IF @d IS NULL RETURN CONCAT(N'{"k":"unk","why":["', STRING_ESCAPE(@why, 'json'), N': not a date"]}');
        RETURN CONCAT(N'{"k":"date","v":"', CONVERT(NVARCHAR(40), @d, 127), N'"}');
    END
    IF @dataType = N'Reference' RETURN CONCAT(N'{"k":"ref","id":"', LOWER(@text), N'","kind":"', ISNULL(@refKind, N''), N'"}');
    RETURN CONCAT(N'{"k":"text","v":"', STRING_ESCAPE(@text, 'json'), N'"}');
END;
GO
GO
