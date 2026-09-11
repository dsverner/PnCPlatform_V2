-- SCHEMA-DESIGN §10.6 (148). Record subclass sharing RecordEntityId. Drawing reconciliation, as-found drift, DC cell
-- out of tolerance, SCD mismatch and audit findings are all rows here.
CREATE TABLE [record].[Finding] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Finding_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Finding_Registry] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Finding_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Finding_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Finding_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Finding_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Finding_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Finding_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [FindingCategoryCode] NVARCHAR(40)    NOT NULL CONSTRAINT [FK_Finding_Category] REFERENCES [ref].[FindingCategory] ([FindingCategoryCode]),
    [Severity]           NVARCHAR(20)     NOT NULL CONSTRAINT [CK_Finding_Severity] CHECK ([Severity] IN (N'Critical', N'Major', N'Minor', N'Observation')),
    [Description]        NVARCHAR(MAX)    NOT NULL,
    [AsFoundValue]       NVARCHAR(400)    NULL,
    [ExpectedValue]      NVARCHAR(400)    NULL,
    [Disposition]        NVARCHAR(30)     NOT NULL CONSTRAINT [DF_Finding_Disposition] DEFAULT N'Open' CONSTRAINT [CK_Finding_Disposition] CHECK ([Disposition] IN (N'Open', N'CorrectiveActionRaised', N'Accepted', N'Closed', N'Rejected')),
    [CorrectiveWorkRequestEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Finding_CorrectiveWorkRequest] REFERENCES [work].[WorkRequestRegistry] ([EntityId]),
    [ClosedByActorId]    UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Finding_ClosedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ClosedAt]           DATETIMEOFFSET(7) NULL,
    CONSTRAINT [PK_Finding] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Finding_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [record].[Finding_History]));
GO
CREATE INDEX [IX_Finding_Entity] ON [record].[Finding] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'record', @level1type = N'TABLE', @level1name = N'Finding';
GO
