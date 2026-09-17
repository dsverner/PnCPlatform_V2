-- #173 (2026-09-17): a classification the platform works out for itself, from a Program.ClassificationDerivation document
-- evaluated by the application (PnC.Api ComplianceEvaluator) over the subject's facts. The first one is the BES Cyber Asset
-- flag — the owner, 2026-09-17: "the BES Cyber Asset determination would result from whether or not the device is a
-- microprocessor based device and whether or not the primary asset that it is protecting is BES" — so it is no longer a
-- drop-down on the device's sheet; nobody records it by hand.
-- The sibling of [asset].[RecordClassification], with three differences:
--   * Basis = Derived, and the derivation's definition version is named (CK_Classification_DerivedHasDefinition requires it);
--   * a Recorded value is never overwritten. One current row per subject and kind (UX_Classification_SubjectKind), so a
--     person's judgement and a derivation cannot both stand; the person's wins and @Outcome says so, for the screen to show.
--   * an unchanged value writes nothing at all — a pass over the whole estate must not revise thousands of identical rows
--     every hour (the scheduled compliance pass, Engine:ComplianceMinutes).
-- @Value NULL means the derivation could not decide (an input was Unknown): a derived row is withdrawn, a recorded one left.
-- Over HTTP this is not callable: only the evaluator writes a derived classification (api-permissions.json maps it to null).
-- @DeterminedAt is also the row's ValidFrom: the evaluator derives and then reads back in one pass, at the pass's own instant,
-- so a row stamped at the write instant (a moment later) would be invisible to the rules that must read it. Measured on DEV
-- 2026-09-17: without this the CIP rules read the BES Cyber Asset flag as Unknown in the very pass that had just derived it.
CREATE PROCEDURE [asset].[DeriveClassification]
    @SubjectKind NVARCHAR(40),
    @SubjectEntityId UNIQUEIDENTIFIER,
    @ClassificationKindCode NVARCHAR(40),
    @ClassificationValue NVARCHAR(60) = NULL,
    @DerivationDefinitionVersionRowId UNIQUEIDENTIFIER,
    @DeterminedAt DATETIMEOFFSET(7) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @EntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @Outcome NVARCHAR(20) = NULL OUTPUT          -- Set | Unchanged | Withdrawn | RecordedStands | Undetermined
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    IF @SubjectKind NOT IN (N'Node', N'Asset', N'Scheme') THROW 50230, N'asset.DeriveClassification: the subject is a Node, an Asset or a Scheme.', 1;
    IF NOT EXISTS (SELECT 1 FROM [ref].[ClassificationKind] WHERE [ClassificationKindCode] = @ClassificationKindCode AND [IsActive] = 1)
    BEGIN DECLARE @m1 NVARCHAR(400) = N'asset.DeriveClassification: no classification kind ' + ISNULL(@ClassificationKindCode, N'(null)') + N'.'; THROW 50231, @m1, 1; END
    IF @DerivationDefinitionVersionRowId IS NULL THROW 50233, N'asset.DeriveClassification: a derived value names the derivation that produced it.', 1;

    DECLARE @value NVARCHAR(60) = NULLIF(LTRIM(RTRIM(@ClassificationValue)), N'');
    SET @DeterminedAt = ISNULL(@DeterminedAt, @now);
    DECLARE @currentBasis NVARCHAR(20), @currentValue NVARCHAR(60);
    SELECT TOP (1) @EntityId = [EntityId], @currentBasis = [Basis], @currentValue = [ClassificationValue]
    FROM [asset].[Classification]
    WHERE [SubjectKind] = @SubjectKind AND [SubjectEntityId] = @SubjectEntityId AND [ClassificationKindCode] = @ClassificationKindCode
      AND [ValidTo] IS NULL AND [IsDeleted] = 0
    ORDER BY [RowSeq] DESC;

    IF @currentBasis = N'Recorded'
    BEGIN
        -- a person has said what this is; the derivation does not argue with them in the data (the screen shows both)
        SET @Outcome = N'RecordedStands';
        RETURN;
    END
    IF @value IS NULL AND @EntityId IS NULL BEGIN SET @Outcome = N'Undetermined'; RETURN; END
    IF @value IS NOT NULL AND @currentValue = @value BEGIN SET @Outcome = N'Unchanged'; RETURN; END

    BEGIN TRANSACTION;
    IF @value IS NULL
    BEGIN
        EXEC [asset].[Classification_SoftDelete] @EntityId = @EntityId, @ActorId = @ActorId;
        SET @Outcome = N'Withdrawn';
    END
    ELSE IF @EntityId IS NULL
    BEGIN
        EXEC [asset].[Classification_Add] @SubjectKind = @SubjectKind, @SubjectEntityId = @SubjectEntityId, @ClassificationKindCode = @ClassificationKindCode, @ClassificationValue = @value,
             @Basis = N'Derived', @DerivationDefinitionVersionRowId = @DerivationDefinitionVersionRowId, @DeterminedByActorId = @ActorId, @DeterminedAt = @DeterminedAt, @ValidFrom = @DeterminedAt,
             @ActorId = @ActorId, @EntityId = @EntityId OUTPUT;
        SET @Outcome = N'Set';
    END
    ELSE
    BEGIN
        EXEC [asset].[Classification_Revise] @EntityId = @EntityId, @SubjectKind = @SubjectKind, @SubjectEntityId = @SubjectEntityId, @ClassificationKindCode = @ClassificationKindCode, @ClassificationValue = @value,
             @Basis = N'Derived', @DerivationDefinitionVersionRowId = @DerivationDefinitionVersionRowId, @DeterminedByActorId = @ActorId, @DeterminedAt = @DeterminedAt, @ValidFrom = @DeterminedAt, @ActorId = @ActorId;
        SET @Outcome = N'Set';
    END
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"classification-derived","kind":"', STRING_ESCAPE(@ClassificationKindCode, 'json'),
                                           N'","value":', CASE WHEN @value IS NULL THEN N'null' ELSE N'"' + STRING_ESCAPE(@value, 'json') + N'"' END,
                                           N',"was":', CASE WHEN @currentValue IS NULL THEN N'null' ELSE N'"' + STRING_ESCAPE(@currentValue, 'json') + N'"' END,
                                           N',"basis":"Derived"}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'asset', @SubjectTable = N'Classification', @SubjectEntityId = @SubjectEntityId, @SubjectRowId = @EntityId,
         @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now;
    COMMIT TRANSACTION;
END;
GO
GRANT EXECUTE ON [asset].[DeriveClassification] TO [app_execute];
GO
