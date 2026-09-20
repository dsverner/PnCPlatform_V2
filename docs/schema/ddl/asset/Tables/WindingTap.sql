-- #213 (2026-09-20): a secondary winding's TAPS as discrete rows. The owner: "Every CT has discrete tap capabilities which
-- should be listed even though they may not be known at this time." A tap is a terminal pair with a fixed ratio on the
-- nameplate (X1-X2 = 600:5, X1-X3 = 1200:5); the ratio in use is which pair the wires are landed on
-- (asset.InstrumentWinding.TapInUseEntityId, landed only through asset.SetWindingTap, which writes the winding's RatioInUse
-- from the tap's ratio), so it is a setting of the protection in the CTR sense — chosen, discrete, changed on purpose. A
-- winding with no tap rows keeps its text ratio: unknown taps stay unknown, none is invented. Terminals are optional —
-- some nameplates list ratios only. The tap rows are the winding-side terminals the cabling phase will land on.
-- Bi-temporal; one current row per winding and tap number.
CREATE TABLE [asset].[WindingTap] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_WindingTap_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_WindingTap_Registry] REFERENCES [asset].[WindingTapRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_WindingTap_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_WindingTap_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_WindingTap_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_WindingTap_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_WindingTap_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_WindingTap_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [WindingEntityId]    UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_WindingTap_Winding] REFERENCES [asset].[InstrumentWindingRegistry] ([EntityId]),
    [TapNo]              TINYINT          NOT NULL CONSTRAINT [CK_WindingTap_No] CHECK ([TapNo] >= 1),
    [Terminals]          NVARCHAR(40)     NULL,       -- the pair as the nameplate marks it: X1-X3
    [Ratio]              NVARCHAR(40)     NOT NULL,   -- 1200:5 (read as 240 by the views)
    [Notes]              NVARCHAR(400)    NULL,
    CONSTRAINT [PK_WindingTap] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_WindingTap_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [asset].[WindingTap_History]));
GO
CREATE INDEX [IX_WindingTap_Entity] ON [asset].[WindingTap] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_WindingTap_WindingNo] ON [asset].[WindingTap] ([WindingEntityId], [TapNo]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'asset', @level1type = N'TABLE', @level1name = N'WindingTap';
GO
