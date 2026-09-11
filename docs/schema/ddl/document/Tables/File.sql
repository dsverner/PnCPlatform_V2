-- SCHEMA-DESIGN §8.1 (124, 125). A file of a revision. Sha256 is the integrity check compared on every
-- read. FileStreamId → document.FileStore.stream_id; null when the bytes live in the archive tier (§13.4).
CREATE TABLE [document].[File] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_File_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_File_Registry] REFERENCES [document].[FileRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_File_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_File_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_File_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_File_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_File_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_File_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [RevisionRowId]      UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_File_Revision] REFERENCES [document].[Revision] ([RowId]),
    [FileName]           NVARCHAR(260)    NOT NULL,
    [MimeType]           NVARCHAR(100)    NOT NULL,
    [SizeBytes]          BIGINT           NOT NULL,
    [Sha256]             BINARY(32)       NOT NULL,
    [FileStreamId]       UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_File_FileStore] REFERENCES [document].[FileStore] ([stream_id]),
    [FileRole]           NVARCHAR(20)     NOT NULL CONSTRAINT [CK_File_Role] CHECK ([FileRole] IN (N'Source', N'Rendered', N'Native', N'Attachment')),
    [RedactionStatus]    NVARCHAR(20)     NOT NULL CONSTRAINT [DF_File_RedactionStatus] DEFAULT N'None' CONSTRAINT [CK_File_Redaction] CHECK ([RedactionStatus] IN (N'None', N'Redacted', N'RedactionPending')),
    [IsCapturedFromDevice] BIT            NOT NULL CONSTRAINT [DF_File_IsCapturedFromDevice] DEFAULT 0,
    CONSTRAINT [PK_File] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_File_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [document].[File_History]));
GO
CREATE INDEX [IX_File_Entity] ON [document].[File] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_File_Revision] ON [document].[File] ([RevisionRowId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'document', @level1type = N'TABLE', @level1name = N'File';
GO
