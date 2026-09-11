-- SCHEMA-DESIGN §2.4 (76). Class Versioned. One characteristic in a characteristic-schema
-- version. IsCatalogueFact publishes it to compliance.vFactCatalogue (§12.3) — the property the
-- extensibility gate proved (docs/schema/gate).
CREATE TABLE [config].[CharacteristicDefinition] (
    [RowSeq]                        BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]                         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_CharacteristicDefinition_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]                      UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_CharacteristicDefinition_Registry] REFERENCES [config].[CharacteristicDefinitionRegistry] ([EntityId]),
    [SysStart]                      DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]                        DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]                     UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_CharacteristicDefinition_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]                     DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]                    UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_CharacteristicDefinition_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]                    DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]                     BIT               NOT NULL CONSTRAINT [DF_CharacteristicDefinition_IsDeleted] DEFAULT 0,
    [DeletedBy]                     UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_CharacteristicDefinition_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]                     DATETIMEOFFSET(7) NULL,
    [MigrationRunId]                UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_CharacteristicDefinition_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [DefinitionVersionRowId]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_CharacteristicDefinition_Version] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [CharacteristicKey]             NVARCHAR(100)     NOT NULL,
    [Name]                          NVARCHAR(200)     NOT NULL,
    [Description]                   NVARCHAR(MAX)     NULL,
    [DataType]                      NVARCHAR(20)      NOT NULL CONSTRAINT [CK_CharacteristicDefinition_DataType] CHECK ([DataType] IN (N'Text', N'Integer', N'Decimal', N'Boolean', N'DateTime', N'Reference', N'Enumeration')),
    [UnitCode]                      NVARCHAR(20)      NULL     CONSTRAINT [FK_CharacteristicDefinition_Unit] REFERENCES [ref].[Unit] ([UnitCode]),
    [Base]                          NVARCHAR(20)      NULL     CONSTRAINT [CK_CharacteristicDefinition_Base] CHECK ([Base] IS NULL OR [Base] IN (N'Primary', N'Secondary', N'PerUnit')),
    [IsRequired]                    BIT               NOT NULL CONSTRAINT [DF_CharacteristicDefinition_IsRequired] DEFAULT 0,
    [AllowedValuesDefinitionRowId]  UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_CharacteristicDefinition_AllowedValues] REFERENCES [config].[DefinitionVersion] ([RowId]),  -- an Enumeration definition version
    [ReferenceTargetKind]           NVARCHAR(40)      NULL     CONSTRAINT [FK_CharacteristicDefinition_ReferenceTarget] REFERENCES [ref].[SubjectKind] ([SubjectKindCode]),
    [ValidationExpression]          NVARCHAR(MAX)     NULL,
    [DisplayOrder]                  INT               NOT NULL CONSTRAINT [DF_CharacteristicDefinition_DisplayOrder] DEFAULT 0,
    [DisplayGroup]                  NVARCHAR(100)     NULL,
    [IsCatalogueFact]               BIT               NOT NULL CONSTRAINT [DF_CharacteristicDefinition_IsCatalogueFact] DEFAULT 0,
    CONSTRAINT [PK_CharacteristicDefinition] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_CharacteristicDefinition_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_CharacteristicDefinition_EnumShape] CHECK ([DataType] <> N'Enumeration' OR [AllowedValuesDefinitionRowId] IS NOT NULL),
    CONSTRAINT [CK_CharacteristicDefinition_RefShape]  CHECK ([DataType] <> N'Reference' OR [ReferenceTargetKind] IS NOT NULL),
    CONSTRAINT [CK_CharacteristicDefinition_BaseNumeric] CHECK ([Base] IS NULL OR [DataType] IN (N'Integer', N'Decimal'))
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [config].[CharacteristicDefinition_History]));
GO
CREATE INDEX [IX_CharacteristicDefinition_Entity] ON [config].[CharacteristicDefinition] ([EntityId]);
GO
CREATE UNIQUE INDEX [UX_CharacteristicDefinition_Key] ON [config].[CharacteristicDefinition] ([DefinitionVersionRowId], [CharacteristicKey]) WHERE [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'config', @level1type = N'TABLE', @level1name = N'CharacteristicDefinition';
GO
