-- PROCEDURE-ENGINE §2, §4, §6 (W4, decisions #106, #40). Starts one run of a Program.Procedure over a subject.
-- A root run (no parent) resolves the Effective version of the key and PINS the whole tree: the root version and,
-- walking process.ProcedureCall transitively, the Effective version of every callee, into InstanceVersionSet — so
-- "which procedure did this request follow" has exactly one answer (#40). A child run (a call block) is started with
-- the version its parent pinned and inherits the parent's set. The root block is materialised and set Running; the
-- interpreter (PnC.Api Engine) evaluates and advances from there.
--   50140 the key has no Effective version   50141 a callee has none   50142 unknown subject
CREATE PROCEDURE [process].[StartProcedure]
    @ProcedureKey NVARCHAR(100),
    @SubjectKind NVARCHAR(40),
    @SubjectEntityId UNIQUEIDENTIFIER,
    @WorkflowInstanceEntityId UNIQUEIDENTIFIER = NULL,
    @InvokedAtState NVARCHAR(40) = NULL,
    @WorkRequestEntityId UNIQUEIDENTIFIER = NULL,
    @Inputs NVARCHAR(MAX) = NULL,
    @ParentInstanceEntityId UNIQUEIDENTIFIER = NULL,
    @CallBlockPath NVARCHAR(400) = NULL,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,   -- W7 (#138)
    @EntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @DefinitionVersionRowId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
    IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
    IF [meta].[fEntityExists](@SubjectKind, @SubjectEntityId) = 0 THROW 50142, N'process.StartProcedure: no subject of that kind with that id.', 1;
    IF @WorkRequestEntityId IS NULL AND @SubjectKind = N'WorkRequest' SET @WorkRequestEntityId = @SubjectEntityId;

    -- the version: the parent's pin for a child, the Effective version for a root
    IF @ParentInstanceEntityId IS NOT NULL
        SELECT @DefinitionVersionRowId = [DefinitionVersionRowId] FROM [process].[InstanceVersionSet]
        WHERE [ProcedureInstanceEntityId] = @ParentInstanceEntityId AND [CalleeKey] = @ProcedureKey AND [IsDeleted] = 0;
    IF @DefinitionVersionRowId IS NULL
        SELECT @DefinitionVersionRowId = dv.[RowId]
        FROM [config].[Definition] d JOIN [config].[DefinitionVersion] dv ON dv.[DefinitionEntityId] = d.[EntityId] AND dv.[IsDeleted] = 0
        WHERE d.[IsDeleted] = 0 AND d.[DefinitionKind] = N'Program.Procedure' AND d.[DefinitionKey] = @ProcedureKey
          AND dv.[Status] = N'Effective' AND dv.[EffectiveFrom] <= @now AND (dv.[EffectiveTo] IS NULL OR dv.[EffectiveTo] > @now);
    IF @DefinitionVersionRowId IS NULL BEGIN DECLARE @m0 NVARCHAR(400) = N'process.StartProcedure: ' + @ProcedureKey + N' has no Effective version.'; THROW 50140, @m0, 1; END

    -- the version set: root walks the call graph; a child copies its parent's
    DECLARE @pins TABLE ([CalleeKey] NVARCHAR(100), [VersionRowId] UNIQUEIDENTIFIER, [Depth] INT);
    IF @ParentInstanceEntityId IS NOT NULL
        INSERT @pins SELECT [CalleeKey], [DefinitionVersionRowId], 0 FROM [process].[InstanceVersionSet] WHERE [ProcedureInstanceEntityId] = @ParentInstanceEntityId AND [IsDeleted] = 0;
    ELSE
    BEGIN
        -- walk the call graph breadth-first (a recursive CTE may not carry the outer join that names a missing callee)
        INSERT @pins VALUES (@ProcedureKey, @DefinitionVersionRowId, 0);
        DECLARE @depth INT = 0;
        WHILE @depth < 16 AND EXISTS (SELECT 1 FROM @pins WHERE [Depth] = @depth AND [VersionRowId] IS NOT NULL)
        BEGIN
            INSERT @pins ([CalleeKey], [VersionRowId], [Depth])
            SELECT DISTINCT c.[CalleeKey],
                   (SELECT MAX(dv.[RowId]) FROM [config].[Definition] d JOIN [config].[DefinitionVersion] dv ON dv.[DefinitionEntityId] = d.[EntityId] AND dv.[IsDeleted] = 0
                    WHERE d.[IsDeleted] = 0 AND d.[DefinitionKind] = N'Program.Procedure' AND d.[DefinitionKey] = c.[CalleeKey]
                      AND dv.[Status] = N'Effective' AND dv.[EffectiveFrom] <= @now AND (dv.[EffectiveTo] IS NULL OR dv.[EffectiveTo] > @now)
                      AND dv.[VersionNumber] = (SELECT MAX(dv2.[VersionNumber]) FROM [config].[DefinitionVersion] dv2 WHERE dv2.[DefinitionEntityId] = d.[EntityId] AND dv2.[IsDeleted] = 0 AND dv2.[Status] = N'Effective'
                                                 AND dv2.[EffectiveFrom] <= @now AND (dv2.[EffectiveTo] IS NULL OR dv2.[EffectiveTo] > @now))),
                   @depth + 1
            FROM @pins p JOIN [process].[ProcedureCall] c ON c.[DefinitionVersionRowId] = p.[VersionRowId] AND c.[IsDeleted] = 0
            WHERE p.[Depth] = @depth AND NOT EXISTS (SELECT 1 FROM @pins q WHERE q.[CalleeKey] = c.[CalleeKey]);
            SET @depth += 1;
        END
        IF EXISTS (SELECT 1 FROM @pins WHERE [VersionRowId] IS NULL)
        BEGIN
            DECLARE @m1 NVARCHAR(400) = N'process.StartProcedure: a called procedure has no Effective version: ' + (SELECT STRING_AGG([CalleeKey], N', ') FROM @pins WHERE [VersionRowId] IS NULL);
            THROW 50141, @m1, 1;
        END
    END

    BEGIN TRANSACTION;
    EXEC [process].[ProcedureInstance_Add]
        @DefinitionVersionRowId = @DefinitionVersionRowId, @ParentInstanceEntityId = @ParentInstanceEntityId, @CallBlockPath = @CallBlockPath,
        @WorkflowInstanceEntityId = @WorkflowInstanceEntityId, @InvokedAtState = @InvokedAtState,
        @SubjectKind = @SubjectKind, @SubjectEntityId = @SubjectEntityId, @WorkRequestEntityId = @WorkRequestEntityId,
        @Inputs = @Inputs, @Produced = N'{}', @State = N'Running', @StartedAt = @now, @StartedByActorId = @ActorId,
        @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @EntityId OUTPUT;
    DECLARE @ck NVARCHAR(100), @cv UNIQUEIDENTIFIER;
    DECLARE pc CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT [CalleeKey], [VersionRowId] FROM @pins;
    OPEN pc; FETCH NEXT FROM pc INTO @ck, @cv;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC [process].[InstanceVersionSet_Add] @ProcedureInstanceEntityId = @EntityId, @CalleeKey = @ck, @DefinitionVersionRowId = @cv, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId;
        FETCH NEXT FROM pc INTO @ck, @cv;
    END
    CLOSE pc; DEALLOCATE pc;

    DECLARE @doc NVARCHAR(MAX) = (SELECT [PayloadText] FROM [config].[DefinitionVersion] WHERE [RowId] = @DefinitionVersionRowId);
    DECLARE @rootPath NVARCHAR(400) = JSON_VALUE(@doc, '$.body.id'), @rootKind NVARCHAR(20) = JSON_VALUE(@doc, '$.body.block'), @root UNIQUEIDENTIFIER;
    EXEC [process].[MaterialiseBlock] @ProcedureInstanceEntityId = @EntityId, @BlockPath = @rootPath, @BlockKind = @rootKind, @IncludeRoot = 1, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @RootEntityId = @root OUTPUT;
    UPDATE [process].[BlockInstance] SET [State] = N'Running', [StartedAt] = @now, [ModifiedBy] = @ActorId, [ModifiedAt] = @now WHERE [EntityId] = @root AND [IsDeleted] = 0;

    DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"action":"procedure-started","key":"', STRING_ESCAPE(@ProcedureKey, 'json'), N'","version":"', LOWER(CONVERT(NVARCHAR(36), @DefinitionVersionRowId)), N'","parent":', CASE WHEN @ParentInstanceEntityId IS NULL THEN N'null' ELSE CONCAT(N'"', LOWER(CONVERT(NVARCHAR(36), @ParentInstanceEntityId)), N'"') END, N'}');
    EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'process', @SubjectTable = N'ProcedureInstance',
         @SubjectEntityId = @EntityId, @DefinitionVersionRowId = @DefinitionVersionRowId, @ActorId = @ActorId, @Detail = @detail;
    COMMIT TRANSACTION;
END;
GO
