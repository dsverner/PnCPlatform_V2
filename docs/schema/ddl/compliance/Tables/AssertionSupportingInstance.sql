-- SCHEMA-DESIGN §12.6 (166): the child table for an assertion's SupportingInstanceRowIds.
CREATE TABLE [compliance].[AssertionSupportingInstance] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_AssertionSupportingInstance_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AssertionSupportingInstance_Registry] REFERENCES [compliance].[AssertionSupportingInstanceRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_AssertionSupportingInstance_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AssertionSupportingInstance_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AssertionSupportingInstance_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_AssertionSupportingInstance_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AssertionSupportingInstance_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AssertionSupportingInstance_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [AssertionEntityId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_AssertionSupportingInstance_Assertion] REFERENCES [compliance].[AssertionRegistry] ([EntityId]),
    [ObligationInstanceRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_AssertionSupportingInstance_Instance] REFERENCES [compliance].[ObligationInstance] ([RowId]),
    CONSTRAINT [PK_AssertionSupportingInstance] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_AssertionSupportingInstance_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [compliance].[AssertionSupportingInstance_History]));
GO
CREATE INDEX [IX_AssertionSupportingInstance_Entity] ON [compliance].[AssertionSupportingInstance] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_AssertionSupportingInstance_Assertion] ON [compliance].[AssertionSupportingInstance] ([AssertionEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'compliance', @level1type = N'TABLE', @level1name = N'AssertionSupportingInstance';
GO
