-- SCHEMA-DESIGN §4.9 (97). Units with dimension and conversion to a base unit.
-- Open item (§2.10): whether this is seeded from an external registry or hand-authored; the
-- seed here carries only the codes the design lists, with factors only where they are SI.
CREATE TABLE [ref].[Unit] (
    [UnitCode]          NVARCHAR(20)      NOT NULL CONSTRAINT [PK_Unit] PRIMARY KEY CLUSTERED,
    [Name]              NVARCHAR(100)     NOT NULL,
    [Dimension]         NVARCHAR(40)      NOT NULL CONSTRAINT [CK_Unit_Dimension] CHECK ([Dimension] IN (N'Voltage', N'Current', N'Power', N'ReactivePower', N'ApparentPower', N'Energy', N'Charge', N'Impedance', N'Time', N'Frequency', N'Length', N'Temperature', N'Ratio', N'Angle', N'Other')),
    [BaseUnitCode]      NVARCHAR(20)      NULL CONSTRAINT [FK_Unit_Base] REFERENCES [ref].[Unit] ([UnitCode]),
    [ToBaseFactor]      DECIMAL(28,12)    NULL,      -- value in this unit × factor = value in base unit; null = not convertible / unknown
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Unit_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Unit_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_Unit_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [ref].[Unit_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'ref', @level1type = N'TABLE', @level1name = N'Unit';
GO
