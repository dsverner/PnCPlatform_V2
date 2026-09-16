-- #170 (2026-09-16): an applicability classification recorded by a person on a primary asset (or a node or a scheme): CIP
-- impact rating, BES status, NPCC bulk-power-system membership, NPCC A-10 impactful bus, PRC-023 listing. In this phase the
-- values are the user's, taken from the entity's own procedures (the CIP-002 evaluation, the A-10 study) which are not yet
-- run in the platform (the owner, 2026-09-16); they are recorded with Basis = Recorded, the person and the instant, and
-- optionally the list or study they came from, so that a later phase's derivation (Basis = Derived) lands beside them and
-- the obligation rules, which read the classification whatever its basis, never change. One current value per subject and
-- kind: a new value revises the current row (the history keeps the old one); an empty value withdraws it.
-- Over HTTP: Asset.Modify (Node.Modify / Scheme.Modify) on the subject — SubjectKind/SubjectEntityId name the scope.
CREATE PROCEDURE [asset].[RecordClassification]
    @SubjectKind NVARCHAR(40),
    @SubjectEntityId UNIQUEIDENTIFIER,
    @ClassificationKindCode NVARCHAR(40),
    @ClassificationValue NVARCHAR(60) = NULL,
    @DeterminedAt DATETIMEOFFSET(7) = NULL,
    @ReferenceDocumentRevisionRowId UNIQUEIDENTIFIER = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @EntityId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    IF @SubjectKind NOT IN (N'Node', N'Asset', N'Scheme') THROW 50230, N'asset.RecordClassification: the subject is a Node, an Asset or a Scheme.', 1;
    IF NOT EXISTS (SELECT 1 FROM [ref].[ClassificationKind] WHERE [ClassificationKindCode] = @ClassificationKindCode AND [IsActive] = 1)
    BEGIN DECLARE @m1 NVARCHAR(400) = N'asset.RecordClassification: no classification kind ' + ISNULL(@ClassificationKindCode, N'(null)') + N'.'; THROW 50231, @m1, 1; END
    DECLARE @value NVARCHAR(60) = NULLIF(LTRIM(RTRIM(@ClassificationValue)), N'');
    SET @DeterminedAt = ISNULL(@DeterminedAt, @now);
    SET @EntityId = (SELECT TOP (1) [EntityId] FROM [asset].[Classification]
                     WHERE [SubjectKind] = @SubjectKind AND [SubjectEntityId] = @SubjectEntityId AND [ClassificationKindCode] = @ClassificationKindCode AND [ValidTo] IS NULL AND [IsDeleted] = 0
                     ORDER BY [RowSeq] DESC);
    BEGIN TRANSACTION;
    IF @value IS NULL
    BEGIN
        -- withdrawn: the current row closes in valid time (the history keeps it); nothing to add
        IF @EntityId IS NOT NULL EXEC [asset].[Classification_SoftDelete] @EntityId = @EntityId, @ActorId = @ActorId;
    END
    ELSE IF @EntityId IS NULL
        EXEC [asset].[Classification_Add] @SubjectKind = @SubjectKind, @SubjectEntityId = @SubjectEntityId, @ClassificationKindCode = @ClassificationKindCode, @ClassificationValue = @value,
             @Basis = N'Recorded', @DeterminedByActorId = @ActorId, @DeterminedAt = @DeterminedAt, @ReferenceDocumentRevisionRowId = @ReferenceDocumentRevisionRowId, @ActorId = @ActorId, @EntityId = @EntityId OUTPUT;
    ELSE
        EXEC [asset].[Classification_Revise] @EntityId = @EntityId, @SubjectKind = @SubjectKind, @SubjectEntityId = @SubjectEntityId, @ClassificationKindCode = @ClassificationKindCode, @ClassificationValue = @value,
             @Basis = N'Recorded', @DeterminedByActorId = @ActorId, @DeterminedAt = @DeterminedAt, @ReferenceDocumentRevisionRowId = @ReferenceDocumentRevisionRowId, @ActorId = @ActorId;
    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"classification-recorded","kind":"', STRING_ESCAPE(@ClassificationKindCode, 'json'), N'","value":', CASE WHEN @value IS NULL THEN N'null' ELSE N'"' + STRING_ESCAPE(@value, 'json') + N'"' END, N',"basis":"Recorded"}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'asset', @SubjectTable = N'Classification', @SubjectEntityId = @SubjectEntityId, @SubjectRowId = @EntityId,
         @ActorId = @ActorId, @Detail = @detail, @OccurredAt = @now;
    COMMIT TRANSACTION;
END;
GO
