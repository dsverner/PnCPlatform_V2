-- #168 increment 2 (2026-09-16): a setting edited in the platform. The owner's hard requirement: settings are edited here and
-- at implementation the platform writes the manufacturer's settings file — no retyping. One value of an outstanding (Draft)
-- revision changes: the current parsed row is closed in valid time and a new row written with the value read as the parser
-- reads it (the template's type, the primary range check, RawValue as typed, a closed list checked); an empty value unsets
-- the setting. #230 (2026-09-23): the file follows — process.IssueRenderedSettings rewrites the revision's file from its rows
-- in the same transaction, so a record never goes in service, and a change is never copied, from a file that no longer says
-- what its settings say (before, only the settings step wrote it and a later edit or re-base was lost from the file). A file
-- that cannot be rewritten faithfully (settings the template does not read) refuses the edit. @DeferFileWrite = 1 is for
-- the callers that change many settings in one act (RebaseDraft, the rationale apply) and write the file once at the end;
-- it is never taken from a request body (SqlSession.NeverBound). Audited (audit.LogAction on the device: code, from, to,
-- range check). Over HTTP: ConfigurationFile.Modify on the device — @DeviceEntityId names the scope and must be the
-- revision's device.
CREATE PROCEDURE [process].[SetParsedSetting]
    @ConfigurationFileRevisionRowId UNIQUEIDENTIFIER,
    @DeviceEntityId UNIQUEIDENTIFIER,
    @SettingCode NVARCHAR(40),
    @RawValue NVARCHAR(400) = NULL,
    @DeferFileWrite BIT = 0,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @RangeCheck NVARCHAR(20) = NULL OUTPUT,
    @RangeCheckNote NVARCHAR(400) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @device UNIQUEIDENTIFIER, @fw UNIQUEIDENTIFIER, @kind NVARCHAR(20), @status NVARCHAR(20), @inService DATETIMEOFFSET(7);
    SELECT @device = cf.[DeviceEntityId], @fw = cf.[FirmwareVersionId], @kind = cf.[FileKind], @inService = cf.[InServiceFrom], @status = r.[Status]
    FROM [document].[ConfigurationFile] cf JOIN [document].[Revision] r ON r.[RowId] = cf.[RevisionRowId]
    WHERE cf.[RevisionRowId] = @ConfigurationFileRevisionRowId AND cf.[IsDeleted] = 0;
    IF @device IS NULL THROW 50180, N'process.SetParsedSetting: the revision is not a device configuration file.', 1;
    IF @device <> @DeviceEntityId THROW 50180, N'process.SetParsedSetting: the revision does not belong to that device.', 1;
    IF @status <> N'Draft' OR @inService IS NOT NULL THROW 50183, N'process.SetParsedSetting: only an outstanding (draft) revision is edited; an in-service or archived revision is the record.', 1;
    IF @kind <> N'SettingsText' THROW 50183, N'process.SetParsedSetting: the revision holds a native vendor file and no reader/writer exists for that format yet; its settings are not edited here.', 1;
    -- #231 (the owner, 2026-09-23: "refuse edits once applied"): once the package's settings are on the relay, the record and
    -- its file stay what was loaded — the lifecycle state says so through its locksContent flag (process.fStateLocksContent)
    IF (SELECT [Locked] FROM [process].[fSettingsLocked](@ConfigurationFileRevisionRowId)) = 1
        THROW 50187, N'process.SetParsedSetting: these settings have been loaded on the relay, so they are no longer changed in this request. Finish the request, or raise a new change to alter them.', 1;

    -- the template, as ParseSettingsText resolves it: the revision's firmware, else the model's row that names one
    DECLARE @tdef UNIQUEIDENTIFIER, @tver UNIQUEIDENTIFIER;
    SELECT @tdef = [ParseTransformDefinitionEntityId] FROM [ref].[FirmwareVersion] WHERE [FirmwareVersionId] = ISNULL(@fw, (SELECT [CurrentFirmwareVersionId] FROM [device].[vDevice] WHERE [EntityId] = @device));
    IF @tdef IS NULL
        SELECT TOP (1) @tdef = fv.[ParseTransformDefinitionEntityId]
        FROM [ref].[FirmwareVersion] fv JOIN [asset].[vAsset] a ON a.[ModelId] = fv.[ModelId]
        WHERE a.[EntityId] = @device AND fv.[ParseTransformDefinitionEntityId] IS NOT NULL AND fv.[IsActive] = 1
        ORDER BY CASE WHEN fv.[VersionString] = N'n/a' THEN 0 ELSE 1 END, fv.[FirmwareVersionId];
    IF @tdef IS NOT NULL
        SELECT TOP (1) @tver = dv.[RowId] FROM [config].[DefinitionVersion] dv
        WHERE dv.[DefinitionEntityId] = @tdef AND dv.[IsDeleted] = 0 AND dv.[Status] = N'Effective' AND dv.[EffectiveFrom] <= @now AND (dv.[EffectiveTo] IS NULL OR dv.[EffectiveTo] > @now)
        ORDER BY dv.[VersionNumber] DESC;
    IF @tver IS NULL THROW 50181, N'process.SetParsedSetting: the device''s model has no Effective settings template; there is nothing to edit against.', 1;

    DECLARE @code NVARCHAR(40) = UPPER(REPLACE(LTRIM(RTRIM(ISNULL(@SettingCode, N''))), N' ', N'_'));
    DECLARE @def UNIQUEIDENTIFIER, @dt NVARCHAR(20), @min DECIMAL(28,10), @max DECIMAL(28,10), @enum UNIQUEIDENTIFIER, @canon NVARCHAR(40);
    SELECT TOP (1) @def = sd.[RowId], @dt = sd.[DataType], @min = sd.[MinValue], @max = sd.[MaxValue], @enum = sd.[EnumerationDefinitionRowId], @canon = sd.[SettingCode]
    FROM [config].[SettingDefinition] sd
    WHERE sd.[DefinitionVersionRowId] = @tver AND sd.[IsDeleted] = 0
      AND (UPPER(sd.[SettingCode]) = @code
           OR (sd.[Aliases] IS NOT NULL AND EXISTS (SELECT 1 FROM STRING_SPLIT(UPPER(sd.[Aliases]), N',') a WHERE LTRIM(RTRIM(a.[value])) = @code)));
    IF @def IS NULL BEGIN DECLARE @m1 NVARCHAR(400) = N'process.SetParsedSetting: the settings template does not know the setting ' + @code + N'.'; THROW 50182, @m1, 1; END

    -- the value, read as the parser reads it: the leading number, the template's type, the primary range, the closed list
    DECLARE @raw NVARCHAR(400) = LEFT(LTRIM(RTRIM(ISNULL(@RawValue, N''))), 400);
    DECLARE @num DECIMAL(28,10) = CASE WHEN @raw <> N'' THEN TRY_CONVERT(DECIMAL(28,10), LEFT(@raw, ISNULL(NULLIF(PATINDEX(N'%[^0-9.+-]%', @raw + N' '), 0) - 1, LEN(@raw)))) END;
    SET @RangeCheck = N'NotChecked'; SET @RangeCheckNote = NULL;
    IF @raw <> N'' AND @dt IN (N'Decimal', N'Integer')
    BEGIN
        IF @num IS NULL BEGIN DECLARE @m2 NVARCHAR(400) = N'process.SetParsedSetting: ' + @canon + N' takes a number; "' + @raw + N'" is not one.'; THROW 50184, @m2, 1; END
        IF @dt = N'Integer' AND @num <> ROUND(@num, 0) BEGIN DECLARE @m3 NVARCHAR(400) = N'process.SetParsedSetting: ' + @canon + N' takes a whole number; "' + @raw + N'" is not one.'; THROW 50184, @m3, 1; END
        IF @min IS NULL AND @max IS NULL SET @RangeCheck = N'NotChecked';
        ELSE IF (@min IS NULL OR @num >= @min) AND (@max IS NULL OR @num <= @max) SET @RangeCheck = N'Ok';
        ELSE BEGIN SET @RangeCheck = N'OutOfRange'; SET @RangeCheckNote = CONCAT(N'value ', [compliance].[fDecText](@num), N' outside ', ISNULL([compliance].[fDecText](@min), N'-'), N'..', ISNULL([compliance].[fDecText](@max), N'-')); END
    END
    IF @raw <> N'' AND @enum IS NOT NULL AND EXISTS (SELECT 1 FROM [config].[EnumerationValue] WHERE [DefinitionVersionRowId] = @enum AND [IsDeleted] = 0)
       AND NOT EXISTS (SELECT 1 FROM [config].[EnumerationValue] WHERE [DefinitionVersionRowId] = @enum AND [IsDeleted] = 0 AND UPPER([ValueCode]) = UPPER(@raw))
    BEGIN
        DECLARE @m4 NVARCHAR(400) = N'process.SetParsedSetting: ' + @canon + N' takes one of ' + ISNULL((SELECT STRING_AGG([ValueCode], N', ') WITHIN GROUP (ORDER BY [DisplayOrder]) FROM [config].[EnumerationValue] WHERE [DefinitionVersionRowId] = @enum AND [IsDeleted] = 0), N'?') + N'; "' + @raw + N'" is not on the list.';
        THROW 50184, @m4, 1;
    END

    DECLARE @from NVARCHAR(400) = (SELECT TOP (1) ps.[RawValue] FROM [document].[ParsedSetting] ps
        WHERE ps.[ConfigurationFileRevisionRowId] = @ConfigurationFileRevisionRowId AND ps.[SettingDefinitionRowId] = @def AND ps.[IsDeleted] = 0 AND ps.[ValidTo] IS NULL);
    BEGIN TRANSACTION;
    UPDATE [document].[ParsedSetting] SET [ValidTo] = @now, [ModifiedBy] = @ActorId, [ModifiedAt] = @now
    WHERE [ConfigurationFileRevisionRowId] = @ConfigurationFileRevisionRowId AND [SettingDefinitionRowId] = @def AND [IsDeleted] = 0 AND [ValidTo] IS NULL;
    IF @raw <> N''
    BEGIN
        IF @dt = N'Integer'
            EXEC [document].[ParsedSetting_Add] @ConfigurationFileRevisionRowId = @ConfigurationFileRevisionRowId, @SettingDefinitionRowId = @def, @IntegerValue = @num, @RawValue = @raw, @RangeCheck = @RangeCheck, @RangeCheckNote = @RangeCheckNote, @ActorId = @ActorId;
        ELSE IF @dt = N'Decimal'
            EXEC [document].[ParsedSetting_Add] @ConfigurationFileRevisionRowId = @ConfigurationFileRevisionRowId, @SettingDefinitionRowId = @def, @DecimalValue = @num, @RawValue = @raw, @RangeCheck = @RangeCheck, @RangeCheckNote = @RangeCheckNote, @ActorId = @ActorId;
        ELSE
            EXEC [document].[ParsedSetting_Add] @ConfigurationFileRevisionRowId = @ConfigurationFileRevisionRowId, @SettingDefinitionRowId = @def, @TextValue = @raw, @RawValue = @raw, @RangeCheck = N'NotChecked', @ActorId = @ActorId;
    END
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"setting-edited","code":"', STRING_ESCAPE(@canon, 'json'), N'","from":', CASE WHEN @from IS NULL THEN N'null' ELSE N'"' + STRING_ESCAPE(@from, 'json') + N'"' END,
                                           N',"to":', CASE WHEN @raw = N'' THEN N'null' ELSE N'"' + STRING_ESCAPE(@raw, 'json') + N'"' END, N',"rangeCheck":"', @RangeCheck, N'"}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'document', @SubjectTable = N'ConfigurationFile', @SubjectEntityId = @device, @SubjectRowId = @ConfigurationFileRevisionRowId,
         @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now;
    IF ISNULL(@DeferFileWrite, 0) = 0
    BEGIN
        DECLARE @fn NVARCHAR(255), @wr BIT;
        EXEC [process].[IssueRenderedSettings] @ConfigurationFileRevisionRowId = @ConfigurationFileRevisionRowId, @ActorId = @ActorId, @Reparse = 0, @FileName = @fn OUTPUT, @Written = @wr OUTPUT;
    END
    COMMIT TRANSACTION;
END;
GO
