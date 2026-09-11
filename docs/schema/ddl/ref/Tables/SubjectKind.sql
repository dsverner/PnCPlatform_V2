-- CONVENTIONS.md "Polymorphic references". Maps every polymorphic kind name used by
-- SubjectKind / MemberKind / ScopeKind / FromKind columns to the registry (or keyed table)
-- that holds the entity, so meta.fEntityExists can validate a reference generically.
CREATE TABLE [ref].[SubjectKind] (
    [SubjectKindCode]   NVARCHAR(40)      NOT NULL CONSTRAINT [PK_SubjectKind] PRIMARY KEY CLUSTERED,
    [Name]              NVARCHAR(200)     NOT NULL,
    [SchemaName]        SYSNAME           NULL,       -- where the identity lives; null = a kind with no table (Platform)
    [TableName]         SYSNAME           NULL,       -- the registry or keyed table
    [KeyColumnName]     SYSNAME           NULL,       -- EntityId, RowId, or the natural key
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SubjectKind_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SubjectKind_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_SubjectKind_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [ref].[SubjectKind_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'ref', @level1type = N'TABLE', @level1name = N'SubjectKind';
GO
