-- #192 (2026-09-18): bring a draft up to its basis — the three-way merge on settings rows. The owner ruled that a second
-- change flagged by a change in the first is BLOCKED at approval/issue until re-based, and that nothing is merged
-- silently. For each row of process.fBasisDrift: take → the basis's value applied through SetParsedSetting (one audited
-- edit per setting, as an engineer's own edit would be); agree/mine → nothing; conflict → the engineer's decision in
-- @Decisions ({"CODE": "mine" | "theirs"}) — a conflict without one refuses the whole re-base (50252), nothing applied.
-- Then the basis is frozen again (WriteBasisSnapshot); a basis that was withdrawn is replaced by the in-service revision
-- with a new BasedOn link (the newest link wins). Audited as draft-rebased with the counts.
CREATE PROCEDURE [process].[RebaseDraft]
    @RevisionRowId UNIQUEIDENTIFIER,
    @DeviceEntityId UNIQUEIDENTIFIER = NULL,
    @Decisions NVARCHAR(MAX) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @Applied INT = NULL OUTPUT,
    @Kept INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    IF @Decisions IS NOT NULL AND ISJSON(@Decisions) <> 1 THROW 50252, N'process.RebaseDraft: the decisions are not valid JSON.', 1;
    DECLARE @device UNIQUEIDENTIFIER, @inService DATETIMEOFFSET(7), @status NVARCHAR(20);
    SELECT @device = cf.[DeviceEntityId], @inService = cf.[InServiceFrom], @status = r.[Status]
    FROM [document].[ConfigurationFile] cf JOIN [document].[Revision] r ON r.[RowId] = cf.[RevisionRowId]
    WHERE cf.[RevisionRowId] = @RevisionRowId AND cf.[IsDeleted] = 0 AND r.[IsDeleted] = 0;
    IF @device IS NULL THROW 50253, N'process.RebaseDraft: no live device configuration revision with that id.', 1;
    IF @inService IS NOT NULL OR @status IN (N'Superseded', N'Withdrawn') THROW 50253, N'process.RebaseDraft: only an outstanding draft is re-based; this revision is not one.', 1;
    DECLARE @linked UNIQUEIDENTIFIER = (SELECT TOP (1) l.[SubjectEntityId] FROM [document].[RevisionLink] l WHERE l.[RevisionRowId] = @RevisionRowId AND l.[LinkKind] = N'BasedOn' AND l.[ValidTo] IS NULL AND l.[IsDeleted] = 0 ORDER BY l.[RowSeq] DESC);
    IF @linked IS NULL THROW 50253, N'process.RebaseDraft: this draft is not based on another request; there is nothing to re-base.', 1;
    DECLARE @basis UNIQUEIDENTIFIER = [process].[fBasisRevision](@RevisionRowId);
    IF @basis IS NULL THROW 50253, N'process.RebaseDraft: the basis is gone and the device has no in-service revision to re-base onto.', 1;

    DECLARE @drift TABLE ([SettingCode] NVARCHAR(40), [GroupNumber] INT, [SettingName] NVARCHAR(200), [ThenValue] NVARCHAR(400), [NowValue] NVARCHAR(400), [MineValue] NVARCHAR(400), [Outcome] NVARCHAR(10), [Decision] NVARCHAR(10));
    INSERT @drift SELECT d.[SettingCode], d.[GroupNumber], d.[SettingName], d.[ThenValue], d.[NowValue], d.[MineValue], d.[Outcome],
                         LOWER(JSON_VALUE(@Decisions, CONCAT(N'$."', d.[SettingCode], N'"')))
                  FROM [process].[fBasisDrift](@RevisionRowId) d;
    DECLARE @undecided NVARCHAR(MAX) = (SELECT STRING_AGG([SettingCode], N', ') WITHIN GROUP (ORDER BY [SettingCode]) FROM @drift WHERE [Outcome] = N'conflict' AND ISNULL([Decision], N'') NOT IN (N'mine', N'theirs'));
    IF @undecided IS NOT NULL
    BEGIN
        DECLARE @m NVARCHAR(600) = CONCAT(N'process.RebaseDraft: decide these before re-basing (mine or theirs): ', LEFT(@undecided, 400));
        THROW 50252, @m, 1;
    END

    BEGIN TRANSACTION;
    DECLARE @code NVARCHAR(40), @value NVARCHAR(400), @rc NVARCHAR(20), @rn NVARCHAR(400);
    SET @Applied = 0; SET @Kept = 0;
    DECLARE ac CURSOR LOCAL FAST_FORWARD FOR
        SELECT [SettingCode], [NowValue] FROM @drift WHERE [Outcome] = N'take' OR ([Outcome] = N'conflict' AND [Decision] = N'theirs') ORDER BY [SettingCode];
    OPEN ac; FETCH NEXT FROM ac INTO @code, @value;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC [process].[SetParsedSetting] @ConfigurationFileRevisionRowId = @RevisionRowId, @DeviceEntityId = @device, @SettingCode = @code, @RawValue = @value, @DeferFileWrite = 1, @ActorId = @ActorId, @RangeCheck = @rc OUTPUT, @RangeCheckNote = @rn OUTPUT;
        SET @Applied += 1;
        FETCH NEXT FROM ac INTO @code, @value;
    END
    CLOSE ac; DEALLOCATE ac;
    -- #230: the file follows the settings — written once for the whole re-base, not once per setting
    IF @Applied > 0
    BEGIN
        DECLARE @fn NVARCHAR(255), @wr BIT;
        EXEC [process].[IssueRenderedSettings] @ConfigurationFileRevisionRowId = @RevisionRowId, @ActorId = @ActorId, @Reparse = 0, @FileName = @fn OUTPUT, @Written = @wr OUTPUT;
    END
    SELECT @Kept = COUNT(*) FROM @drift WHERE [Outcome] = N'conflict' AND [Decision] = N'mine';
    IF @basis <> @linked
        EXEC [document].[RevisionLink_Add] @RevisionRowId = @RevisionRowId, @LinkKind = N'BasedOn', @SubjectKind = N'DocumentRevision', @SubjectEntityId = @basis, @ActorId = @ActorId;
    EXEC [process].[WriteBasisSnapshot] @RevisionRowId = @RevisionRowId, @BasisRevisionRowId = @basis, @ActorId = @ActorId;
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"draft-rebased","applied":', @Applied, N',"kept":', @Kept, N',"basis":"', LOWER(CONVERT(NVARCHAR(36), @basis)), N'","retargeted":', CASE WHEN @basis <> @linked THEN N'true' ELSE N'false' END, N'}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'document', @SubjectTable = N'ConfigurationFile', @SubjectEntityId = @device, @SubjectRowId = @RevisionRowId,
         @ActorId = @ActorId, @Detail = @detail;
    COMMIT TRANSACTION;
END;
GO
