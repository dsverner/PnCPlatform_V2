-- V2 W2 (decision #66; docs/design/IDENTITY.md §4). The scopes of the seven account types are nodes: one Owner and
-- five Divisions, seeded as data through location.AddNode, once. Stations arrive under them in W7. Idempotent by
-- (NodeTypeCode, Name); nothing is ever deleted here.
IF OBJECT_ID(N'[location].[AddNode]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @sys UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @owner UNIQUEIDENTIFIER = (SELECT TOP (1) [EntityId] FROM [location].[Node] WHERE [NodeTypeCode] = N'Owner' AND [Name] = N'NB Power' AND [IsDeleted] = 0 AND [ValidTo] IS NULL);
IF @owner IS NULL
    EXEC [location].[AddNode] @NodeTypeCode = N'Owner', @Name = N'NB Power', @Notes = N'Seeded W2 (decision #66): the owner of the estate; its divisions are the account-type scopes.',
         @ActorId = @sys, @EntityId = @owner OUTPUT;
DECLARE @d TABLE ([Name] NVARCHAR(200), [Order] INT);
INSERT @d VALUES (N'Transmission', 1), (N'Distribution', 2), (N'Generation · Hydro', 3), (N'Generation · Belledune', 4), (N'Generation · Coleson', 5);
DECLARE @n NVARCHAR(200), @o INT, @e UNIQUEIDENTIFIER;
DECLARE d CURSOR LOCAL FAST_FORWARD FOR SELECT [Name], [Order] FROM @d ORDER BY [Order];
OPEN d; FETCH NEXT FROM d INTO @n, @o;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM [location].[Node] WHERE [NodeTypeCode] = N'Division' AND [Name] = @n AND [IsDeleted] = 0 AND [ValidTo] IS NULL)
    BEGIN
        SET @e = NULL;
        EXEC [location].[AddNode] @NodeTypeCode = N'Division', @ParentEntityId = @owner, @Name = @n, @SiblingOrder = @o,
             @Notes = N'Seeded W2 (decision #66): a scope of the engineer grant.', @ActorId = @sys, @EntityId = @e OUTPUT;
    END
    FETCH NEXT FROM d INTO @n, @o;
END
CLOSE d; DEALLOCATE d;
GO
