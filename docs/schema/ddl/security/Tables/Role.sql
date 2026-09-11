-- SCHEMA-DESIGN §11.3 (154). RoleKind is nullable: the design states Positional only for Administrator
-- and Assignment only for work assignment roles in the abstract; the seed leaves the kind unclassified
-- for every other role (STEPS.md).
CREATE TABLE [security].[Role] (
    [RoleCode]          NVARCHAR(40)      NOT NULL CONSTRAINT [PK_Role] PRIMARY KEY CLUSTERED,
    [Name]              NVARCHAR(200)     NOT NULL,
    [RoleKind]          NVARCHAR(20)      NULL     CONSTRAINT [CK_Role_Kind] CHECK ([RoleKind] IS NULL OR [RoleKind] IN (N'Positional', N'Assignment')),
    [Description]       NVARCHAR(MAX)     NULL,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Role_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Role_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_Role_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Role_MigrationRun] REFERENCES [migration].[Run] ([RunId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [security].[Role_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'security', @level1type = N'TABLE', @level1name = N'Role';
GO
