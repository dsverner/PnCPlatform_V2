-- Decision #226. The catalogue of what a person may show or hide: one row per named part of a screen (a tab today,
-- a panel later). A screen declares its items here, so a new one appears without a code change. Hiding is a
-- preference and never a permission — an item hidden here is still one click away, and only security.fHasPermission
-- refuses anything. Rows are Administrator/seed content, as the other catalogues are.
CREATE TABLE [config].[ViewItem] (
    [ScreenKey]         NVARCHAR(60)      NOT NULL,
    [ItemKey]           NVARCHAR(60)      NOT NULL,
    [Name]              NVARCHAR(100)     NOT NULL,
    [Description]       NVARCHAR(400)     NULL,
    [ItemKind]          NVARCHAR(20)      NOT NULL CONSTRAINT [DF_ViewItem_ItemKind] DEFAULT N'Tab'
                        CONSTRAINT [CK_ViewItem_ItemKind] CHECK ([ItemKind] IN (N'Tab', N'Panel', N'Column', N'NavGroup')),
    [DisplayOrder]      INT               NOT NULL CONSTRAINT [DF_ViewItem_DisplayOrder] DEFAULT 0,
    [ShownByDefault]    BIT               NOT NULL CONSTRAINT [DF_ViewItem_ShownByDefault] DEFAULT 1,
    [IsAlways]          BIT               NOT NULL CONSTRAINT [DF_ViewItem_IsAlways] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ViewItem_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ViewItem_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_ViewItem_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ViewItem_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_ViewItem] PRIMARY KEY CLUSTERED ([ScreenKey], [ItemKey])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [config].[ViewItem_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'config', @level1type = N'TABLE', @level1name = N'ViewItem';
GO
