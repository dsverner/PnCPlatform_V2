-- SCHEMA-DESIGN §8.9 (133). Revision subclass: a drawing sheet with the lifted title block. What it depicts
-- is RevisionLink (Depicts, DrawingKey). Reconciliation is a Finding record (step 10); editor state is a File.
CREATE TABLE [document].[Drawing] (
    [RevisionRowId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Drawing_Parent] REFERENCES [document].[Revision] ([RowId]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Drawing_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Drawing_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Drawing_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Drawing_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Drawing_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [SheetNumber]        INT              NULL,
    [SheetCount]         INT              NULL,
    [TitleLine1]         NVARCHAR(200)    NULL,
    [TitleLine2]         NVARCHAR(200)    NULL,
    [AssetTitle]         NVARCHAR(200)    NULL,
    [JobNumber]          NVARCHAR(100)    NULL,
    [WbsNumber]          NVARCHAR(100)    NULL,
    [DrawnByActorId]     UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Drawing_DrawnBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [CheckedByActorId]   UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Drawing_CheckedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [DesignedByActorId]  UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Drawing_DesignedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [DrawingStatusCode]  NVARCHAR(40)     NULL     CONSTRAINT [FK_Drawing_Status] REFERENCES [ref].[DrawingStatus] ([DrawingStatusCode]),
    [Orientation]        NVARCHAR(20)     NULL,
    [PaperSize]          NVARCHAR(20)     NULL,
    [Scale]              NVARCHAR(40)     NULL,
    [DrawingKind]        NVARCHAR(20)     NOT NULL CONSTRAINT [CK_Drawing_Kind] CHECK ([DrawingKind] IN (N'Schematic', N'Wiring', N'Logic', N'SingleLine', N'Layout', N'Cable', N'Other')),
    CONSTRAINT [PK_Drawing] PRIMARY KEY CLUSTERED ([RevisionRowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [document].[Drawing_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Subclass',
    @level0type = N'SCHEMA', @level0name = N'document', @level1type = N'TABLE', @level1name = N'Drawing';
GO
