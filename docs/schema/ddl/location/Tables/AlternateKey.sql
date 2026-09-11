-- SCHEMA-DESIGN §0.4 (68). The identities the field and the drawings use for a node.
-- The design writes EntityId as "the thing the key names"; here each key row has its own identity
-- (EntityId → AlternateKeyRegistry) and SubjectEntityId names the node, because the base
-- rule of one current row per EntityId would otherwise allow only one key per thing (STEPS.md).
CREATE TABLE [location].[AlternateKey] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_AlternateKey_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AlternateKey_Registry] REFERENCES [location].[AlternateKeyRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_AlternateKey_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AlternateKey_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AlternateKey_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_AlternateKey_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AlternateKey_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AlternateKey_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [SubjectEntityId]    UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_AlternateKey_Subject] REFERENCES [location].[NodeRegistry] ([EntityId]),
    [KeyKindCode]        NVARCHAR(50)     NOT NULL CONSTRAINT [FK_AlternateKey_Kind] REFERENCES [ref].[AlternateKeyKind] ([KeyKindCode]),
    [KeyValue]           NVARCHAR(200)    NOT NULL,
    [ScopeEntityId]      UNIQUEIDENTIFIER NULL,
    [IsPrimaryLabel]     BIT              NOT NULL CONSTRAINT [DF_AlternateKey_IsPrimaryLabel] DEFAULT 0,
    CONSTRAINT [PK_AlternateKey] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_AlternateKey_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [location].[AlternateKey_History]));
GO
CREATE INDEX [IX_AlternateKey_Entity] ON [location].[AlternateKey] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_AlternateKey_Value] ON [location].[AlternateKey] ([KeyKindCode], [KeyValue], [ScopeEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
CREATE INDEX [IX_AlternateKey_Subject] ON [location].[AlternateKey] ([SubjectEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'location', @level1type = N'TABLE', @level1name = N'AlternateKey';
GO
