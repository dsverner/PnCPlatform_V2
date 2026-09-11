-- SCHEMA-DESIGN §1.3 (decision 65). Per object class: are reads logged. Class Reference.
-- The design names ChangedBy / ChangedAt; here they are the standard ModifiedBy / ModifiedAt of
-- the reference block (STEPS.md notes the rename).
CREATE TABLE [config].[ReadLoggedClass] (
    [SchemaName]        SYSNAME           NOT NULL,
    [TableName]         SYSNAME           NOT NULL,
    [IsLogged]          BIT               NOT NULL CONSTRAINT [DF_ReadLoggedClass_IsLogged] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ReadLoggedClass_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ReadLoggedClass_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_ReadLoggedClass_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL CONSTRAINT [FK_ReadLoggedClass_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_ReadLoggedClass] PRIMARY KEY CLUSTERED ([SchemaName], [TableName])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [config].[ReadLoggedClass_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'config', @level1type = N'TABLE', @level1name = N'ReadLoggedClass';
GO
