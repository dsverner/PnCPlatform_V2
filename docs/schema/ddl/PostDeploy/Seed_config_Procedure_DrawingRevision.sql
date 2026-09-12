-- W4 (decision #112, plan Q5): SETTINGS_CHANGE calls DRAWING_REVISION at COMPLETION; version pinning (§6) needs an
-- Effective version of every callee when a root instance starts. Until W5 authors the real procedure in the tool,
-- this one-step placeholder is version 1: the engineer records that drawings and documentation were updated.
-- Loaded through process.AddProcedureVersion (the same path the API uses; structural rules apply) and approved by
-- the seed approver. Idempotent on content (AddProcedureVersion answers the existing version for the same hash).
IF OBJECT_ID(N'[process].[AddProcedureVersion]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @author   UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';
DECLARE @doc NVARCHAR(MAX) = N'{"g":1,"body":{"block":"sequence","id":"MAIN","items":[{"block":"step","id":"UPDATE_DRAWINGS","instruction":"Revise the drawings and documentation affected by the change and record the revision references. Placeholder v1 (W4); W5 authors the full procedure.","record":{"kind":"DrawingUpdate"},"role":"engineer","title":"[1] Drawings and documentation updated"}]},"description":"Placeholder v1 seeded in W4 so SETTINGS_CHANGE''s call resolves; W5 authors the procedure in the tool (decision #112).","key":"DRAWING_REVISION","kind":"procedure","name":"Drawing revision","outcomes":["Completed"],"roles":{"engineer":{"role":"PCEngineer"}},"subjectKind":"WorkRequest"}';
DECLARE @def UNIQUEIDENTIFIER, @ver UNIQUEIDENTIFIER, @no INT, @existing BIT;
EXEC [process].[AddProcedureVersion] @Canonical = @doc, @ChangeNote = N'W4 placeholder v1', @ActorId = @author,
     @DefinitionEntityId = @def OUTPUT, @VersionRowId = @ver OUTPUT, @VersionNumber = @no OUTPUT, @Existing = @existing OUTPUT;
IF EXISTS (SELECT 1 FROM [config].[DefinitionVersion] WHERE [RowId] = @ver AND [Status] = N'Draft')
    EXEC [process].[ApproveProcedureVersion] @VersionRowId = @ver, @ActorId = @approver;
GO
