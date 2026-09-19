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
    -- #197 (2026-09-19): is this function one PRC-023-6 applies to? The standard binds "load-responsive phase protection
    -- systems as described in Attachment A" (4.1): Attachment A 1 lists the functions included (phase distance, out-of-step,
    -- switch-on-to-fault, overcurrent, communications-aided schemes), Attachment A 2 the exclusions (ground fault detection,
    -- elements enabled only on failure of others, RAS-only, 15-minute-or-slower, thermal emulation, dc lines and converter
    -- transformers). 1 = included, 0 = excluded or not listed, NULL = nobody has ruled (the migrated strings). [LoadResponsiveBasis]
    -- names the clause. Set by the core seed for the C37.2 numbers; a legacy string is read through ref.fAnsiLoadResponsive.
    [LoadResponsive]    BIT               NULL,
    [LoadResponsiveBasis] NVARCHAR(200)   NULL,
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
