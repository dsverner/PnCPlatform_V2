-- SCHEMA-DESIGN §8.2 (126). One polymorphic, kind-labelled join from a revision to anything.
-- SubjectKind list from §8.2: node, asset, scheme, connection, record, obligation instance, another revision.
CREATE TABLE [document].[RevisionLink] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_RevisionLink_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_RevisionLink_Registry] REFERENCES [document].[RevisionLinkRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_RevisionLink_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_RevisionLink_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_RevisionLink_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_RevisionLink_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_RevisionLink_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_RevisionLink_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [RevisionRowId]      UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_RevisionLink_Revision] REFERENCES [document].[Revision] ([RowId]),
    [LinkKind]           NVARCHAR(20)     NOT NULL CONSTRAINT [CK_RevisionLink_Kind] CHECK ([LinkKind] IN (N'About', N'Depicts', N'PerformedTo', N'ValidAgainst', N'Cites', N'EvidenceFor', N'BasedOn')),   -- BasedOn (#191): a draft copied from another request's open draft, subject DocumentRevision
    [SubjectKind]        NVARCHAR(40)     NOT NULL CONSTRAINT [CK_RevisionLink_SubjectKind] CHECK ([SubjectKind] IN (N'Node', N'Asset', N'Scheme', N'Connection', N'Record', N'ObligationInstance', N'DocumentRevision')),
    [SubjectEntityId]    UNIQUEIDENTIFIER NOT NULL,
    [DrawingKey]         NVARCHAR(100)    NULL,
    CONSTRAINT [PK_RevisionLink] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_RevisionLink_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [document].[RevisionLink_History]));
GO
CREATE INDEX [IX_RevisionLink_Entity] ON [document].[RevisionLink] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_RevisionLink_Subject] ON [document].[RevisionLink] ([SubjectKind], [SubjectEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
CREATE INDEX [IX_RevisionLink_Revision] ON [document].[RevisionLink] ([RevisionRowId], [LinkKind]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'document', @level1type = N'TABLE', @level1name = N'RevisionLink';
GO
