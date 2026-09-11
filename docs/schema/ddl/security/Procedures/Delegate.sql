-- SCHEMA-DESIGN §11.5 (decision 156); PROCEDURES.md #34.
-- Records a delegation of a positional role from one person to another for a period. Refuses an
-- assignment role (§11.3: only positional roles are delegable; an assignment is a grant against a
-- request, never passed on). The authority passes and returns at EndsAt — personnel.ResolveActor
-- honours only delegations in force, so nothing is reassigned. Logs a Grant action.
CREATE PROCEDURE [security].[Delegate]
    @FromPersonEntityId UNIQUEIDENTIFIER,
    @ToPersonEntityId UNIQUEIDENTIFIER,
    @RoleCode NVARCHAR(40),
    @StartsAt DATETIMEOFFSET(7) = NULL,
    @EndsAt DATETIMEOFFSET(7) = NULL,
    @Reason NVARCHAR(400) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,
    @EntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @RowId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @StartsAt = ISNULL(@StartsAt, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;

    DECLARE @kind NVARCHAR(20), @active BIT;
    SELECT @kind = [RoleKind], @active = [IsActive] FROM [security].[Role] WHERE [RoleCode] = @RoleCode;
    IF @active IS NULL OR @active = 0 THROW 50230, N'security.Delegate: unknown or inactive role.', 1;
    IF ISNULL(@kind, N'') <> N'Positional'
    BEGIN
        DECLARE @m NVARCHAR(400) = CONCAT(N'security.Delegate: role ', @RoleCode, N' is not positional; only positional roles are delegated (§11.5).');
        THROW 50231, @m, 1;
    END;
    IF @FromPersonEntityId = @ToPersonEntityId THROW 50232, N'security.Delegate: a person cannot delegate to themself.', 1;
    IF @EndsAt IS NOT NULL AND @EndsAt <= @StartsAt THROW 50233, N'security.Delegate: EndsAt must follow StartsAt.', 1;
    IF NOT EXISTS (SELECT 1 FROM [personnel].[vPerson] WHERE [EntityId] = @FromPersonEntityId)
       OR NOT EXISTS (SELECT 1 FROM [personnel].[vPerson] WHERE [EntityId] = @ToPersonEntityId)
        THROW 50234, N'security.Delegate: both persons must be current.', 1;

    BEGIN TRANSACTION;
    EXEC [security].[Delegation_Add] @FromPersonEntityId = @FromPersonEntityId, @ToPersonEntityId = @ToPersonEntityId, @RoleCode = @RoleCode,
         @StartsAt = @StartsAt, @EndsAt = @EndsAt, @Reason = @Reason, @GrantedByActorId = @ActorId,
         @ValidFrom = @StartsAt, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @EntityId OUTPUT, @RowId = @RowId OUTPUT;
    DECLARE @detail NVARCHAR(MAX) = (SELECT @RoleCode AS [roleCode], @FromPersonEntityId AS [fromPerson], @ToPersonEntityId AS [toPerson], @EndsAt AS [endsAt] FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC [audit].[LogAction] @ActionKindCode = N'Grant', @SubjectSchema = N'security', @SubjectTable = N'Delegation',
                             @SubjectEntityId = @EntityId, @SubjectRowId = @RowId, @Detail = @detail, @ActorId = @ActorId, @OccurredAt = @StartsAt;
    COMMIT TRANSACTION;
END;
GO
