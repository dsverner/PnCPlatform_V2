-- SCHEMA-DESIGN §9.4 (137). Link table: cardinality between requests and Cascade orders is not yet decided.
CREATE TABLE [work].[WorkRequestCascadeLink] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_WorkRequestCascadeLink_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_WorkRequestCascadeLink_Registry] REFERENCES [work].[WorkRequestCascadeLinkRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_WorkRequestCascadeLink_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_WorkRequestCascadeLink_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_WorkRequestCascadeLink_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_WorkRequestCascadeLink_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_WorkRequestCascadeLink_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_WorkRequestCascadeLink_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [WorkRequestEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_WorkRequestCascadeLink_Request] REFERENCES [work].[WorkRequestRegistry] ([EntityId]),
    [CascadeWorkOrderEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_WorkRequestCascadeLink_Order] REFERENCES [work].[CascadeWorkOrderRegistry] ([EntityId]),
    [LinkKind]           NVARCHAR(20)     NOT NULL CONSTRAINT [CK_WorkRequestCascadeLink_Kind] CHECK ([LinkKind] IN (N'RaisedFor', N'ExecutedUnder')),
    CONSTRAINT [PK_WorkRequestCascadeLink] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_WorkRequestCascadeLink_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [work].[WorkRequestCascadeLink_History]));
GO
CREATE INDEX [IX_WorkRequestCascadeLink_Entity] ON [work].[WorkRequestCascadeLink] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_WorkRequestCascadeLink_Request] ON [work].[WorkRequestCascadeLink] ([WorkRequestEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'work', @level1type = N'TABLE', @level1name = N'WorkRequestCascadeLink';
GO
