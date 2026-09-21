-- W4 (decision #109). The three document classes the procedure engine writes into (PROCEDURE-ENGINE §5, §5.1):
--   SettingsIssuePackage — a package is a document.Revision of this class (SCHEMA-DESIGN §8.4; STEPS.md reconciliation);
--                          the REQUEST step produces one and the SETTINGS_LIFECYCLE workflow governs it
--   DeviceConfiguration  — one document per device; every configuration-file revision (native or text) is a revision of it
--   Evidence             — one document per committed step that carries evidence files; the revision links EvidenceFor the record
-- CharacteristicSchema.DocumentClass definitions carry no payload; a version is approved so the class is Effective.
-- Idempotent: an existing key is left alone.
IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @author   UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';
IF NOT EXISTS (SELECT 1 FROM [personnel].[Actor] WHERE [ActorId] = @approver)
    INSERT [personnel].[Actor] ([ActorId], [ActorKind], [SystemName]) VALUES (@approver, N'System', N'Platform.SeedApprover');
DECLARE @k NVARCHAR(100), @n NVARCHAR(200), @d NVARCHAR(MAX), @e UNIQUEIDENTIFIER, @v UNIQUEIDENTIFIER, @no INT;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT * FROM (VALUES
        (N'SettingsIssuePackage', N'Settings-issue package', N'The approval subject of a settings change: a revision of this class holds the package; its items are configuration-file revisions (§8.4, PROCEDURE-ENGINE §5.1)'),
        (N'DeviceConfiguration',  N'Device configuration',   N'One document per device; each configuration-file revision — the vendor''s native file or the name=value text file (#61) — is a revision of it'),
        (N'Evidence',             N'Step evidence',          N'Files attached at a committed procedure step; the revision links EvidenceFor the step''s record'),
        (N'InstructionManual',    N'Instruction manual',     N'A device model''s manual from its manufacturer (#216): a revision holds the file; the revision links About the model''s asset template definition, so every relay of the model opens it'),
        (N'Rationale',            N'Settings rationale',     N'Why the settings are what they are (#217). A legacy Word document as filed, frozen at the configuration-file revision it links About; from the next change on a device the rationale is the structured one the application generates')
    ) AS s (k, n, d);
OPEN c; FETCH NEXT FROM c INTO @k, @n, @d;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM [config].[Definition] WHERE [DefinitionKind] = N'CharacteristicSchema.DocumentClass' AND [DefinitionKey] = @k AND [IsDeleted] = 0)
    BEGIN
        SET @e = NULL; SET @v = NULL;   -- an OUTPUT parameter keeps its last value; Definition_Add would reuse the id
        EXEC [config].[AddDefinition] @DefinitionKind = N'CharacteristicSchema.DocumentClass', @DefinitionKey = @k, @Name = @n, @Description = @d, @ActorId = @author, @EntityId = @e OUTPUT;
        EXEC [config].[AddDefinitionVersion] @DefinitionKey = @k, @DefinitionKind = N'CharacteristicSchema.DocumentClass', @ChangeNote = N'W4 seed', @ActorId = @author, @VersionRowId = @v OUTPUT, @VersionNumber = @no OUTPUT;
        EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @v, @ActorId = @approver;
    END
    FETCH NEXT FROM c INTO @k, @n, @d;
END
CLOSE c; DEALLOCATE c;
GO
