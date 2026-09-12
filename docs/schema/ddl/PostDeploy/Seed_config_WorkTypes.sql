-- W6 (decision #131; PROCEDURE-ENGINE §10 row 6): the legacy change-request action types — Change, Add, Delete, Verify
-- (LEGACY-SYSTEM §6) — as four Program.WorkType definitions, each bound to the SETTINGS_CHANGE_REQUEST workflow. The
-- request screen's "Request Change" / "New Setting" actions pick one; W7 maps each legacy request's Type onto them.
-- Payload shape is the W4 fixture's ({"g":1,"workflow":…,"requiredRecordKinds":[]}). Idempotent: an existing key is left
-- alone (a deploy never overturns what an Administrator changed). Pending the owner's W6 card.
IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @author   UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';
DECLARE @k NVARCHAR(100), @n NVARCHAR(200), @d NVARCHAR(MAX);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT [Key], [Name], [Description] FROM (VALUES
        (N'SETTINGS_CHANGE', N'Settings change',   N'A change to the settings of one or more devices (legacy action type Change Order).'),
        (N'SETTINGS_ADD',    N'New setting',       N'Settings for a device that had none in the settings book (legacy Add Order).'),
        (N'SETTINGS_DELETE', N'Settings retired',  N'A device''s settings taken out of service without replacement (legacy Delete Order).'),
        (N'SETTINGS_VERIFY', N'Settings verified', N'Existing settings re-verified in the field without a design change (legacy Verify Order).')
    ) v ([Key], [Name], [Description]);
OPEN c; FETCH NEXT FROM c INTO @k, @n, @d;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM [config].[Definition] WHERE [DefinitionKind] = N'Program.WorkType' AND [DefinitionKey] = @k AND [IsDeleted] = 0)
    BEGIN
        DECLARE @e UNIQUEIDENTIFIER, @v UNIQUEIDENTIFIER, @no INT;
        SET @e = NULL; SET @v = NULL;   -- OUTPUT variables keep their last value across the cursor's rows
        EXEC [config].[AddDefinition] @DefinitionKind = N'Program.WorkType', @DefinitionKey = @k, @Name = @n, @Description = @d, @ActorId = @author, @EntityId = @e OUTPUT;
        EXEC [config].[AddDefinitionVersion] @DefinitionKey = @k, @DefinitionKind = N'Program.WorkType', @ChangeNote = N'W6 seed (#131)',
             @PayloadText = N'{"g":1,"workflow":"SETTINGS_CHANGE_REQUEST","requiredRecordKinds":[]}', @ActorId = @author, @VersionRowId = @v OUTPUT, @VersionNumber = @no OUTPUT;
        EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @v, @ActorId = @approver;
    END
    FETCH NEXT FROM c INTO @k, @n, @d;
END
CLOSE c; DEALLOCATE c;
GO
