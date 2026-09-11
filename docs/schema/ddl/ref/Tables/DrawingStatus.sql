-- SCHEMA-DESIGN §8.9 (133). "The predecessor's six states, lifted" — the design does not name them, so no
-- seed; rows come from migration (§14.2).
CREATE TABLE [ref].[DrawingStatus] (
    [DrawingStatusCode] NVARCHAR(40)      NOT NULL,
    [Name]              NVARCHAR(200)     NOT NULL,
    [Description]       NVARCHAR(MAX)     NULL,
    [DisplayOrder]      INT               NOT NULL CONSTRAINT [DF_DrawingStatus_DisplayOrder] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_DrawingStatus_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_DrawingStatus_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_DrawingStatus_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_DrawingStatus_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_DrawingStatus] PRIMARY KEY CLUSTERED ([DrawingStatusCode])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [ref].[DrawingStatus_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'ref', @level1type = N'TABLE', @level1name = N'DrawingStatus';
GO
