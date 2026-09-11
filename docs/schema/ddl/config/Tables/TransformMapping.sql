-- SCHEMA-DESIGN §2.5. Class Versioned. The structured content of a Transform.* definition
-- version; one parser interprets these rows (vision §7.7).
CREATE TABLE [config].[TransformMapping] (
    [RowSeq]                BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]                 UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_TransformMapping_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]              UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_TransformMapping_Registry] REFERENCES [config].[TransformMappingRegistry] ([EntityId]),
    [SysStart]              DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]                DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_TransformMapping_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]             DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]            UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_TransformMapping_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]            DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]             BIT               NOT NULL CONSTRAINT [DF_TransformMapping_IsDeleted] DEFAULT 0,
    [DeletedBy]             UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_TransformMapping_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]             DATETIMEOFFSET(7) NULL,
    [MigrationRunId]        UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_TransformMapping_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [DefinitionVersionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_TransformMapping_Version] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [Direction]             NVARCHAR(20)      NOT NULL CONSTRAINT [CK_TransformMapping_Direction] CHECK ([Direction] IN (N'Parse', N'Generate')),
    [SourcePath]            NVARCHAR(400)     NOT NULL,
    [TargetKind]            NVARCHAR(40)      NOT NULL CONSTRAINT [CK_TransformMapping_TargetKind] CHECK ([TargetKind] IN (N'SettingDefinition', N'Characteristic', N'DocumentField', N'LayerField')),
    [TargetKey]             NVARCHAR(100)     NOT NULL,
    [ConversionExpression]  NVARCHAR(MAX)     NULL,
    [IsRequired]            BIT               NOT NULL CONSTRAINT [DF_TransformMapping_IsRequired] DEFAULT 0,
    [DefaultValue]          NVARCHAR(400)     NULL,
    [Sequence]              INT               NOT NULL CONSTRAINT [DF_TransformMapping_Sequence] DEFAULT 0,
    CONSTRAINT [PK_TransformMapping] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_TransformMapping_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [config].[TransformMapping_History]));
GO
CREATE INDEX [IX_TransformMapping_Entity] ON [config].[TransformMapping] ([EntityId]);
GO
CREATE INDEX [IX_TransformMapping_Version] ON [config].[TransformMapping] ([DefinitionVersionRowId], [Direction], [Sequence]) WHERE [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'config', @level1type = N'TABLE', @level1name = N'TransformMapping';
GO
