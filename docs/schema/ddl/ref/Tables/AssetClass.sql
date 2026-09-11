-- SCHEMA-DESIGN §4.1 (88). The four asset classes. `Rule` holds the vision's one-line rule per class;
-- left null by the seed (the rule text lives in the vision, not in the design's table).
CREATE TABLE [ref].[AssetClass] (
    [AssetClassCode]    NVARCHAR(40)      NOT NULL,
    [Name]              NVARCHAR(200)     NOT NULL,
    [Rule]              NVARCHAR(400)     NULL,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AssetClass_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AssetClass_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_AssetClass_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AssetClass_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_AssetClass] PRIMARY KEY CLUSTERED ([AssetClassCode])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [ref].[AssetClass_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'ref', @level1type = N'TABLE', @level1name = N'AssetClass';
GO
