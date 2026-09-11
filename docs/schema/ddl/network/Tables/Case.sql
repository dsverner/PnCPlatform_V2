-- SCHEMA-DESIGN §13.1 (186). Class ValidTime. A case is a SNAPSHOT of a layer: what the external system
-- or the platform held at a system-model date (an import file, an export, a study's model).
CREATE TABLE [network].[Case] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Case_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Case_Registry] REFERENCES [network].[CaseRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Case_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Case_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Case_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Case_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Case_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Case_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [LayerEntityId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Case_Layer] REFERENCES [network].[LayerRegistry] ([EntityId]),
    [Name]                      NVARCHAR(200)     NOT NULL,
    [SystemModelAt]             DATETIMEOFFSET(7) NOT NULL,
    [Origin]                    NVARCHAR(20)      NOT NULL CONSTRAINT [CK_Case_Origin] CHECK ([Origin] IN (N'Imported', N'Platform')),
    [SourceFileDocumentEntityId] UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Case_SourceFileDocument] REFERENCES [document].[DocumentRegistry] ([EntityId]),
    [StudyRevisionRowId]        UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Case_StudyRevision] REFERENCES [document].[Study] ([RevisionRowId]),
    CONSTRAINT [PK_Case] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Case_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [network].[Case_History]));
GO
CREATE INDEX [IX_Case_Entity] ON [network].[Case] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'network', @level1type = N'TABLE', @level1name = N'Case';
GO
