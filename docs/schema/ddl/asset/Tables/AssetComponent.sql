-- SCHEMA-DESIGN §4.3 (91). Physical composition; a child has at most one parent at a time.
CREATE TABLE [asset].[AssetComponent] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_AssetComponent_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AssetComponent_Registry] REFERENCES [asset].[AssetComponentRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_AssetComponent_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AssetComponent_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AssetComponent_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_AssetComponent_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AssetComponent_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AssetComponent_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ParentAssetEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_AssetComponent_Parent] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [ChildAssetEntityId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_AssetComponent_Child]  REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [ComponentRole]       NVARCHAR(60)     NOT NULL,
    [Sequence]            INT              NULL,
    CONSTRAINT [PK_AssetComponent] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_AssetComponent_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_AssetComponent_NotSelf] CHECK ([ParentAssetEntityId] <> [ChildAssetEntityId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [asset].[AssetComponent_History]));
GO
CREATE INDEX [IX_AssetComponent_Entity] ON [asset].[AssetComponent] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_AssetComponent_ChildOneParent] ON [asset].[AssetComponent] ([ChildAssetEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'asset', @level1type = N'TABLE', @level1name = N'AssetComponent';
GO
