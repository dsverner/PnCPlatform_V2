-- PROCEDURE-ENGINE §4 (instances). Class Versioned. A hold block's wait, reportable as such: why, who, and how it was
-- released (a condition, a person, or expiry — a hold past its maximum raises an obligation, #69).
CREATE TABLE [process].[HoldInstance] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_HoldInstance_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_HoldInstance_Registry] REFERENCES [process].[HoldInstanceRegistry] ([EntityId]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_HoldInstance_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_HoldInstance_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_HoldInstance_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_HoldInstance_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_HoldInstance_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [BlockInstanceEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_HoldInstance_Block] REFERENCES [process].[BlockInstanceRegistry] ([EntityId]),
    [Reason]            NVARCHAR(400)     NOT NULL,
    [HeldAt]            DATETIMEOFFSET(7) NOT NULL,
    [HeldByActorId] UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_HoldInstance_HeldByActor] REFERENCES [personnel].[Actor] ([ActorId]),
    [ReleasedAt]        DATETIMEOFFSET(7) NULL,
    [ReleasedByActorId] UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_HoldInstance_ReleasedByActor] REFERENCES [personnel].[Actor] ([ActorId]),
    [ReleaseBasis]      NVARCHAR(20)      NULL     CONSTRAINT [CK_HoldInstance_ReleaseBasis] CHECK ([ReleaseBasis] IS NULL OR [ReleaseBasis] IN (N'Condition', N'Manual', N'Expired')),
    CONSTRAINT [PK_HoldInstance] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_HoldInstance_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [process].[HoldInstance_History]));
GO
CREATE INDEX [IX_HoldInstance_Entity] ON [process].[HoldInstance] ([EntityId]);
GO
CREATE INDEX [IX_HoldInstance_Block] ON [process].[HoldInstance] ([BlockInstanceEntityId]) WHERE [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'process', @level1type = N'TABLE', @level1name = N'HoldInstance';
GO
