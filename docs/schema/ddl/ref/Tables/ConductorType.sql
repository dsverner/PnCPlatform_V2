-- SCHEMA-DESIGN §13.2 (172). The conductor library: name, GMR, resistance, diameter, ampacity.
-- The design states no units; each measure carries its unit as a reference to ref.Unit so no unit
-- is assumed here. No seed: rows come from TLM at migration (§14.3).
CREATE TABLE [ref].[ConductorType] (
    [ConductorTypeCode]     NVARCHAR(40)      NOT NULL CONSTRAINT [PK_ConductorType] PRIMARY KEY CLUSTERED,
    [Name]                  NVARCHAR(200)     NOT NULL,
    [Gmr]                   DECIMAL(18,8)     NULL,
    [GmrUnitCode]           NVARCHAR(20)      NULL CONSTRAINT [FK_ConductorType_GmrUnit] REFERENCES [ref].[Unit] ([UnitCode]),
    [Resistance]            DECIMAL(18,8)     NULL,
    [ResistanceUnitCode]    NVARCHAR(20)      NULL CONSTRAINT [FK_ConductorType_ResistanceUnit] REFERENCES [ref].[Unit] ([UnitCode]),
    [Diameter]              DECIMAL(18,8)     NULL,
    [DiameterUnitCode]      NVARCHAR(20)      NULL CONSTRAINT [FK_ConductorType_DiameterUnit] REFERENCES [ref].[Unit] ([UnitCode]),
    [Ampacity]              DECIMAL(18,4)     NULL,
    [AmpacityUnitCode]      NVARCHAR(20)      NULL CONSTRAINT [FK_ConductorType_AmpacityUnit] REFERENCES [ref].[Unit] ([UnitCode]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ConductorType_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ConductorType_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_ConductorType_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL CONSTRAINT [FK_ConductorType_MigrationRun] REFERENCES [migration].[Run] ([RunId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [ref].[ConductorType_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'ref', @level1type = N'TABLE', @level1name = N'ConductorType';
GO
