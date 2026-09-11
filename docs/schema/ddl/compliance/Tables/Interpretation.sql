-- SCHEMA-DESIGN §12.9 (169). NB Power's documented reading of a requirement, cited by rules and packages.
CREATE TABLE [compliance].[Interpretation] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Interpretation_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Interpretation_Registry] REFERENCES [compliance].[InterpretationRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Interpretation_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Interpretation_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Interpretation_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Interpretation_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Interpretation_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Interpretation_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [StandardVersionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Interpretation_StandardVersion] REFERENCES [compliance].[StandardVersion] ([RowId]),
    [RequirementEntityId] UNIQUEIDENTIFIER NULL    CONSTRAINT [FK_Interpretation_Requirement] REFERENCES [compliance].[RequirementRegistry] ([EntityId]),
    [Title]              NVARCHAR(200)    NOT NULL,
    [InterpretationText] NVARCHAR(MAX)    NOT NULL,
    [ApprovedByActorId]  UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Interpretation_ApprovedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ApprovedAt]         DATETIMEOFFSET(7) NULL,
    [SupersedesEntityId] UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Interpretation_Supersedes] REFERENCES [compliance].[InterpretationRegistry] ([EntityId]),
    [RationaleDocumentEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Interpretation_RationaleDocument] REFERENCES [document].[DocumentRegistry] ([EntityId]),
    CONSTRAINT [PK_Interpretation] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Interpretation_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [compliance].[Interpretation_History]));
GO
CREATE INDEX [IX_Interpretation_Entity] ON [compliance].[Interpretation] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'compliance', @level1type = N'TABLE', @level1name = N'Interpretation';
GO
