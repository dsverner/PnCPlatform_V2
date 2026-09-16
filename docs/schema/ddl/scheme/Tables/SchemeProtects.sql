-- SCHEMA-DESIGN §7.1 (116). What a scheme protects, with its zone role.
CREATE TABLE [scheme].[SchemeProtects] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_SchemeProtects_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SchemeProtects_Registry] REFERENCES [scheme].[SchemeProtectsRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_SchemeProtects_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SchemeProtects_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SchemeProtects_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_SchemeProtects_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_SchemeProtects_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_SchemeProtects_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [SchemeEntityId]     UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_SchemeProtects_Scheme] REFERENCES [scheme].[SchemeRegistry] ([EntityId]),
    [PrimaryAssetEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_SchemeProtects_Asset] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [ZoneRole]           NVARCHAR(20)     NOT NULL CONSTRAINT [CK_SchemeProtects_Zone] CHECK ([ZoneRole] IN (N'Primary', N'Backup', N'Overlap')),
    [AssetTerminalEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_SchemeProtects_Terminal] REFERENCES [asset].[AssetTerminalRegistry] ([EntityId]),   -- #170: the terminal end the scheme protects from (a line's two ends have their own schemes); NULL = matched by station
    CONSTRAINT [PK_SchemeProtects] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_SchemeProtects_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [scheme].[SchemeProtects_History]));
GO
CREATE INDEX [IX_SchemeProtects_Entity] ON [scheme].[SchemeProtects] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_SchemeProtects] ON [scheme].[SchemeProtects] ([SchemeEntityId], [PrimaryAssetEntityId], [ZoneRole]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'scheme', @level1type = N'TABLE', @level1name = N'SchemeProtects';
GO
