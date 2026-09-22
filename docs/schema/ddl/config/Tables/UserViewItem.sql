-- Decision #226. One person's own answer for one view item, kept the way every other change is kept: valid time, so
-- what someone chose last March is still readable, and soft delete, so going back to the role's default is itself a
-- recorded act. Only config.SetViewItem writes here, and it writes only the calling person's row — the user is taken
-- from the session, never from a parameter, so nobody can set another person's view.
CREATE TABLE [config].[UserViewItem] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_UserViewItem_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_UserViewItem_Registry] REFERENCES [config].[UserViewItemRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_UserViewItem_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_UserViewItem_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_UserViewItem_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_UserViewItem_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_UserViewItem_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_UserViewItem_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [UserEntityId]      UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_UserViewItem_User] REFERENCES [security].[UserRegistry] ([EntityId]),
    [ScreenKey]         NVARCHAR(60)      NOT NULL,
    [ItemKey]           NVARCHAR(60)      NOT NULL,
    [IsShown]           BIT               NOT NULL,
    CONSTRAINT [PK_UserViewItem] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_UserViewItem_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [config].[UserViewItem_History]));
GO
CREATE INDEX [IX_UserViewItem_Entity] ON [config].[UserViewItem] ([EntityId], [ValidFrom]);
GO
-- one live answer per person per item, so a screen resolves its shape in a single seek
CREATE UNIQUE INDEX [UX_UserViewItem_Mine] ON [config].[UserViewItem] ([UserEntityId], [ScreenKey], [ItemKey])
    INCLUDE ([IsShown]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'config', @level1type = N'TABLE', @level1name = N'UserViewItem';
GO
