-- SCHEMA-DESIGN §12.1 (161), decision 64. When a version came into force and when we learned it; overlap window.
CREATE TABLE [compliance].[StandardVersion] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_StandardVersion_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_StandardVersion_Registry] REFERENCES [compliance].[StandardVersionRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_StandardVersion_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_StandardVersion_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_StandardVersion_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_StandardVersion_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_StandardVersion_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_StandardVersion_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [StandardCode]       NVARCHAR(40)     NOT NULL CONSTRAINT [FK_StandardVersion_Standard] REFERENCES [compliance].[Standard] ([StandardCode]),
    [VersionLabel]       NVARCHAR(40)     NOT NULL,
    [EffectiveFrom]      DATETIMEOFFSET(7) NULL,
    [EffectiveTo]        DATETIMEOFFSET(7) NULL,
    [OverlapUntil]       DATETIMEOFFSET(7) NULL,
    [TextDocumentEntityId] UNIQUEIDENTIFIER NULL   CONSTRAINT [FK_StandardVersion_TextDocument] REFERENCES [document].[DocumentRegistry] ([EntityId]),
    [TextReference]      NVARCHAR(400)    NULL,
    [SupersedesVersionRowId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_StandardVersion_Supersedes] REFERENCES [compliance].[StandardVersion] ([RowId]),
    CONSTRAINT [PK_StandardVersion] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_StandardVersion_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_StandardVersion_Period] CHECK ([EffectiveTo] IS NULL OR [EffectiveFrom] IS NULL OR [EffectiveTo] > [EffectiveFrom])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [compliance].[StandardVersion_History]));
GO
CREATE INDEX [IX_StandardVersion_Entity] ON [compliance].[StandardVersion] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_StandardVersion_Standard] ON [compliance].[StandardVersion] ([StandardCode], [EffectiveFrom]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'compliance', @level1type = N'TABLE', @level1name = N'StandardVersion';
GO
