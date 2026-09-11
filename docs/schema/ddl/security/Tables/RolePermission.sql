-- SCHEMA-DESIGN §11.3 (154). No seed: the design does not map roles to permissions (STEPS.md).
CREATE TABLE [security].[RolePermission] (
    [RoleCode]          NVARCHAR(40)      NOT NULL CONSTRAINT [FK_RolePermission_Role] REFERENCES [security].[Role] ([RoleCode]),
    [PermissionCode]    NVARCHAR(80)      NOT NULL CONSTRAINT [FK_RolePermission_Permission] REFERENCES [security].[Permission] ([PermissionCode]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_RolePermission_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_RolePermission_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_RolePermission_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_RolePermission_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_RolePermission] PRIMARY KEY CLUSTERED ([RoleCode], [PermissionCode])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [security].[RolePermission_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'security', @level1type = N'TABLE', @level1name = N'RolePermission';
GO
