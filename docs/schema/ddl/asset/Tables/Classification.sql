-- SCHEMA-DESIGN §4.7 (95). Bi-temporal; many concurrent kinds per subject, one value per kind at an
-- instant. ReferenceDocumentRevisionRowId → document.Revision (RowId), step 8.
CREATE TABLE [asset].[Classification] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Classification_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Classification_Registry] REFERENCES [asset].[ClassificationRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Classification_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Classification_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Classification_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Classification_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Classification_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Classification_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [SubjectKind]        NVARCHAR(40)     NOT NULL CONSTRAINT [CK_Classification_SubjectKind] CHECK ([SubjectKind] IN (N'Node', N'Asset', N'Scheme')),
    [SubjectEntityId]    UNIQUEIDENTIFIER NOT NULL,
    [ClassificationKindCode] NVARCHAR(40) NOT NULL CONSTRAINT [FK_Classification_Kind] REFERENCES [ref].[ClassificationKind] ([ClassificationKindCode]),
    [ClassificationValue] NVARCHAR(60)    NOT NULL,
    [Basis]              NVARCHAR(20)     NOT NULL CONSTRAINT [CK_Classification_Basis] CHECK ([Basis] IN (N'Recorded', N'Derived')),
    [DerivationDefinitionVersionRowId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Classification_Derivation] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [DeterminedByActorId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Classification_DeterminedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [DeterminedAt]       DATETIMEOFFSET(7) NOT NULL,
    [ReferenceDocumentRevisionRowId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Classification_ReferenceDocument] REFERENCES [document].[Revision] ([RowId]),
    CONSTRAINT [PK_Classification] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Classification_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_Classification_DerivedHasDefinition] CHECK ([Basis] <> N'Derived' OR [DerivationDefinitionVersionRowId] IS NOT NULL)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [asset].[Classification_History]));
GO
CREATE INDEX [IX_Classification_Entity] ON [asset].[Classification] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_Classification_SubjectKind] ON [asset].[Classification] ([SubjectKind], [SubjectEntityId], [ClassificationKindCode]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'asset', @level1type = N'TABLE', @level1name = N'Classification';
GO
