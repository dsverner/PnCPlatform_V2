-- SCHEMA-DESIGN §2.3 (75). Class ValidTime. Typed selector rows, one per dimension; a version
-- matches a subject when every non-overlay row matches. Resolver: config.ResolveDefinition.
CREATE TABLE [config].[DefinitionAppliesTo] (
    [RowSeq]                BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]                 UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_DefinitionAppliesTo_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]              UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_DefinitionAppliesTo_Registry] REFERENCES [config].[DefinitionAppliesToRegistry] ([EntityId]),
    [ValidFrom]             DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]               DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]      TINYINT           NOT NULL CONSTRAINT [DF_DefinitionAppliesTo_ValidFromQuality] DEFAULT 0,
    [SysStart]              DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]                DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_DefinitionAppliesTo_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]             DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]            UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_DefinitionAppliesTo_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]            DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]             BIT               NOT NULL CONSTRAINT [DF_DefinitionAppliesTo_IsDeleted] DEFAULT 0,
    [DeletedBy]             UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_DefinitionAppliesTo_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]             DATETIMEOFFSET(7) NULL,
    [MigrationRunId]        UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_DefinitionAppliesTo_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [DefinitionVersionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_DefinitionAppliesTo_Version] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [DimensionCode]         NVARCHAR(40)      NOT NULL CONSTRAINT [FK_DefinitionAppliesTo_Dimension] REFERENCES [ref].[AppliesToDimension] ([DimensionCode]),
    [ValueEntityId]         UNIQUEIDENTIFIER  NULL,
    [ValueCode]             NVARCHAR(100)     NULL,
    [IsOverlay]             BIT               NOT NULL CONSTRAINT [DF_DefinitionAppliesTo_IsOverlay] DEFAULT 0,
    CONSTRAINT [PK_DefinitionAppliesTo] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_DefinitionAppliesTo_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_DefinitionAppliesTo_OneValue] CHECK (
        ([ValueEntityId] IS NOT NULL AND [ValueCode] IS NULL)
     OR ([ValueEntityId] IS NULL AND [ValueCode] IS NOT NULL))
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [config].[DefinitionAppliesTo_History]));
GO
CREATE INDEX [IX_DefinitionAppliesTo_Entity] ON [config].[DefinitionAppliesTo] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_DefinitionAppliesTo_Version] ON [config].[DefinitionAppliesTo] ([DefinitionVersionRowId]) WHERE [IsDeleted] = 0 AND [ValidTo] IS NULL;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'config', @level1type = N'TABLE', @level1name = N'DefinitionAppliesTo';
GO
