-- SCHEMA-DESIGN §7.3 (117). Lifted from the predecessor's 62-row AnsiCodeRegistry (migration, §14.2); no seed.
CREATE TABLE [ref].[AnsiFunction] (
    [AnsiCode]          NVARCHAR(10)      NOT NULL,
    [Name]              NVARCHAR(200)     NOT NULL,
    [Description]       NVARCHAR(MAX)     NULL,
    [Category]          NVARCHAR(40)      NULL,
    [DefaultLnClass]    NVARCHAR(10)      NULL,
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
