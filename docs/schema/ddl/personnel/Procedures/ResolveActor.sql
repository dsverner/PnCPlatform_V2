-- SCHEMA-DESIGN §0.3 (72), §11.1 (152), §11.5 (156). Resolves the actor for the current session and
-- returns its immutable personnel.Actor row, creating it on first sight of a combination.
--
-- Resolution order:
--   1. SESSION_CONTEXT('ActorId') — set by the application after its own resolution; must exist.
--   2. SESSION_CONTEXT('UserPrincipalName') → enabled security.User → its Person.
--        @SponsoredPersonEntityId given → ActorKind Sponsored (a non-user person the acting user
--          enters work for; person = the sponsored person, acting user = the session's user).
--        else a security.Delegation in force TO the user's person (StartsAt ≤ now < EndsAt, not
--          revoked, current row) → ActorKind Delegated, DelegationEntityId set; if several are in
--          force, SESSION_CONTEXT('DelegationEntityId') selects one, otherwise the earliest-starting.
--        else ActorKind Self.
--   3. Otherwise a System actor named after ORIGINAL_LOGIN() (scheduled jobs, migrations,
--      developers on DEV).
-- Held-versus-exercised (vision §3.5) is therefore on every table without a second column.
CREATE PROCEDURE [personnel].[ResolveActor]
    @ActorId UNIQUEIDENTIFIER OUTPUT,
    @SponsoredPersonEntityId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();

    DECLARE @ctx UNIQUEIDENTIFIER = TRY_CONVERT(UNIQUEIDENTIFIER, SESSION_CONTEXT(N'ActorId'));
    IF @ctx IS NOT NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [personnel].[Actor] WHERE [ActorId] = @ctx)
            THROW 50001, N'SESSION_CONTEXT ActorId does not name an existing actor.', 1;
        SET @ActorId = @ctx;
        RETURN;
    END

    DECLARE @upn NVARCHAR(200) = TRY_CONVERT(NVARCHAR(200), SESSION_CONTEXT(N'UserPrincipalName'));
    IF @upn IS NOT NULL
    BEGIN
        DECLARE @userEntity UNIQUEIDENTIFIER, @personEntity UNIQUEIDENTIFIER;
        SELECT TOP (1) @userEntity = [EntityId], @personEntity = [PersonEntityId]
        FROM [security].[User]
        WHERE [UserPrincipalName] = @upn AND [IsEnabled] = 1 AND [IsDeleted] = 0
          AND [ValidFrom] <= @now AND ([ValidTo] IS NULL OR [ValidTo] > @now)
        ORDER BY [ValidFrom] DESC, [RowSeq] DESC;
        IF @userEntity IS NULL THROW 50002, N'SESSION_CONTEXT UserPrincipalName does not name an enabled user.', 1;

        DECLARE @kind NVARCHAR(20) = N'Self', @person UNIQUEIDENTIFIER = @personEntity, @delegation UNIQUEIDENTIFIER = NULL;
        IF @SponsoredPersonEntityId IS NOT NULL
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [personnel].[PersonRegistry] WHERE [EntityId] = @SponsoredPersonEntityId)
                THROW 50003, N'@SponsoredPersonEntityId is not a registered person.', 1;
            SET @kind = N'Sponsored'; SET @person = @SponsoredPersonEntityId;
        END
        ELSE
        BEGIN
            DECLARE @wanted UNIQUEIDENTIFIER = TRY_CONVERT(UNIQUEIDENTIFIER, SESSION_CONTEXT(N'DelegationEntityId'));
            SELECT TOP (1) @delegation = [EntityId]
            FROM [security].[Delegation]
            WHERE [ToPersonEntityId] = @personEntity AND [IsDeleted] = 0 AND [RevokedByActorId] IS NULL
              AND [ValidFrom] <= @now AND ([ValidTo] IS NULL OR [ValidTo] > @now)
              AND [StartsAt] <= @now AND ([EndsAt] IS NULL OR [EndsAt] > @now)
              AND (@wanted IS NULL OR [EntityId] = @wanted)
            ORDER BY [StartsAt], [RowSeq];
            IF @delegation IS NOT NULL SET @kind = N'Delegated';
        END

        SELECT @ActorId = [ActorId] FROM [personnel].[Actor]
        WHERE [ActorKind] = @kind AND [PersonEntityId] = @person AND [ActingUserEntityId] = @userEntity
          AND (([DelegationEntityId] IS NULL AND @delegation IS NULL) OR [DelegationEntityId] = @delegation);
        IF @ActorId IS NULL
        BEGIN
            SET @ActorId = NEWID();
            INSERT [personnel].[Actor] ([ActorId], [PersonEntityId], [ActingUserEntityId], [ActorKind], [DelegationEntityId])
            VALUES (@ActorId, @person, @userEntity, @kind, @delegation);
        END
        RETURN;
    END

    DECLARE @systemName NVARCHAR(100) = N'Login:' + LEFT(ORIGINAL_LOGIN(), 94);
    SELECT @ActorId = [ActorId] FROM [personnel].[Actor]
    WHERE [ActorKind] = N'System' AND [SystemName] = @systemName;
    IF @ActorId IS NULL
    BEGIN
        SET @ActorId = NEWID();
        INSERT [personnel].[Actor] ([ActorId], [ActorKind], [SystemName]) VALUES (@ActorId, N'System', @systemName);
    END
END;
GO
