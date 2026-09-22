-- Decision #226. What a role starts people with: the default answer for one view item, per role. A person who has
-- made no choice of their own sees an item when ANY role they hold says to show it — the widest wins, so holding a
-- second role never takes anything away. An Administrator editing a row here changes what people who have not
-- chosen see; it never overwrites a choice someone has made for themselves.
CREATE TABLE [config].[RoleViewItem] (
    [RoleCode]          NVARCHAR(40)      NOT NULL CONSTRAINT [FK_RoleViewItem_Role] REFERENCES [security].[Role] ([RoleCode]),
    [ScreenKey]         NVARCHAR(60)      NOT NULL,
    [ItemKey]           NVARCHAR(60)      NOT NULL,
    [IsShown]           BIT               NOT NULL,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_RoleViewItem_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_RoleViewItem_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_RoleViewItem_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_RoleViewItem_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_RoleViewItem] PRIMARY KEY CLUSTERED ([RoleCode], [ScreenKey], [ItemKey]),
    CONSTRAINT [FK_RoleViewItem_Item] FOREIGN KEY ([ScreenKey], [ItemKey]) REFERENCES [config].[ViewItem] ([ScreenKey], [ItemKey])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [config].[RoleViewItem_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'config', @level1type = N'TABLE', @level1name = N'RoleViewItem';
GO
