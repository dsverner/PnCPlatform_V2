-- SCHEMA-DESIGN §11.1 (152, 160). AD asserts identity and nothing more: no password, no session.
-- ActiveDirectorySid is a security.AlternateKey row.
CREATE TABLE [security].[User] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_User_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_User_Registry] REFERENCES [security].[UserRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_User_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_User_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_User_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_User_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_User_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_User_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [PersonEntityId]     UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_User_Person] REFERENCES [personnel].[PersonRegistry] ([EntityId]),
    [UserPrincipalName]  NVARCHAR(200)    NOT NULL,
    [IsEnabled]          BIT              NOT NULL CONSTRAINT [DF_User_IsEnabled] DEFAULT 1,
    [DisabledAt]         DATETIMEOFFSET(7) NULL,
    [DisabledReason]     NVARCHAR(400)    NULL,
    CONSTRAINT [PK_User] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_User_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [security].[User_History]));
GO
CREATE INDEX [IX_User_Entity] ON [security].[User] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_User_Upn] ON [security].[User] ([UserPrincipalName]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'security', @level1type = N'TABLE', @level1name = N'User';
GO
