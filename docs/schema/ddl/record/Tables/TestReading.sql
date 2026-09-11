-- SCHEMA-DESIGN §10.3 (145). A reading against a test result: as-found, as-left or single.
CREATE TABLE [record].[TestReading] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_TestReading_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_TestReading_Registry] REFERENCES [record].[TestReadingRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_TestReading_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_TestReading_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_TestReading_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_TestReading_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_TestReading_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_TestReading_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [TestResultEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_TestReading_Result] REFERENCES [record].[TestResultRegistry] ([EntityId]),
    [TestPlanReadingRowId] UNIQUEIDENTIFIER NOT NULL,  -- V2 W0: config.TestPlanReading is replaced (SCHEMA-REVIEW §3); the FK is dropped here and the column is re-pointed at the step's capture in W3 (PROCEDURE-ENGINE §4)
    [Phase]              NVARCHAR(20)     NOT NULL CONSTRAINT [CK_TestReading_Phase] CHECK ([Phase] IN (N'AsFound', N'AsLeft', N'Single')),
    [TextValue]          NVARCHAR(400)    NULL,
    [IntegerValue]       BIGINT           NULL,
    [DecimalValue]       DECIMAL(28,10)   NULL,
    [BooleanValue]       BIT              NULL,
    [DateTimeValue]      DATETIMEOFFSET(7) NULL,
    [ReferenceEntityId]  UNIQUEIDENTIFIER NULL,
    [UnitOverrideCode]   NVARCHAR(20)     NULL     CONSTRAINT [FK_TestReading_UnitOverride] REFERENCES [ref].[Unit] ([UnitCode]),
    [IsWithinLimits]     BIT              NULL,
    CONSTRAINT [PK_TestReading] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_TestReading_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_TestReading_OneValue] CHECK (
        (CASE WHEN [TextValue] IS NULL THEN 0 ELSE 1 END) + (CASE WHEN [IntegerValue] IS NULL THEN 0 ELSE 1 END)
      + (CASE WHEN [DecimalValue] IS NULL THEN 0 ELSE 1 END) + (CASE WHEN [BooleanValue] IS NULL THEN 0 ELSE 1 END)
      + (CASE WHEN [DateTimeValue] IS NULL THEN 0 ELSE 1 END) + (CASE WHEN [ReferenceEntityId] IS NULL THEN 0 ELSE 1 END) = 1)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [record].[TestReading_History]));
GO
CREATE INDEX [IX_TestReading_Entity] ON [record].[TestReading] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_TestReading_Result] ON [record].[TestReading] ([TestResultEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'record', @level1type = N'TABLE', @level1name = N'TestReading';
GO
