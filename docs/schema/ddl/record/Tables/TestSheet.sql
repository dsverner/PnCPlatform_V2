-- SCHEMA-DESIGN §10.3 (145). Record subclass sharing RecordEntityId (extension keyed by the record's identity,
-- as device.Device is to asset.Asset). InstrumentRowId cites the instrument as it was (calibration state fixed).
-- IsPartial is "computed" in the design (needs TestResult rows); stored here, set by rule (PROCEDURES.md).
CREATE TABLE [record].[TestSheet] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_TestSheet_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_TestSheet_Registry] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_TestSheet_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_TestSheet_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_TestSheet_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_TestSheet_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_TestSheet_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_TestSheet_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [TestPlanDefinitionVersionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_TestSheet_Plan] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [InstrumentRowId]    UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_TestSheet_Instrument] REFERENCES [record].[Instrument] ([RowId]),
    [AmbientConditions]  NVARCHAR(400)    NULL,
    [IsPartial]          BIT              NOT NULL CONSTRAINT [DF_TestSheet_IsPartial] DEFAULT 0,
    CONSTRAINT [PK_TestSheet] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_TestSheet_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [record].[TestSheet_History]));
GO
CREATE INDEX [IX_TestSheet_Entity] ON [record].[TestSheet] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'record', @level1type = N'TABLE', @level1name = N'TestSheet';
GO
