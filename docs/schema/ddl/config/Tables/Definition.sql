-- SCHEMA-DESIGN §2.1 (74). Class Versioned. One row per definition (the thing); its versions
-- are config.DefinitionVersion. OwningRoleCode → security.Role: the FK is added with step 11.
CREATE TABLE [config].[Definition] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Definition_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Definition_Registry] REFERENCES [config].[DefinitionRegistry] ([EntityId]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Definition_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Definition_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Definition_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Definition_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Definition_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [DefinitionKind]    NVARCHAR(40)      NOT NULL CONSTRAINT [FK_Definition_Kind] REFERENCES [ref].[DefinitionKind] ([DefinitionKind]),
    [DefinitionKey]     NVARCHAR(100)     NOT NULL,
    [Name]              NVARCHAR(200)     NOT NULL,
    [Description]       NVARCHAR(MAX)     NULL,
    [OwningRoleCode]    NVARCHAR(40)      NULL     CONSTRAINT [FK_Definition_OwningRole] REFERENCES [security].[Role] ([RoleCode]),
    CONSTRAINT [PK_Definition] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Definition_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [config].[Definition_History]));
GO
CREATE INDEX [IX_Definition_Entity] ON [config].[Definition] ([EntityId]);
GO
CREATE UNIQUE INDEX [UX_Definition_KindKey] ON [config].[Definition] ([DefinitionKind], [DefinitionKey]) WHERE [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'config', @level1type = N'TABLE', @level1name = N'Definition';
GO
