-- SCHEMA-DESIGN §7.2 (116). Seeded from the design's list; extensible.
CREATE TABLE [ref].[SchemeMemberRole] (
    [MemberRoleCode]    NVARCHAR(40)      NOT NULL,
    [Name]              NVARCHAR(200)     NOT NULL,
    [Description]       NVARCHAR(MAX)     NULL,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SchemeMemberRole_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SchemeMemberRole_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_SchemeMemberRole_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_SchemeMemberRole_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_SchemeMemberRole] PRIMARY KEY CLUSTERED ([MemberRoleCode])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [ref].[SchemeMemberRole_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'ref', @level1type = N'TABLE', @level1name = N'SchemeMemberRole';
GO
