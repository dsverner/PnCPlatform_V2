-- PROCEDURE-ENGINE §4 "The claim" (#55; W4). The first person in the step's role to open a Ready step claims it: the
-- step goes Active with a lease (ClaimExpiresAt) that renews on every claim and draft save. Another claimant's live
-- lease refuses with that person's name (50161); an expired lease can be taken. The role is the grant's: the actor's
-- user must hold the assigned role in some scope (50160). Read scope on the work request is the API's decision.
CREATE PROCEDURE [process].[ClaimStep]
    @StepInstanceEntityId UNIQUEIDENTIFIER,
    @LeaseMinutes INT = 30,
    @ActorId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @state NVARCHAR(40), @role NVARCHAR(40), @claimant UNIQUEIDENTIFIER, @expires DATETIMEOFFSET(7);
    SELECT @state = [State], @role = [AssignedRoleCode], @claimant = [ClaimedByActorId], @expires = [ClaimExpiresAt]
    FROM [process].[StepInstance] WHERE [EntityId] = @StepInstanceEntityId AND [IsDeleted] = 0;
    IF @state IS NULL THROW 50143, N'process.ClaimStep: no live step instance with that id.', 1;
    IF @state NOT IN (N'Ready', N'Active') THROW 50157, N'process.ClaimStep: only a Ready step can be claimed.', 1;
    -- the role: a live grant of the assigned role to the actor's user (any scope), or Administrator
    DECLARE @person UNIQUEIDENTIFIER = (SELECT [PersonEntityId] FROM [personnel].[Actor] WHERE [ActorId] = @ActorId);
    IF NOT EXISTS (SELECT 1 FROM [security].[fGrantAsOf](@now, SYSUTCDATETIME()) g JOIN [security].[vUser] u ON u.[EntityId] = g.[GranteeEntityId]
                   WHERE g.[GranteeKind] = N'User' AND u.[PersonEntityId] = @person AND g.[RevokedByActorId] IS NULL AND g.[IsDeleted] = 0 AND g.[RoleCode] IN (@role, N'Administrator'))
    BEGIN DECLARE @m0 NVARCHAR(400) = N'process.ClaimStep: the step is assigned to role ' + @role + N', which you do not hold.'; THROW 50160, @m0, 1; END
    IF @claimant IS NOT NULL AND @claimant <> @ActorId AND @expires > @now
       AND (SELECT [PersonEntityId] FROM [personnel].[Actor] WHERE [ActorId] = @claimant) <> @person
    BEGIN
        DECLARE @who NVARCHAR(200) = ISNULL((SELECT TOP (1) p.[DisplayName] FROM [personnel].[Actor] a JOIN [personnel].[vPerson] p ON p.[EntityId] = a.[PersonEntityId] WHERE a.[ActorId] = @claimant), N'someone else');
        DECLARE @m1 NVARCHAR(400) = @who + N' is working this step.';
        THROW 50161, @m1, 1;
    END
    UPDATE [process].[StepInstance]
       SET [State] = N'Active', [ClaimedByActorId] = @ActorId, [ClaimedAt] = CASE WHEN [ClaimedByActorId] = @ActorId THEN [ClaimedAt] ELSE @now END,
           [ClaimExpiresAt] = DATEADD(MINUTE, @LeaseMinutes, @now), [ModifiedBy] = @ActorId, [ModifiedAt] = @now
     WHERE [EntityId] = @StepInstanceEntityId AND [IsDeleted] = 0;
END;
GO
