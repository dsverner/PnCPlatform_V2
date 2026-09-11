-- SCHEMA-DESIGN §0.4 (68). Per kind: which schema and subject kind may carry it and whether a
-- scope is required.
CREATE TABLE [ref].[AlternateKeyKind] (
    [KeyKindCode]       NVARCHAR(50)      NOT NULL CONSTRAINT [PK_AlternateKeyKind] PRIMARY KEY CLUSTERED,
    [Name]              NVARCHAR(200)     NOT NULL,
    [SchemaName]        SYSNAME           NOT NULL,   -- the <schema>.AlternateKey table that holds it
    [SubjectKindCode]   NVARCHAR(40)      NOT NULL CONSTRAINT [FK_AlternateKeyKind_SubjectKind] REFERENCES [ref].[SubjectKind] ([SubjectKindCode]),
    [ScopeRequired]     BIT               NOT NULL CONSTRAINT [DF_AlternateKeyKind_ScopeRequired] DEFAULT 0,
    [ScopeSubjectKindCode] NVARCHAR(40)   NULL CONSTRAINT [FK_AlternateKeyKind_ScopeKind] REFERENCES [ref].[SubjectKind] ([SubjectKindCode]),
    [Description]       NVARCHAR(MAX)     NULL,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AlternateKeyKind_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AlternateKeyKind_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_AlternateKeyKind_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL,
    CONSTRAINT [CK_AlternateKeyKind_Scope] CHECK ([ScopeRequired] = 0 OR [ScopeSubjectKindCode] IS NOT NULL)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [ref].[AlternateKeyKind_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'ref', @level1type = N'TABLE', @level1name = N'AlternateKeyKind';
GO
