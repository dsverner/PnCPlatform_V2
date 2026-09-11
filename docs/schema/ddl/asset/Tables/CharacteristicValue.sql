-- SCHEMA-DESIGN §2.4 (76), host = asset. Exactly one typed value column, governed by the
-- CharacteristicDefinition it cites. SourceRecordRowId FK → record.Record (RowId) added in step 10.
CREATE TABLE [asset].[CharacteristicValue] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_CharacteristicValue_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_CharacteristicValue_Registry] REFERENCES [asset].[CharacteristicValueRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_CharacteristicValue_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_CharacteristicValue_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_CharacteristicValue_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_CharacteristicValue_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_CharacteristicValue_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_CharacteristicValue_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [HostEntityId]       UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_CharacteristicValue_Host] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [CharacteristicDefinitionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_CharacteristicValue_Definition] REFERENCES [config].[CharacteristicDefinition] ([RowId]),
    [TextValue]          NVARCHAR(400)    NULL,
    [IntegerValue]       BIGINT           NULL,
    [DecimalValue]       DECIMAL(28,10)   NULL,
    [BooleanValue]       BIT              NULL,
    [DateTimeValue]      DATETIMEOFFSET(7) NULL,
    [ReferenceEntityId]  UNIQUEIDENTIFIER NULL,
    [UnitOverrideCode]   NVARCHAR(20)     NULL     CONSTRAINT [FK_CharacteristicValue_UnitOverride] REFERENCES [ref].[Unit] ([UnitCode]),
    [SourceRecordRowId]  UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_CharacteristicValue_SourceRecord] REFERENCES [record].[Record] ([RowId]),
    CONSTRAINT [PK_CharacteristicValue] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_CharacteristicValue_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_CharacteristicValue_OneValue] CHECK (
        (CASE WHEN [TextValue] IS NULL THEN 0 ELSE 1 END) + (CASE WHEN [IntegerValue] IS NULL THEN 0 ELSE 1 END)
      + (CASE WHEN [DecimalValue] IS NULL THEN 0 ELSE 1 END) + (CASE WHEN [BooleanValue] IS NULL THEN 0 ELSE 1 END)
      + (CASE WHEN [DateTimeValue] IS NULL THEN 0 ELSE 1 END) + (CASE WHEN [ReferenceEntityId] IS NULL THEN 0 ELSE 1 END) = 1)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [asset].[CharacteristicValue_History]));
GO
CREATE INDEX [IX_CharacteristicValue_Entity] ON [asset].[CharacteristicValue] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_CharacteristicValue_Host] ON [asset].[CharacteristicValue] ([HostEntityId], [CharacteristicDefinitionRowId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'asset', @level1type = N'TABLE', @level1name = N'CharacteristicValue';
GO
