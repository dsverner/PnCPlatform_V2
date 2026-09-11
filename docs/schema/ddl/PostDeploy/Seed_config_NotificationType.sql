-- PLATFORM-ARCHITECTURE §6 (decisions 244, 251, 252). The worked Program.NotificationType definitions; the platform's
-- NotificationService reads trigger, recipientRole, escalation and expiresAfter from PayloadText. Idempotent by key:
-- a key with no definition is created; a key whose latest effective payload differs from the text below gets a new
-- version (authored by the seed author, approved by the seed approver); an identical payload is left alone.
IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @author   UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';
IF NOT EXISTS (SELECT 1 FROM [personnel].[Actor] WHERE [ActorId] = @approver)
    INSERT [personnel].[Actor] ([ActorId], [ActorKind], [SystemName]) VALUES (@approver, N'System', N'Platform.SeedApprover');

DECLARE @types TABLE ([Key] NVARCHAR(100), [Name] NVARCHAR(200), [Payload] NVARCHAR(MAX));
INSERT @types VALUES
 (N'ObligationDueSoon', N'Obligation due within 90 days (PLATFORM-ARCHITECTURE §6)',
  N'{"trigger":{"on":"ObligationDue","leadTime":"P90D"},"recipientRole":"Administrator","channels":["InApp"],"escalation":[{"after":"P30D","role":"Administrator"}]}'),
 (N'FeedStale', N'Satellite feed with no good pull for an hour (PLATFORM-ARCHITECTURE §5.1, §6)',
  N'{"trigger":{"on":"FeedStale","after":"PT1H"},"recipientRole":"Administrator","channels":["InApp"],"escalation":[{"after":"PT4H","role":"Administrator"}],"expiresAfter":"P30D"}'),
 (N'AdvisoryOpen', N'Device with open manufacturer advisories (PLATFORM-ARCHITECTURE §6, decision 251)',
  N'{"trigger":{"on":"AdvisoryOpen"},"recipientRole":"Administrator","channels":["InApp"],"completion":"auto-resolve"}');

DECLARE @key NVARCHAR(100), @name NVARCHAR(200), @payload NVARCHAR(MAX);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT [Key], [Name], [Payload] FROM @types;
OPEN c; FETCH NEXT FROM c INTO @key, @name, @payload;
WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @defEntity UNIQUEIDENTIFIER = (SELECT [EntityId] FROM [config].[Definition] WHERE [DefinitionKind] = N'Program.NotificationType' AND [DefinitionKey] = @key AND [IsDeleted] = 0);
    DECLARE @current NVARCHAR(MAX) = NULL, @verRowId UNIQUEIDENTIFIER, @verNo INT;
    IF @defEntity IS NULL
        EXEC [config].[AddDefinition] @DefinitionKind = N'Program.NotificationType', @DefinitionKey = @key, @Name = @name, @ActorId = @author, @EntityId = @defEntity OUTPUT;
    ELSE
        SELECT TOP (1) @current = [PayloadText] FROM [config].[vDefinitionVersion] WHERE [DefinitionEntityId] = @defEntity AND [Status] IN (N'Approved', N'Effective') ORDER BY [VersionNumber] DESC;
    IF @current IS NULL OR @current <> @payload
    BEGIN
        EXEC [config].[AddDefinitionVersion] @DefinitionKey = @key, @DefinitionKind = N'Program.NotificationType', @ChangeNote = N'seed', @PayloadText = @payload,
             @ActorId = @author, @VersionRowId = @verRowId OUTPUT, @VersionNumber = @verNo OUTPUT;
        EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @verRowId, @ActorId = @approver;
        PRINT CONCAT(N'  notification type ', @key, N' version ', @verNo, N' approved');
    END
    FETCH NEXT FROM c INTO @key, @name, @payload;
END
CLOSE c; DEALLOCATE c;
GO
