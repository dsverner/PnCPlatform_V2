-- SCHEMA-DESIGN §8.1 (124). A document; its class is a CharacteristicSchema.DocumentClass definition.
-- ClassificationMarking: the design lists "Public, Internal, BcsiRestricted …" (open list) → no CHECK.
-- Alternate keys DocumentNumber, LegacyReference, DrawingNumber live in document.AlternateKey.
CREATE TABLE [document].[Document] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Document_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Document_Registry] REFERENCES [document].[DocumentRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Document_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Document_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Document_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Document_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Document_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Document_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [DocumentClassDefinitionEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Document_Class] REFERENCES [config].[DefinitionRegistry] ([EntityId]),
    [Title]              NVARCHAR(200)    NOT NULL,
    [Description]        NVARCHAR(MAX)    NULL,
    [OwnerEntityEntityId] UNIQUEIDENTIFIER NULL    CONSTRAINT [FK_Document_Owner] REFERENCES [party].[EntityRegistry] ([EntityId]),
    [ClassificationMarking] NVARCHAR(40)  NULL,
    [Notes]              NVARCHAR(MAX)    NULL,
    CONSTRAINT [PK_Document] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Document_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [document].[Document_History]));
GO
CREATE INDEX [IX_Document_Entity] ON [document].[Document] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'document', @level1type = N'TABLE', @level1name = N'Document';
GO
