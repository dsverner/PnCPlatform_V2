-- W8 (decision #158; owner's round-5 ruling B10, 2026-09-14): the legacy settings book grouped its records by the free
-- text of the EQUIPMENT column; the owner ruled that grouping "is really the Equipment field, more appropriately named" —
-- a functional scheme (a RAS is a scheme, as a transformer protection is). The migration therefore raises one
-- scheme.Scheme per (station, EQUIPMENT) text, typed by this one Program.SchemeType definition, and makes every migrated
-- position a member of its group (its protection-function nodes, and the installed asset so a position whose FUNCTIONS
-- carried no ANSI code still belongs). Curation re-types a group later (a line protection, a bus differential …) without
-- touching the schema. Payload shape mirrors the other Program.* seeds: {"g":1, …}; it names no facts, so
-- compliance.ValidateProgramFacts accepts it. Idempotent: an existing key is left alone.
IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @author   UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';
IF NOT EXISTS (SELECT 1 FROM [config].[Definition] WHERE [DefinitionKind] = N'Program.SchemeType' AND [DefinitionKey] = N'LEGACY_EQUIPMENT_GROUP' AND [IsDeleted] = 0)
BEGIN
    DECLARE @e UNIQUEIDENTIFIER, @v UNIQUEIDENTIFIER, @no INT;
    EXEC [config].[AddDefinition] @DefinitionKind = N'Program.SchemeType', @DefinitionKey = N'LEGACY_EQUIPMENT_GROUP', @Name = N'Equipment group (migrated)',
         @Description = N'A functional scheme raised by the migration from the legacy settings book''s EQUIPMENT text (one per station and text). Re-type it through curation once its kind is known.',
         @ActorId = @author, @EntityId = @e OUTPUT;
    EXEC [config].[AddDefinitionVersion] @DefinitionKey = N'LEGACY_EQUIPMENT_GROUP', @DefinitionKind = N'Program.SchemeType', @ChangeNote = N'W8 seed (#158)',
         @PayloadText = N'{"g":1,"memberRoles":["Member"],"requiredMemberRoles":[],"testPlan":null,"rationaleTemplate":null,"origin":"legacy EQUIPMENT text"}',
         @ActorId = @author, @VersionRowId = @v OUTPUT, @VersionNumber = @no OUTPUT;
    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @v, @ActorId = @approver;
END
GO
