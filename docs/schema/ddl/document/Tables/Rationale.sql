-- SCHEMA-DESIGN §8.8 (132). Revision subclass: a rationale. Its content is document.CharacteristicValue
-- rows governed by two composed templates (§2.3 overlays). The two resolved template versions are stored
-- per §2.2 ("every instance stores the DefinitionVersion.RowId it was made under"); §8.8 lists no other
-- columns. Links (About the configuration-file revision; Cites study, philosophy, standard) are RevisionLink rows.
CREATE TABLE [document].[Rationale] (
    [RevisionRowId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Rationale_Parent] REFERENCES [document].[Revision] ([RowId]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Rationale_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Rationale_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Rationale_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Rationale_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Rationale_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [SchemeTypeTemplateDefinitionVersionRowId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Rationale_SchemeTypeTemplate] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [DeviceTemplateDefinitionVersionRowId]     UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Rationale_DeviceTemplate] REFERENCES [config].[DefinitionVersion] ([RowId]),
    CONSTRAINT [PK_Rationale] PRIMARY KEY CLUSTERED ([RevisionRowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [document].[Rationale_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Subclass',
    @level0type = N'SCHEMA', @level0name = N'document', @level1type = N'TABLE', @level1name = N'Rationale';
GO
