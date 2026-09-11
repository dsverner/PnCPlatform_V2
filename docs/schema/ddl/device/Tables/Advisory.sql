-- SCHEMA-DESIGN §5.5 (102). A vendor bulletin or CERT advisory. DocumentEntityId FK → document in step 8.
CREATE TABLE [device].[Advisory] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Advisory_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Advisory_Registry] REFERENCES [device].[AdvisoryRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Advisory_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Advisory_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Advisory_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Advisory_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Advisory_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Advisory_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [IssuerEntityEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Advisory_Issuer] REFERENCES [party].[EntityRegistry] ([EntityId]),
    [AdvisoryReference]  NVARCHAR(100)    NOT NULL,
    [AdvisoryKind]       NVARCHAR(40)     NOT NULL CONSTRAINT [CK_Advisory_Kind] CHECK ([AdvisoryKind] IN (N'SecurityVulnerability', N'ProductDefect', N'Patch', N'EndOfLife', N'Recall')),
    [Severity]           NVARCHAR(20)     NULL,
    [PublishedAt]        DATETIMEOFFSET(7) NULL,
    [NotifiedAt]         DATETIMEOFFSET(7) NULL,
    [DocumentEntityId]   UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Advisory_Document] REFERENCES [document].[DocumentRegistry] ([EntityId]),
    [Summary]            NVARCHAR(MAX)    NULL,
    [MitigationSummary]  NVARCHAR(MAX)    NULL,
    CONSTRAINT [PK_Advisory] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Advisory_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [device].[Advisory_History]));
GO
CREATE INDEX [IX_Advisory_Entity] ON [device].[Advisory] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'device', @level1type = N'TABLE', @level1name = N'Advisory';
GO
