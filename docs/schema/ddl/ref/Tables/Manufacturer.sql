-- SCHEMA-DESIGN §4.8 (96). Thin reference over party.Entity rows of kind Manufacturer.
CREATE TABLE [ref].[Manufacturer] (
    [ManufacturerId]    UNIQUEIDENTIFIER  NOT NULL,
    [EntityEntityId]    UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Manufacturer_Entity] REFERENCES [party].[EntityRegistry] ([EntityId]),
    [ShortCode]         NVARCHAR(20)      NOT NULL,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Manufacturer_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Manufacturer_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_Manufacturer_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Manufacturer_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_Manufacturer] PRIMARY KEY CLUSTERED ([ManufacturerId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [ref].[Manufacturer_History]));
GO
CREATE UNIQUE INDEX [UX_Manufacturer_ShortCode] ON [ref].[Manufacturer] ([ShortCode]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'ref', @level1type = N'TABLE', @level1name = N'Manufacturer';
GO
