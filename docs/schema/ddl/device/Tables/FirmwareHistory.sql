-- SCHEMA-DESIGN §5.3 (100). Valid period = while this firmware was on the device. Opening a row fires
-- re-validation and requires the parse transform (PROCEDURES.md #7). WorkRequestEntityId FK in step 9.
CREATE TABLE [device].[FirmwareHistory] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_FirmwareHistory_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_FirmwareHistory_Registry] REFERENCES [device].[FirmwareHistoryRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_FirmwareHistory_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_FirmwareHistory_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_FirmwareHistory_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_FirmwareHistory_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_FirmwareHistory_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_FirmwareHistory_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [DeviceEntityId]     UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_FirmwareHistory_Device] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [FirmwareVersionId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_FirmwareHistory_Firmware] REFERENCES [ref].[FirmwareVersion] ([FirmwareVersionId]),
    [AppliedByActorId]   UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_FirmwareHistory_AppliedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [VerifiedByActorId]  UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_FirmwareHistory_VerifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [VerifiedAt]         DATETIMEOFFSET(7) NULL,
    [WorkRequestEntityId] UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_FirmwareHistory_WorkRequest] REFERENCES [work].[WorkRequestRegistry] ([EntityId]),
    [AdvisoryDispositionEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_FirmwareHistory_AdvisoryDisposition] REFERENCES [device].[AdvisoryDispositionRegistry] ([EntityId]),
    CONSTRAINT [PK_FirmwareHistory] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_FirmwareHistory_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [device].[FirmwareHistory_History]));
GO
CREATE INDEX [IX_FirmwareHistory_Entity] ON [device].[FirmwareHistory] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_FirmwareHistory_Device] ON [device].[FirmwareHistory] ([DeviceEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'device', @level1type = N'TABLE', @level1name = N'FirmwareHistory';
GO
