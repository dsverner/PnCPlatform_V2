-- SCHEMA-DESIGN §13.1 (189). Stage → accept → apply. A LayerReconciliation record (subject: the layer;
-- second subject: the import document) groups LayerMatchCandidate records (subject: the layer node;
-- second subject: the reconciliation record). A candidate's proposal lives in its characteristics under
-- the record template (keys anchor_kind, anchor_entity_id, line_asset_entity_id, is_primary, confidence,
-- method, reason). This procedure applies every candidate of the session that a person has ACCEPTED
-- (record.Acceptance, written by record.AcceptRecord) and not yet applied: one endpoint each through
-- network.AddLayerNodeEndpoint (SnapMethod Reconciled), then marks the candidate with the characteristic
-- applied_endpoint. Nothing is deleted; an unaccepted or rejected candidate is left alone. Tools stage,
-- humans accept, this applies — never the tool directly (Phase40 tombstone).
CREATE PROCEDURE [network].[ApplyReconciliation]
    @ReconciliationRecordEntityId UNIQUEIDENTIFIER,
    @OccurredAt DATETIMEOFFSET(7) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,
    @Applied INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @OccurredAt = ISNULL(@OccurredAt, SYSDATETIMEOFFSET());
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    DECLARE @layer UNIQUEIDENTIFIER;
    SELECT @layer = [SubjectEntityId] FROM [record].[vRecord] WHERE [EntityId] = @ReconciliationRecordEntityId AND [RecordKindCode] = N'LayerReconciliation' AND [SubjectKind] = N'Layer';
    IF @layer IS NULL THROW 50370, N'network.ApplyReconciliation: the record is not a current LayerReconciliation record on a layer.', 1;

    SET @Applied = 0;
    DECLARE @cand UNIQUEIDENTIFIER, @node UNIQUEIDENTIFIER, @tmpl UNIQUEIDENTIFIER;
    DECLARE cands CURSOR LOCAL FAST_FORWARD FOR
        SELECT r.[EntityId], r.[SubjectEntityId], r.[TemplateDefinitionVersionRowId]
        FROM [record].[vRecord] r
        WHERE r.[RecordKindCode] = N'LayerMatchCandidate' AND r.[SubjectKind] = N'LayerNode'
          AND r.[SecondSubjectKind] = N'Record' AND r.[SecondSubjectEntityId] = @ReconciliationRecordEntityId
          AND EXISTS (SELECT 1 FROM [record].[vAcceptance] a WHERE a.[RecordEntityId] = r.[EntityId] AND a.[AcceptanceStatus] = N'Accepted')
          AND NOT EXISTS (SELECT 1 FROM [record].[vCharacteristicValue] v JOIN [config].[vCharacteristicDefinition] d ON d.[RowId] = v.[CharacteristicDefinitionRowId]
                          WHERE v.[HostEntityId] = r.[EntityId] AND d.[CharacteristicKey] = N'applied_endpoint')
        ORDER BY r.[OccurredAt];
    OPEN cands; FETCH NEXT FROM cands INTO @cand, @node, @tmpl;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @kind NVARCHAR(40), @anchor UNIQUEIDENTIFIER, @line UNIQUEIDENTIFIER, @primary BIT, @appliedDef UNIQUEIDENTIFIER;
        SELECT @kind = NULL, @anchor = NULL, @line = NULL, @primary = 0, @appliedDef = NULL;
        SELECT @kind    = MAX(CASE WHEN d.[CharacteristicKey] = N'anchor_kind' THEN v.[TextValue] END),
               @anchor  = MAX(CASE WHEN d.[CharacteristicKey] = N'anchor_entity_id' THEN v.[ReferenceEntityId] END),
               @line    = MAX(CASE WHEN d.[CharacteristicKey] = N'line_asset_entity_id' THEN v.[ReferenceEntityId] END),
               @primary = ISNULL(MAX(CASE WHEN d.[CharacteristicKey] = N'is_primary' THEN CONVERT(INT, v.[BooleanValue]) END), 0)
        FROM [record].[vCharacteristicValue] v JOIN [config].[vCharacteristicDefinition] d ON d.[RowId] = v.[CharacteristicDefinitionRowId]
        WHERE v.[HostEntityId] = @cand;
        SELECT @appliedDef = [RowId] FROM [config].[vCharacteristicDefinition] WHERE [DefinitionVersionRowId] = @tmpl AND [CharacteristicKey] = N'applied_endpoint';
        IF @kind IS NULL OR @anchor IS NULL OR @appliedDef IS NULL
        BEGIN
            DECLARE @m NVARCHAR(400) = CONCAT(N'network.ApplyReconciliation: candidate ', CONVERT(NVARCHAR(36), @cand), N' lacks anchor_kind / anchor_entity_id or its template has no applied_endpoint characteristic.');
            THROW 50371, @m, 1;
        END;
        BEGIN TRANSACTION;
        DECLARE @ep UNIQUEIDENTIFIER;
        EXEC [network].[AddLayerNodeEndpoint] @LayerNodeEntityId = @node, @AnchorKind = @kind, @AnchorEntityId = @anchor, @LineAssetEntityId = @line, @IsPrimary = @primary,
             @SnapMethod = N'Reconciled', @Notes = N'Applied from an accepted reconciliation candidate', @ValidFrom = @OccurredAt,
             @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @ep OUTPUT;
        EXEC [record].[CharacteristicValue_Add] @HostEntityId = @cand, @CharacteristicDefinitionRowId = @appliedDef, @ReferenceEntityId = @ep, @ValidFrom = @OccurredAt, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId;
        DECLARE @detail NVARCHAR(MAX) = (SELECT @cand AS [candidate], @node AS [layerNode], @ep AS [endpoint] FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'network', @SubjectTable = N'LayerNodeEndpoint', @SubjectEntityId = @ep, @Detail = @detail, @ActorId = @ActorId, @OccurredAt = @OccurredAt;
        COMMIT TRANSACTION;
        SET @Applied += 1;
        FETCH NEXT FROM cands INTO @cand, @node, @tmpl;
    END;
    CLOSE cands; DEALLOCATE cands;
END;
GO
