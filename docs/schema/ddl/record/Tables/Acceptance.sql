-- SCHEMA-DESIGN §10.1 (143), decision 42. Acceptance is an approval: bi-temporal, separate from the readings.
CREATE TABLE [record].[Acceptance] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Acceptance_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Acceptance_Registry] REFERENCES [record].[AcceptanceRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Acceptance_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Acceptance_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Acceptance_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Acceptance_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Acceptance_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Acceptance_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [RecordEntityId]     UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Acceptance_Record] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [AcceptedByActorId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Acceptance_AcceptedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [AcceptedAt]         DATETIMEOFFSET(7) NOT NULL,
    [AcceptanceStatus]   NVARCHAR(20)     NOT NULL CONSTRAINT [CK_Acceptance_Status] CHECK ([AcceptanceStatus] IN (N'Accepted', N'Rejected', N'Withdrawn')),
    [Reason]             NVARCHAR(400)    NULL,
    [SupersededByRecordEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Acceptance_SupersededBy] REFERENCES [record].[RecordRegistry] ([EntityId]),
    CONSTRAINT [PK_Acceptance] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Acceptance_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [record].[Acceptance_History]));
GO
CREATE INDEX [IX_Acceptance_Entity] ON [record].[Acceptance] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_Acceptance_Record] ON [record].[Acceptance] ([RecordEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'record', @level1type = N'TABLE', @level1name = N'Acceptance';
GO
