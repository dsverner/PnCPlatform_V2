-- SCHEMA-DESIGN §5.9 (105). Shape only, no Phase 1 build. AcknowledgementDocumentEntityId FK →
-- document.DocumentRegistry added in step 8; ContactPersonEntityId FK → personnel.PersonRegistry in step 11.
CREATE TABLE [party].[EntityAgreement] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_EntityAgreement_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_EntityAgreement_Registry] REFERENCES [party].[EntityAgreementRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_EntityAgreement_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_EntityAgreement_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_EntityAgreement_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_EntityAgreement_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_EntityAgreement_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_EntityAgreement_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [EntityEntityId]     UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_EntityAgreement_Entity] REFERENCES [party].[EntityRegistry] ([EntityId]),
    [AgreementKind]      NVARCHAR(40)     NOT NULL CONSTRAINT [CK_EntityAgreement_Kind] CHECK ([AgreementKind] IN (N'SupportContract', N'SupplyChainAcknowledgement', N'Licence')),
    [ProductLine]        NVARCHAR(200)    NULL,
    [Reference]          NVARCHAR(100)    NULL,
    [StartsAt]           DATETIMEOFFSET(7) NULL,
    [EndsAt]             DATETIMEOFFSET(7) NULL,
    [EndOfSupportAt]     DATETIMEOFFSET(7) NULL,
    [EndOfLifeAt]        DATETIMEOFFSET(7) NULL,
    [AcknowledgementDocumentEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_EntityAgreement_Document] REFERENCES [document].[DocumentRegistry] ([EntityId]),
    [ContactPersonEntityId] UNIQUEIDENTIFIER NULL   CONSTRAINT [FK_EntityAgreement_ContactPerson] REFERENCES [personnel].[PersonRegistry] ([EntityId]),
    CONSTRAINT [PK_EntityAgreement] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_EntityAgreement_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [party].[EntityAgreement_History]));
GO
CREATE INDEX [IX_EntityAgreement_Entity] ON [party].[EntityAgreement] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'party', @level1type = N'TABLE', @level1name = N'EntityAgreement';
GO
