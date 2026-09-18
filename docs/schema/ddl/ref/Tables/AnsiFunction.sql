-- SCHEMA-DESIGN §7.3 (117). Lifted from the predecessor's 62-row AnsiCodeRegistry (migration, §14.2); no seed.
CREATE TABLE [ref].[AnsiFunction] (
    [AnsiCode]          NVARCHAR(10)      NOT NULL,
    [Name]              NVARCHAR(200)     NOT NULL,
    [Description]       NVARCHAR(MAX)     NULL,
    [Category]          NVARCHAR(40)      NULL,
    [DefaultLnClass]    NVARCHAR(10)      NULL,
    -- #182 (2026-09-17): is [AnsiCode] a real C37.2 device number? The owner, on the functions a relay performs for
    -- which no number exists: "That is to be expected from those devices and should not be left out, they are part of
    -- the device and must be included. When no numbers can be found for the functionality, wording will have to
    -- suffice." So this catalogue holds both: 21 and 51N, which ARE device numbers, and LOP, SOTF, REJO and the rest,
    -- which are the manufacturer's own abbreviations printed in its manual. [Name] always carries the words, and this
    -- flag says which kind of key the code is, so a screen can show a number as a number and everything else as words.
    -- NULL means nobody has said — the migrated codes, which the importer invented from free text, are all NULL.
    [IsDeviceNumber]    BIT               NULL,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AnsiFunction_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AnsiFunction_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_AnsiFunction_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AnsiFunction_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_AnsiFunction] PRIMARY KEY CLUSTERED ([AnsiCode])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [ref].[AnsiFunction_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'ref', @level1type = N'TABLE', @level1name = N'AnsiFunction';
GO
