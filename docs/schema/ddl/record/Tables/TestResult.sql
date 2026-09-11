-- SCHEMA-DESIGN §10.3 (145). One step of a test sheet, with performed / not performed / not applicable (gap G7).
CREATE TABLE [record].[TestResult] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_TestResult_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_TestResult_Registry] REFERENCES [record].[TestResultRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_TestResult_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_TestResult_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_TestResult_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_TestResult_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_TestResult_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_TestResult_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [TestSheetEntityId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_TestResult_Sheet] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [TestPlanStepRowId]  UNIQUEIDENTIFIER NOT NULL,  -- V2 W0: config.TestPlanStep is replaced (SCHEMA-REVIEW §3); the FK is dropped here and the column is re-pointed at process.ProcedureStep in W3 (PROCEDURE-ENGINE §4)
    [StepSubjectKind]    NVARCHAR(40)     NULL     CONSTRAINT [CK_TestResult_StepSubjectKind] CHECK ([StepSubjectKind] IS NULL OR [StepSubjectKind] IN (N'ProtectionFunction', N'Asset', N'Connection', N'Device', N'Scheme')),
    [StepSubjectEntityId] UNIQUEIDENTIFIER NULL,
    [Status]             NVARCHAR(20)     NOT NULL CONSTRAINT [CK_TestResult_Status] CHECK ([Status] IN (N'Performed', N'NotPerformed', N'NotApplicable')),
    [NotPerformedReason] NVARCHAR(400)    NULL,
    [Outcome]            NVARCHAR(20)     NULL     CONSTRAINT [CK_TestResult_Outcome] CHECK ([Outcome] IS NULL OR [Outcome] IN (N'Pass', N'Fail', N'Marginal')),
    [Notes]              NVARCHAR(MAX)    NULL,
    CONSTRAINT [PK_TestResult] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_TestResult_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_TestResult_NotPerformedReason] CHECK ([Status] <> N'NotPerformed' OR [NotPerformedReason] IS NOT NULL)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [record].[TestResult_History]));
GO
CREATE INDEX [IX_TestResult_Entity] ON [record].[TestResult] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_TestResult_Sheet] ON [record].[TestResult] ([TestSheetEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'record', @level1type = N'TABLE', @level1name = N'TestResult';
GO
