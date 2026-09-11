-- SCHEMA-DESIGN §12.6 (166): the platform assembles, a person asserts (vision §5.9). Supporting instances in the child table.
CREATE TABLE [compliance].[Assertion] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Assertion_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Assertion_Registry] REFERENCES [compliance].[AssertionRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Assertion_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Assertion_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Assertion_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Assertion_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Assertion_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Assertion_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [SubjectKind]        NVARCHAR(40)     NOT NULL CONSTRAINT [CK_Assertion_SubjectKind] CHECK ([SubjectKind] IN (N'Station', N'Scheme', N'Device', N'Asset', N'Connection', N'Person', N'Entity', N'Document', N'Definition', N'Platform')),
    [SubjectEntityId]    UNIQUEIDENTIFIER NULL,
    [StandardVersionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Assertion_StandardVersion] REFERENCES [compliance].[StandardVersion] ([RowId]),
    [RequirementEntityId] UNIQUEIDENTIFIER NULL    CONSTRAINT [FK_Assertion_Requirement] REFERENCES [compliance].[RequirementRegistry] ([EntityId]),
    [PeriodStartAt]      DATETIMEOFFSET(7) NOT NULL,
    [PeriodEndAt]        DATETIMEOFFSET(7) NOT NULL,
    [AssertedByActorId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Assertion_AssertedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [AssertedAt]         DATETIMEOFFSET(7) NOT NULL,
    [Statement]          NVARCHAR(20)     NOT NULL CONSTRAINT [CK_Assertion_Statement] CHECK ([Statement] IN (N'Compliant', N'NonCompliant', N'NotApplicable')),
    [Basis]              NVARCHAR(1000)   NULL,
    CONSTRAINT [PK_Assertion] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Assertion_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_Assertion_Subject] CHECK ([SubjectKind] = N'Platform' OR [SubjectEntityId] IS NOT NULL)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [compliance].[Assertion_History]));
GO
CREATE INDEX [IX_Assertion_Entity] ON [compliance].[Assertion] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'compliance', @level1type = N'TABLE', @level1name = N'Assertion';
GO
