-- #212 (2026-09-20): an instrument transformer's SECONDARY WINDINGS as first-class rows. The owner: "most if not all of them
-- come with a single primary connection and multiple (2, 3, 4 or 5 typically) secondary windings each with its own ratio,
-- name etc., which can be used in various protections … this is a physical thing that needs to have a first class place in
-- the database." A winding is a child of the transformer (the asset.AssetTerminal shape, #170): its number and code (S1,
-- 1Y, X), what it is for, its ratio taps and the ratio in use, accuracy class, burden, knee point, rated secondary and
-- connection. A scheme's source membership names the winding it uses (scheme.SchemeMember.WindingEntityId), so "2103
-- B-PROT Current 1 is fed by E2103 winding S2" is a fact and the relay's CTR is judged against that winding's ratio. The
-- winding is the yard-side endpoint the cabling phase will reference; its taps (kept as text here) become the terminals
-- then. Bi-temporal; one current row per transformer and winding number.
CREATE TABLE [asset].[InstrumentWinding] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_InstrumentWinding_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_InstrumentWinding_Registry] REFERENCES [asset].[InstrumentWindingRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_InstrumentWinding_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_InstrumentWinding_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_InstrumentWinding_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_InstrumentWinding_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_InstrumentWinding_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_InstrumentWinding_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [AssetEntityId]      UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_InstrumentWinding_Asset] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [WindingNo]          TINYINT          NOT NULL CONSTRAINT [CK_InstrumentWinding_No] CHECK ([WindingNo] >= 1),
    [Code]               NVARCHAR(20)     NOT NULL,   -- S1, S2, 1Y, 2Y, X, Y: the nameplate's name for the winding
    [Purpose]            NVARCHAR(20)     NULL     CONSTRAINT [CK_InstrumentWinding_Purpose] CHECK ([Purpose] IN (N'Protection', N'Metering', N'Sync', N'Spare', N'Other')),
    [RatioTaps]          NVARCHAR(200)    NULL,       -- every ratio the winding offers, as the nameplate lists them: "600:5, 1200:5"
    [RatioInUse]         NVARCHAR(40)     NULL,       -- the tap connected: "1200:5" (read as 240 by scheme.vSchemeSource)
    [AccuracyClass]      NVARCHAR(40)     NULL,       -- C400, 0.3B1.8, 3P …
    [RatedBurden]        NVARCHAR(40)     NULL,
    [KneePointVoltageV]  DECIMAL(10,2)    NULL,
    [RatedSecondary]     NVARCHAR(20)     NULL,       -- 5 A, 1 A, 115 V, 66.4 V
    [Connection]         NVARCHAR(20)     NULL     CONSTRAINT [CK_InstrumentWinding_Connection] CHECK ([Connection] IN (N'Wye', N'Delta', N'OpenDelta', N'BrokenDelta', N'Single')),
    [TapInUseEntityId]   UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_InstrumentWinding_TapInUse] REFERENCES [asset].[WindingTapRegistry] ([EntityId]),   -- #213: the tap the wires are landed on; set only through asset.SetWindingTap, which copies its ratio into RatioInUse
    [Notes]              NVARCHAR(400)    NULL,
    CONSTRAINT [PK_InstrumentWinding] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_InstrumentWinding_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [asset].[InstrumentWinding_History]));
GO
CREATE INDEX [IX_InstrumentWinding_Entity] ON [asset].[InstrumentWinding] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_InstrumentWinding_AssetNo] ON [asset].[InstrumentWinding] ([AssetEntityId], [WindingNo]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'asset', @level1type = N'TABLE', @level1name = N'InstrumentWinding';
GO
