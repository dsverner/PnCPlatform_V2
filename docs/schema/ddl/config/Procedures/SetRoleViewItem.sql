-- Decision #226 (2026-09-22). What a role starts people with: the default answer for one part of one screen. An
-- Administrator's act, and it changes only what people who have made no choice of their own see — a choice someone has
-- made for themselves is never overwritten from here. @IsShown NULL removes the role's answer, leaving the screen's own.
--   50300 no such item on that screen   50301 that part of the screen is always shown   50303 no such role
CREATE PROCEDURE [config].[SetRoleViewItem]
    @RoleCode NVARCHAR(40),
    @ScreenKey NVARCHAR(60),
    @ItemKey NVARCHAR(60),
    @IsShown BIT = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @Outcome NVARCHAR(20) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    SET @RoleCode = LTRIM(RTRIM(@RoleCode));
    SET @ScreenKey = LTRIM(RTRIM(@ScreenKey));
    SET @ItemKey = LTRIM(RTRIM(@ItemKey));

    IF NOT EXISTS (SELECT 1 FROM [security].[Role] WHERE [RoleCode] = @RoleCode AND [IsActive] = 1)
        THROW 50303, N'config.SetRoleViewItem: there is no active role with that code.', 1;
    DECLARE @always BIT;
    SELECT @always = [IsAlways] FROM [config].[ViewItem]
     WHERE [ScreenKey] = @ScreenKey AND [ItemKey] = @ItemKey AND [IsActive] = 1;
    IF @always IS NULL THROW 50300, N'config.SetRoleViewItem: that screen has no part with that key.', 1;
    -- the same rule as config.SetViewItem: a part the screen exists for is not turned off, for a group either
    IF @IsShown = 0 AND @always = 1 THROW 50301, N'config.SetRoleViewItem: that part of the screen is always shown.', 1;

    DECLARE @was BIT;
    SELECT @was = [IsShown] FROM [config].[RoleViewItem]
     WHERE [RoleCode] = @RoleCode AND [ScreenKey] = @ScreenKey AND [ItemKey] = @ItemKey AND [IsActive] = 1;
    IF (@was IS NULL AND @IsShown IS NULL) OR @was = @IsShown BEGIN SET @Outcome = N'Unchanged'; RETURN; END

    BEGIN TRANSACTION;
    IF @IsShown IS NULL
    BEGIN
        EXEC [config].[RoleViewItem_Deactivate] @RoleCode = @RoleCode, @ScreenKey = @ScreenKey, @ItemKey = @ItemKey, @ActorId = @ActorId;
        SET @Outcome = N'Cleared';
    END
    ELSE
    BEGIN
        EXEC [config].[RoleViewItem_Upsert] @RoleCode = @RoleCode, @ScreenKey = @ScreenKey, @ItemKey = @ItemKey,
             @IsShown = @IsShown, @ActorId = @ActorId;
        SET @Outcome = CASE WHEN @was IS NULL THEN N'Set' ELSE N'Changed' END;
    END
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"role-view-item-set","role":"', STRING_ESCAPE(@RoleCode, 'json'),
        N'","screen":"', STRING_ESCAPE(@ScreenKey, 'json'), N'","item":"', STRING_ESCAPE(@ItemKey, 'json'),
        N'","from":', CASE WHEN @was IS NULL THEN N'null' ELSE CASE @was WHEN 1 THEN N'true' ELSE N'false' END END,
        N',"to":', CASE WHEN @IsShown IS NULL THEN N'null' ELSE CASE @IsShown WHEN 1 THEN N'true' ELSE N'false' END END, N'}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'config', @SubjectTable = N'RoleViewItem',
         @SubjectEntityId = NULL, @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now;
    COMMIT TRANSACTION;
END;
GO
GRANT EXECUTE ON [config].[SetRoleViewItem] TO [app_execute];
GO
