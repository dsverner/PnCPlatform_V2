-- Decision #226 (2026-09-22). One person shows or hides one part of a screen, for themselves. The owner: "the choice
-- should be entirely personal as far as views … the ability to edit at all levels need to be built in as well."
--
-- The person is taken from the session, never from a parameter: whoever calls this writes their own row and no other.
-- @IsShown NULL means "back to what my roles give me" — the standing row is closed, so the answer falls through to the
-- role default and then to the screen's own. Hiding is a preference, never a permission: an item hidden here is still
-- one click away, and only security.fHasPermission refuses anything.
--   50300 no such item on that screen   50301 that part of the screen is always shown   50302 no signed-in person
CREATE PROCEDURE [config].[SetViewItem]
    @ScreenKey NVARCHAR(60),
    @ItemKey NVARCHAR(60),
    @IsShown BIT = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @EntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @Outcome NVARCHAR(20) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();

    -- whose view: the user the session is acting as. A job or a migration has no view of its own.
    DECLARE @user UNIQUEIDENTIFIER;
    SELECT @user = [ActingUserEntityId] FROM [personnel].[Actor] WHERE [ActorId] = @ActorId;
    IF @user IS NULL THROW 50302, N'config.SetViewItem: only a signed-in person has a view of their own to set.', 1;

    SET @ScreenKey = LTRIM(RTRIM(@ScreenKey));
    SET @ItemKey = LTRIM(RTRIM(@ItemKey));
    DECLARE @always BIT, @name NVARCHAR(100);
    SELECT @always = [IsAlways], @name = [Name] FROM [config].[ViewItem]
     WHERE [ScreenKey] = @ScreenKey AND [ItemKey] = @ItemKey AND [IsActive] = 1;
    IF @always IS NULL THROW 50300, N'config.SetViewItem: that screen has no part with that key.', 1;
    IF @IsShown = 0 AND @always = 1 THROW 50301, N'config.SetViewItem: that part of the screen is always shown.', 1;

    -- what stands for this person. @EntityId is an OUTPUT, and the API binds an OUTPUT from the request body, so a
    -- caller can name a row: cleared first, or a person could pass someone else's row id on an item they have none for
    -- and the lookup below would leave it standing. Measured on DEV, 2026-09-22, before this line existed.
    SET @EntityId = NULL;
    DECLARE @was BIT;
    SELECT TOP (1) @EntityId = [EntityId], @was = [IsShown] FROM [config].[UserViewItem]
     WHERE [UserEntityId] = @user AND [ScreenKey] = @ScreenKey AND [ItemKey] = @ItemKey AND [ValidTo] IS NULL AND [IsDeleted] = 0
     ORDER BY [RowSeq] DESC;
    IF @IsShown IS NULL AND @EntityId IS NULL BEGIN SET @Outcome = N'Unchanged'; RETURN; END
    IF @IsShown IS NOT NULL AND @was = @IsShown BEGIN SET @Outcome = N'Unchanged'; RETURN; END

    BEGIN TRANSACTION;
    IF @IsShown IS NULL
    BEGIN
        EXEC [config].[UserViewItem_SoftDelete] @EntityId = @EntityId, @ActorId = @ActorId;
        SET @Outcome = N'Cleared';
    END
    ELSE IF @EntityId IS NULL
    BEGIN
        EXEC [config].[UserViewItem_Add] @UserEntityId = @user, @ScreenKey = @ScreenKey, @ItemKey = @ItemKey,
             @IsShown = @IsShown, @ValidFrom = @now, @ActorId = @ActorId, @EntityId = @EntityId OUTPUT;
        SET @Outcome = N'Set';
    END
    ELSE
    BEGIN
        EXEC [config].[UserViewItem_Revise] @EntityId = @EntityId, @UserEntityId = @user, @ScreenKey = @ScreenKey, @ItemKey = @ItemKey,
             @IsShown = @IsShown, @ValidFrom = @now, @ActorId = @ActorId;
        SET @Outcome = N'Changed';
    END
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"view-item-set","screen":"', STRING_ESCAPE(@ScreenKey, 'json'),
        N'","item":"', STRING_ESCAPE(@ItemKey, 'json'), N'","name":"', STRING_ESCAPE(@name, 'json'),
        N'","from":', CASE WHEN @was IS NULL THEN N'null' ELSE CASE @was WHEN 1 THEN N'true' ELSE N'false' END END,
        N',"to":', CASE WHEN @IsShown IS NULL THEN N'null' ELSE CASE @IsShown WHEN 1 THEN N'true' ELSE N'false' END END, N'}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'config', @SubjectTable = N'UserViewItem',
         @SubjectEntityId = @EntityId, @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now;
    COMMIT TRANSACTION;
END;
GO
GRANT EXECUTE ON [config].[SetViewItem] TO [app_execute];
GO
