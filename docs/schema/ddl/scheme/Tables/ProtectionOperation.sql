-- SCHEMA-DESIGN §7.6 (122). An operation is the protected asset's history (vision §4.1). Raising one
-- appends ProtectionOperationSnapshot rows and, on outcome Incorrect, opens a compliance.Exception
-- (PROCEDURES.md #13). ReviewRecordEntityId FK → record (step 10); ExceptionEntityId FK → compliance (step 12).
CREATE TABLE [scheme].[ProtectionOperation] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_ProtectionOperation_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProtectionOperation_Registry] REFERENCES [scheme].[ProtectionOperationRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_ProtectionOperation_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProtectionOperation_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProtectionOperation_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_ProtectionOperation_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ProtectionOperation_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ProtectionOperation_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [OccurredAt]         DATETIMEOFFSET(7) NOT NULL,
    [TimeSourceQuality]  TINYINT          NOT NULL CONSTRAINT [CK_ProtectionOperation_TimeSourceQuality] CHECK ([TimeSourceQuality] BETWEEN 0 AND 4),
    [PrimaryAssetEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_ProtectionOperation_Asset] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [Outcome]            NVARCHAR(20)     NOT NULL CONSTRAINT [CK_ProtectionOperation_Outcome] CHECK ([Outcome] IN (N'Correct', N'Incorrect', N'Unnecessary', N'FailureToOperate', N'SlowClear', N'Undetermined')),
    [ElementsOperated]   NVARCHAR(400)    NULL,
    [ClearingTimeMs]     INT              NULL,
    [RecloseAttempts]    TINYINT          NULL,
    [RecloseSuccessful]  BIT              NULL,
    [DataSource]         NVARCHAR(20)     NOT NULL CONSTRAINT [CK_ProtectionOperation_DataSource] CHECK ([DataSource] IN (N'Scada', N'Dfr', N'RelayEventReport', N'Ser', N'FieldReport', N'Manual')),
    [IsConfirmed]        BIT              NOT NULL CONSTRAINT [DF_ProtectionOperation_IsConfirmed] DEFAULT 0,
    [ReviewRecordEntityId] UNIQUEIDENTIFIER NULL   CONSTRAINT [FK_ProtectionOperation_ReviewRecord] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [ExceptionEntityId]  UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_ProtectionOperation_Exception] REFERENCES [compliance].[ExceptionRegistry] ([EntityId]),
    [Notes]              NVARCHAR(MAX)    NULL,
    CONSTRAINT [PK_ProtectionOperation] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_ProtectionOperation_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [scheme].[ProtectionOperation_History]));
GO
CREATE INDEX [IX_ProtectionOperation_Entity] ON [scheme].[ProtectionOperation] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_ProtectionOperation_Asset] ON [scheme].[ProtectionOperation] ([PrimaryAssetEntityId], [OccurredAt]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'scheme', @level1type = N'TABLE', @level1name = N'ProtectionOperation';
GO
