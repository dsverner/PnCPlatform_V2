-- SCHEMA-DESIGN §11.3 (154). PermissionCode = <SubjectClass>.<Verb> with the vision's six verbs (§3.4).
CREATE TABLE [security].[Permission] (
    [PermissionCode]    NVARCHAR(80)      NOT NULL CONSTRAINT [PK_Permission] PRIMARY KEY CLUSTERED,
    [SubjectClass]      NVARCHAR(40)      NOT NULL,
    [Verb]              NVARCHAR(20)      NOT NULL CONSTRAINT [CK_Permission_Verb] CHECK ([Verb] IN (N'Read', N'Modify', N'Approve', N'Archive', N'Report', N'Administer')),
    [Name]              NVARCHAR(200)     NOT NULL,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Permission_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Permission_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_Permission_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Permission_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [CK_Permission_Code] CHECK ([PermissionCode] = [SubjectClass] + N'.' + [Verb])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [security].[Permission_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'security', @level1type = N'TABLE', @level1name = N'Permission';
GO
