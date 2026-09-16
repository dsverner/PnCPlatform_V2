-- #170 (2026-09-16): where a primary asset terminates. The owner: "transmission lines will have 1 or two terminations (three
-- terminal lines will have two line numbers)". A line has terminal 1 and terminal 2, each a station; a transformer, bus,
-- breaker, generator, capacitor or reactor has terminal 1 only; the system itself has none. This replaces the placement a
-- primary asset was given in the first cut (a placement is a device's — one Installed asset per node — and a routed asset has
-- none). When the TLM project supplies a line's route, the terminals stay the two stations the route joins. Bi-temporal; one
-- current row per asset and terminal number.
CREATE TABLE [asset].[AssetTerminal] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_AssetTerminal_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AssetTerminal_Registry] REFERENCES [asset].[AssetTerminalRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_AssetTerminal_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AssetTerminal_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AssetTerminal_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_AssetTerminal_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AssetTerminal_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AssetTerminal_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [AssetEntityId]      UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_AssetTerminal_Asset] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [TerminalNo]         TINYINT          NOT NULL CONSTRAINT [CK_AssetTerminal_No] CHECK ([TerminalNo] IN (1, 2)),
    [StationNodeEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_AssetTerminal_Station] REFERENCES [location].[NodeRegistry] ([EntityId]),
    [Notes]              NVARCHAR(400)    NULL,
    CONSTRAINT [PK_AssetTerminal] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_AssetTerminal_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [asset].[AssetTerminal_History]));
GO
CREATE INDEX [IX_AssetTerminal_Entity] ON [asset].[AssetTerminal] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_AssetTerminal_AssetNo] ON [asset].[AssetTerminal] ([AssetEntityId], [TerminalNo]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
CREATE INDEX [IX_AssetTerminal_Station] ON [asset].[AssetTerminal] ([StationNodeEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'asset', @level1type = N'TABLE', @level1name = N'AssetTerminal';
GO
