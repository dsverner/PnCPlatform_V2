-- Implied by SCHEMA-DESIGN §2.4 (AllowedValuesDefinitionRowId → "an enumeration definition"),
-- §3.1 (SubtypeListDefinitionRowId) and §14.2 (LookupCategory/LookupValue → enumeration
-- definitions). The design names no table for the values; this is the structured content of a
-- definition of kind CharacteristicSchema.Enumeration (a kind added to the seed for the same
-- reason — STEPS.md flags both). Class Versioned.
CREATE TABLE [config].[EnumerationValue] (
    [RowSeq]                BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]                 UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_EnumerationValue_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]              UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_EnumerationValue_Registry] REFERENCES [config].[EnumerationValueRegistry] ([EntityId]),
    [SysStart]              DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]                DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_EnumerationValue_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]             DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]            UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_EnumerationValue_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]            DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]             BIT               NOT NULL CONSTRAINT [DF_EnumerationValue_IsDeleted] DEFAULT 0,
    [DeletedBy]             UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_EnumerationValue_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]             DATETIMEOFFSET(7) NULL,
    [MigrationRunId]        UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_EnumerationValue_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [DefinitionVersionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_EnumerationValue_Version] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [ValueCode]             NVARCHAR(60)      NOT NULL,
    [Name]                  NVARCHAR(200)     NOT NULL,
    [Description]           NVARCHAR(MAX)     NULL,
    [DisplayOrder]          INT               NOT NULL CONSTRAINT [DF_EnumerationValue_DisplayOrder] DEFAULT 0,
    CONSTRAINT [PK_EnumerationValue] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_EnumerationValue_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [config].[EnumerationValue_History]));
GO
CREATE INDEX [IX_EnumerationValue_Entity] ON [config].[EnumerationValue] ([EntityId]);
GO
CREATE UNIQUE INDEX [UX_EnumerationValue_Code] ON [config].[EnumerationValue] ([DefinitionVersionRowId], [ValueCode]) WHERE [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'config', @level1type = N'TABLE', @level1name = N'EnumerationValue';
GO
