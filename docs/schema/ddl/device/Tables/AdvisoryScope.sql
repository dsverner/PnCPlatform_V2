-- SCHEMA-DESIGN §5.5 (102). Which models and firmware ranges an advisory names (null To = all).
CREATE TABLE [device].[AdvisoryScope] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_AdvisoryScope_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AdvisoryScope_Registry] REFERENCES [device].[AdvisoryScopeRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_AdvisoryScope_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AdvisoryScope_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AdvisoryScope_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_AdvisoryScope_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AdvisoryScope_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AdvisoryScope_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [AdvisoryEntityId]   UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_AdvisoryScope_Advisory] REFERENCES [device].[AdvisoryRegistry] ([EntityId]),
    [ModelId]            UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_AdvisoryScope_Model] REFERENCES [ref].[Model] ([ModelId]),
    [FirmwareVersionFromId] UNIQUEIDENTIFIER NULL  CONSTRAINT [FK_AdvisoryScope_FirmwareFrom] REFERENCES [ref].[FirmwareVersion] ([FirmwareVersionId]),
    [FirmwareVersionToId]   UNIQUEIDENTIFIER NULL  CONSTRAINT [FK_AdvisoryScope_FirmwareTo]   REFERENCES [ref].[FirmwareVersion] ([FirmwareVersionId]),
    CONSTRAINT [PK_AdvisoryScope] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_AdvisoryScope_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [device].[AdvisoryScope_History]));
GO
CREATE INDEX [IX_AdvisoryScope_Entity] ON [device].[AdvisoryScope] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'device', @level1type = N'TABLE', @level1name = N'AdvisoryScope';
GO
