-- #204 (2026-09-19): the lifecycle of an instrument transformer test — CT_TEST_REQUEST and VT_TEST_REQUEST, the
-- SETTINGS_CHANGE_REQUEST_SIMPLE shape: Raised → In progress (entering it starts the test procedure) → Closed, which needs
-- the procedure Completed; Cancelled with a reason. And the two Program.WorkType definitions a request is raised under,
-- CT_TEST and VT_TEST, binding their workflow by payload (the #131 rule: the raise starts the workflow the type names, so a
-- new type needs no screen change). Loaded through process.AddWorkflowVersion and approved only while no Effective version
-- exists; the work types added only when absent.
IF OBJECT_ID(N'[process].[AddWorkflowVersion]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @author   UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';
DECLARE @key NVARCHAR(100), @proc NVARCHAR(100), @name NVARCHAR(200), @doc NVARCHAR(MAX);
DECLARE @def UNIQUEIDENTIFIER, @ver UNIQUEIDENTIFIER, @no INT, @existing BIT;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT [Key], [Proc], [Name] FROM (VALUES
    (N'CT_TEST_REQUEST', N'CT_TEST', N'Current transformer test request'),
    (N'VT_TEST_REQUEST', N'VT_TEST', N'Voltage transformer test request')) x ([Key], [Proc], [Name]);
OPEN c; FETCH NEXT FROM c INTO @key, @proc, @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM [config].[Definition] d JOIN [config].[DefinitionVersion] v ON v.[DefinitionEntityId] = d.[EntityId] AND v.[IsDeleted] = 0
                   WHERE d.[DefinitionKind] = N'Program.Workflow' AND d.[DefinitionKey] = @key AND d.[IsDeleted] = 0 AND v.[Status] = N'Effective')
    BEGIN
        SET @doc = N'{"g":1,"kind":"workflow","key":"' + @key + N'","name":"' + @name + N'","description":"The lifecycle of an instrument transformer test request (#204): entering In progress starts ' + @proc + N'; closing requires it to have completed.","subjectKind":"WorkRequest",'
            + N'"states":[{"code":"Raised","name":"Raised","initial":true,"roles":["PCEngineer","PCTechnician","Administrator"]},{"code":"InProgress","name":"In progress","roles":["PCEngineer","PCTechnician","Administrator"],"onEnter":[{"startProcedure":"' + @proc + N'"}]},{"code":"Closed","name":"Closed","terminal":true,"roles":[]},{"code":"Cancelled","name":"Cancelled","terminal":true,"cancellation":true,"roles":[]}],'
            + N'"transitions":[{"from":"Raised","to":"InProgress","name":"Start","roles":["PCEngineer","PCTechnician"]},{"from":"InProgress","to":"Closed","name":"Close","roles":["PCEngineer"],"requires":[{"procedure":"' + @proc + N'","outcome":"Completed"}]},{"from":"Raised","to":"Cancelled","name":"Cancel","requiresReason":true},{"from":"InProgress","to":"Cancelled","name":"Cancel","requiresReason":true,"roles":["PCEngineer","Administrator"]}]}';
        SET @def = NULL; SET @ver = NULL;
        EXEC [process].[AddWorkflowVersion] @Canonical = @doc, @ChangeNote = N'seed (#204)', @ActorId = @author,
             @DefinitionEntityId = @def OUTPUT, @VersionRowId = @ver OUTPUT, @VersionNumber = @no OUTPUT, @Existing = @existing OUTPUT;
        IF EXISTS (SELECT 1 FROM [config].[DefinitionVersion] WHERE [RowId] = @ver AND [Status] = N'Draft')
            EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @ver, @ActorId = @approver;   -- workflows approve through the generic definition approval (no process.ApproveWorkflowVersion exists)
    END
    FETCH NEXT FROM c INTO @key, @proc, @name;
END
CLOSE c; DEALLOCATE c;
GO
-- the work types
DECLARE @author   UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';
DECLARE @k NVARCHAR(100), @n NVARCHAR(200), @d NVARCHAR(MAX), @wf NVARCHAR(100);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT [Key], [Name], [Description], [Workflow] FROM (VALUES
    (N'CT_TEST', N'Current transformer test', N'Ratio, polarity and excitation curve of a current transformer, recorded as test sheets against it (#204)', N'CT_TEST_REQUEST'),
    (N'VT_TEST', N'Voltage transformer test', N'Ratio and polarity of a voltage transformer, recorded as test sheets against it (#204)', N'VT_TEST_REQUEST')) x ([Key], [Name], [Description], [Workflow]);
OPEN c; FETCH NEXT FROM c INTO @k, @n, @d, @wf;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM [config].[Definition] WHERE [DefinitionKind] = N'Program.WorkType' AND [DefinitionKey] = @k AND [IsDeleted] = 0)
    BEGIN
        DECLARE @e UNIQUEIDENTIFIER, @v UNIQUEIDENTIFIER, @no INT, @payload NVARCHAR(MAX);
        SET @e = NULL; SET @v = NULL;
        SET @payload = N'{"g":1,"workflow":"' + @wf + N'","requiredRecordKinds":["TestSheet"]}';
        EXEC [config].[AddDefinition] @DefinitionKind = N'Program.WorkType', @DefinitionKey = @k, @Name = @n, @Description = @d, @ActorId = @author, @EntityId = @e OUTPUT;
        EXEC [config].[AddDefinitionVersion] @DefinitionKey = @k, @DefinitionKind = N'Program.WorkType', @ChangeNote = N'seed (#204)', @PayloadText = @payload, @ActorId = @author, @VersionRowId = @v OUTPUT, @VersionNumber = @no OUTPUT;
        EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @v, @ActorId = @approver;
    END
    FETCH NEXT FROM c INTO @k, @n, @d, @wf;
END
CLOSE c; DEALLOCATE c;
GO
