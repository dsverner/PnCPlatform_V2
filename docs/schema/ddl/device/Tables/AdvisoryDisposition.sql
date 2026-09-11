-- SCHEMA-DESIGN §5.5 (102). The assessment of an advisory against one device: an approval-like act,
-- hence bi-temporal. DueAt is derived by rule and stored for the record. WorkRequestEntityId FK in step 9.
CREATE TABLE [device].[AdvisoryDisposition] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_AdvisoryDisposition_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AdvisoryDisposition_Registry] REFERENCES [device].[AdvisoryDispositionRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_AdvisoryDisposition_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AdvisoryDisposition_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AdvisoryDisposition_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_AdvisoryDisposition_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AdvisoryDisposition_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AdvisoryDisposition_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [AdvisoryEntityId]   UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_AdvisoryDisposition_Advisory] REFERENCES [device].[AdvisoryRegistry] ([EntityId]),
    [DeviceEntityId]     UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_AdvisoryDisposition_Device] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [Applicability]      NVARCHAR(20)     NOT NULL CONSTRAINT [CK_AdvisoryDisposition_Applicability] CHECK ([Applicability] IN (N'Applicable', N'NotApplicable', N'Undetermined')),
    [AssessedByActorId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_AdvisoryDisposition_AssessedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [AssessedAt]         DATETIMEOFFSET(7) NOT NULL,
    [Action]             NVARCHAR(20)     NOT NULL CONSTRAINT [CK_AdvisoryDisposition_Action] CHECK ([Action] IN (N'Patch', N'Mitigate', N'Accept', N'Replace', N'None')),
    [DueAt]              DATETIMEOFFSET(7) NULL,
    [CompletedAt]        DATETIMEOFFSET(7) NULL,
    [DeferralReason]     NVARCHAR(400)    NULL,
    [RiskAcceptedByActorId] UNIQUEIDENTIFIER NULL  CONSTRAINT [FK_AdvisoryDisposition_RiskAcceptedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [DeferralReviewAt]   DATETIMEOFFSET(7) NULL,
    [WorkRequestEntityId] UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_AdvisoryDisposition_WorkRequest] REFERENCES [work].[WorkRequestRegistry] ([EntityId]),
    CONSTRAINT [PK_AdvisoryDisposition] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_AdvisoryDisposition_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [device].[AdvisoryDisposition_History]));
GO
CREATE INDEX [IX_AdvisoryDisposition_Entity] ON [device].[AdvisoryDisposition] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_AdvisoryDisposition_Device] ON [device].[AdvisoryDisposition] ([DeviceEntityId], [AdvisoryEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'device', @level1type = N'TABLE', @level1name = N'AdvisoryDisposition';
GO
