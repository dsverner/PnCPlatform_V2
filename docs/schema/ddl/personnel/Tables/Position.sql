-- SCHEMA-DESIGN §11.2 (153).
CREATE TABLE [personnel].[Position] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Position_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Position_Registry] REFERENCES [personnel].[PositionRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Position_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Position_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Position_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Position_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Position_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Position_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [EntityEntityId]     UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Position_Entity] REFERENCES [party].[EntityRegistry] ([EntityId]),
    [Title]              NVARCHAR(200)    NOT NULL,
    [ReportsToPositionEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Position_ReportsTo] REFERENCES [personnel].[PositionRegistry] ([EntityId]),
    [IsActive]           BIT              NOT NULL CONSTRAINT [DF_Position_IsActive] DEFAULT 1,
    CONSTRAINT [PK_Position] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Position_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [personnel].[Position_History]));
GO
CREATE INDEX [IX_Position_Entity] ON [personnel].[Position] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'personnel', @level1type = N'TABLE', @level1name = N'Position';
GO
