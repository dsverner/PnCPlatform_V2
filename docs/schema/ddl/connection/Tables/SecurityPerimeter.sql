-- SCHEMA-DESIGN §6.5 (111). The electronic security perimeter (verify its definition against the current
-- CIP text before authoring rules); lifted from comms.ESP.
CREATE TABLE [connection].[SecurityPerimeter] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_SecurityPerimeter_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SecurityPerimeter_Registry] REFERENCES [connection].[SecurityPerimeterRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_SecurityPerimeter_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SecurityPerimeter_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SecurityPerimeter_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_SecurityPerimeter_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_SecurityPerimeter_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_SecurityPerimeter_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [Name]               NVARCHAR(200)    NOT NULL,
    [Description]        NVARCHAR(MAX)    NULL,
    [AccessPointDescription] NVARCHAR(400) NULL,
    [LastReviewedAt]     DATETIMEOFFSET(7) NULL,
    [NextReviewAt]       DATETIMEOFFSET(7) NULL,
    [ReviewedByActorId]  UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_SecurityPerimeter_ReviewedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ClassificationDocumentEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_SecurityPerimeter_Document] REFERENCES [document].[DocumentRegistry] ([EntityId]),
    CONSTRAINT [PK_SecurityPerimeter] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_SecurityPerimeter_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [connection].[SecurityPerimeter_History]));
GO
CREATE INDEX [IX_SecurityPerimeter_Entity] ON [connection].[SecurityPerimeter] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'connection', @level1type = N'TABLE', @level1name = N'SecurityPerimeter';
GO
