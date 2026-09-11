-- SCHEMA-DESIGN §11.2 (153).
CREATE TABLE [personnel].[PositionHolder] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_PositionHolder_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_PositionHolder_Registry] REFERENCES [personnel].[PositionHolderRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_PositionHolder_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_PositionHolder_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_PositionHolder_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_PositionHolder_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_PositionHolder_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_PositionHolder_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [PositionEntityId]   UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_PositionHolder_Position] REFERENCES [personnel].[PositionRegistry] ([EntityId]),
    [PersonEntityId]     UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_PositionHolder_Person] REFERENCES [personnel].[PersonRegistry] ([EntityId]),
    [IsActing]           BIT              NOT NULL CONSTRAINT [DF_PositionHolder_IsActing] DEFAULT 0,
    CONSTRAINT [PK_PositionHolder] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_PositionHolder_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [personnel].[PositionHolder_History]));
GO
CREATE INDEX [IX_PositionHolder_Entity] ON [personnel].[PositionHolder] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'personnel', @level1type = N'TABLE', @level1name = N'PositionHolder';
GO
