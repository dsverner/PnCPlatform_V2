-- SCHEMA-DESIGN §8.1 (124). Class BiTemporal: a revision's status changes are approvals (vision §4.10).
-- Segregation PreparedBy ≠ ApprovedBy is PROCEDURES.md #16.
CREATE TABLE [document].[Revision] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Revision_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Revision_Registry] REFERENCES [document].[RevisionRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Revision_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Revision_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Revision_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Revision_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Revision_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Revision_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [DocumentEntityId]   UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Revision_Document] REFERENCES [document].[DocumentRegistry] ([EntityId]),
    [RevisionLabel]      NVARCHAR(20)     NOT NULL,
    [Status]             NVARCHAR(20)     NOT NULL CONSTRAINT [CK_Revision_Status] CHECK ([Status] IN (N'Draft', N'Checked', N'Approved', N'Issued', N'Superseded', N'Withdrawn')),
    [PreparedByActorId]  UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Revision_PreparedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [PreparedAt]         DATETIMEOFFSET(7) NULL,
    [CheckedByActorId]   UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Revision_CheckedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [CheckedAt]          DATETIMEOFFSET(7) NULL,
    [ApprovedByActorId]  UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Revision_ApprovedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ApprovedAt]         DATETIMEOFFSET(7) NULL,
    [IssuedAt]           DATETIMEOFFSET(7) NULL,
    [EffectiveFrom]      DATETIMEOFFSET(7) NULL,
    [EffectiveTo]        DATETIMEOFFSET(7) NULL,
    [ChangeNote]         NVARCHAR(MAX)    NULL,
    [SupersedesRevisionRowId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Revision_Supersedes] REFERENCES [document].[Revision] ([RowId]),
    CONSTRAINT [PK_Revision] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Revision_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [document].[Revision_History]));
GO
CREATE INDEX [IX_Revision_Entity] ON [document].[Revision] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_Revision_Document] ON [document].[Revision] ([DocumentEntityId], [RevisionLabel]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'document', @level1type = N'TABLE', @level1name = N'Revision';
GO
