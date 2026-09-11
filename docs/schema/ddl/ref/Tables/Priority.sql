-- SCHEMA-DESIGN §9.1. Work Request priority. No values are stated in the design; none seeded (STEPS.md).
CREATE TABLE [ref].[Priority] (
    [PriorityCode]      NVARCHAR(40)      NOT NULL CONSTRAINT [PK_Priority] PRIMARY KEY CLUSTERED,
    [Name]              NVARCHAR(200)     NOT NULL,
    [DisplayOrder]      INT               NOT NULL CONSTRAINT [DF_Priority_DisplayOrder] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Priority_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Priority_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_Priority_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Priority_MigrationRun] REFERENCES [migration].[Run] ([RunId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [ref].[Priority_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'ref', @level1type = N'TABLE', @level1name = N'Priority';
GO
