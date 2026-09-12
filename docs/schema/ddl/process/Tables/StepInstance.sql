-- PROCEDURE-ENGINE §4 (instances), §5, §5.2. Class Versioned. The mutable side of a step (claim, draft, capture) and
-- then the pointer to the immutable side (the committed record.Record). Reads of Draft by anyone but the claimant
-- are audit-logged (#68); that is the reader's duty, not a column.
CREATE TABLE [process].[StepInstance] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_StepInstance_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_StepInstance_Registry] REFERENCES [process].[StepInstanceRegistry] ([EntityId]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_StepInstance_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_StepInstance_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_StepInstance_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_StepInstance_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_StepInstance_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [BlockInstanceEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_StepInstance_Block] REFERENCES [process].[BlockInstanceRegistry] ([EntityId]),
    [StepId]            NVARCHAR(64)      NOT NULL,
    [State]             NVARCHAR(40)      NOT NULL CONSTRAINT [CK_StepInstance_State] CHECK ([State] IN (N'Pending', N'Ready', N'Active', N'Held', N'Committed', N'Skipped', N'Varied')),
    [AssignedRoleCode]  NVARCHAR(40)      NOT NULL CONSTRAINT [FK_StepInstance_AssignedRole] REFERENCES [security].[Role] ([RoleCode]),
    [ClaimedByActorId] UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_StepInstance_ClaimedByActor] REFERENCES [personnel].[Actor] ([ActorId]),
    [ClaimedAt]         DATETIMEOFFSET(7) NULL,
    [ClaimExpiresAt]    DATETIMEOFFSET(7) NULL,
    [Draft] NVARCHAR(MAX) NULL CONSTRAINT [CK_StepInstance_DraftJson] CHECK ([Draft] IS NULL OR ISJSON([Draft]) = 1),
    [DraftModifiedAt]   DATETIMEOFFSET(7) NULL,
    [CapturedAt]        DATETIMEOFFSET(7) NULL,
    [CapturedByActorId] UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_StepInstance_CapturedByActor] REFERENCES [personnel].[Actor] ([ActorId]),
    [CaptureSource]     NVARCHAR(20)      NULL     CONSTRAINT [CK_StepInstance_CaptureSource] CHECK ([CaptureSource] IS NULL OR [CaptureSource] IN (N'Online', N'FieldPack')),
    [CaptureTimeQuality] TINYINT          NULL     CONSTRAINT [CK_StepInstance_CaptureTimeQuality] CHECK ([CaptureTimeQuality] IS NULL OR [CaptureTimeQuality] BETWEEN 0 AND 4),
    [CommittedRecordEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_StepInstance_CommittedRecord] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [CommittedByActorId] UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_StepInstance_CommittedByActor] REFERENCES [personnel].[Actor] ([ActorId]),
    [WitnessedByActorId] UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_StepInstance_WitnessedByActor] REFERENCES [personnel].[Actor] ([ActorId]),
    [AcceptedIntoPlatformByActorId] UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_StepInstance_AcceptedIntoPlatformByActor] REFERENCES [personnel].[Actor] ([ActorId]),
    [CommittedAt]       DATETIMEOFFSET(7) NULL,
    [Outcome]           NVARCHAR(40)      NULL,
    [DeviationFindingEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_StepInstance_DeviationFinding] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [HeldReason]        NVARCHAR(400)     NULL,
    CONSTRAINT [PK_StepInstance] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_StepInstance_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_StepInstance_Committed] CHECK ([State] <> N'Committed' OR ([CommittedRecordEntityId] IS NOT NULL AND [CommittedByActorId] IS NOT NULL AND [CommittedAt] IS NOT NULL))
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [process].[StepInstance_History]));
GO
CREATE INDEX [IX_StepInstance_Entity] ON [process].[StepInstance] ([EntityId]);
GO
CREATE INDEX [IX_StepInstance_Block] ON [process].[StepInstance] ([BlockInstanceEntityId], [StepId]) WHERE [IsDeleted] = 0;
GO
CREATE INDEX [IX_StepInstance_Claim] ON [process].[StepInstance] ([ClaimedByActorId]) WHERE [IsDeleted] = 0 AND [ClaimedByActorId] IS NOT NULL;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'process', @level1type = N'TABLE', @level1name = N'StepInstance';
GO
