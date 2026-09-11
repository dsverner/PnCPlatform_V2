-- SCHEMA-DESIGN §7.3 (117). What a relay model (or firmware) can do; seeded from the ICD parse or the model template.
CREATE TABLE [scheme].[FunctionCapability] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_FunctionCapability_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_FunctionCapability_Registry] REFERENCES [scheme].[FunctionCapabilityRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_FunctionCapability_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_FunctionCapability_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_FunctionCapability_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_FunctionCapability_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_FunctionCapability_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_FunctionCapability_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ModelId]            UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_FunctionCapability_Model] REFERENCES [ref].[Model] ([ModelId]),
    [FirmwareVersionId]  UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_FunctionCapability_Firmware] REFERENCES [ref].[FirmwareVersion] ([FirmwareVersionId]),
    [AnsiCode]           NVARCHAR(10)     NOT NULL CONSTRAINT [FK_FunctionCapability_Ansi] REFERENCES [ref].[AnsiFunction] ([AnsiCode]),
    [Source]             NVARCHAR(20)     NOT NULL CONSTRAINT [CK_FunctionCapability_Source] CHECK ([Source] IN (N'Template', N'Icd', N'Manual')),
    CONSTRAINT [PK_FunctionCapability] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_FunctionCapability_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [scheme].[FunctionCapability_History]));
GO
CREATE INDEX [IX_FunctionCapability_Entity] ON [scheme].[FunctionCapability] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'scheme', @level1type = N'TABLE', @level1name = N'FunctionCapability';
GO
