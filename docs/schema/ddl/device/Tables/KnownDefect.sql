-- SCHEMA-DESIGN §5.6 (103). A defect found in the field before the vendor names it. The design lists a
-- Status column without values; no CHECK is applied (STEPS.md).
CREATE TABLE [device].[KnownDefect] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_KnownDefect_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_KnownDefect_Registry] REFERENCES [device].[KnownDefectRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_KnownDefect_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_KnownDefect_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_KnownDefect_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_KnownDefect_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_KnownDefect_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_KnownDefect_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ModelId]            UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_KnownDefect_Model] REFERENCES [ref].[Model] ([ModelId]),
    [FirmwareVersionFromId] UNIQUEIDENTIFIER NULL  CONSTRAINT [FK_KnownDefect_FirmwareFrom] REFERENCES [ref].[FirmwareVersion] ([FirmwareVersionId]),
    [FirmwareVersionToId]   UNIQUEIDENTIFIER NULL  CONSTRAINT [FK_KnownDefect_FirmwareTo]   REFERENCES [ref].[FirmwareVersion] ([FirmwareVersionId]),
    [Description]        NVARCHAR(MAX)    NOT NULL,
    [Workaround]         NVARCHAR(MAX)    NULL,
    [VendorReference]    NVARCHAR(100)    NULL,
    [AdvisoryEntityId]   UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_KnownDefect_Advisory] REFERENCES [device].[AdvisoryRegistry] ([EntityId]),
    [ReportedByActorId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_KnownDefect_ReportedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [Status]             NVARCHAR(20)     NOT NULL,
    CONSTRAINT [PK_KnownDefect] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_KnownDefect_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [device].[KnownDefect_History]));
GO
CREATE INDEX [IX_KnownDefect_Entity] ON [device].[KnownDefect] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'device', @level1type = N'TABLE', @level1name = N'KnownDefect';
GO
