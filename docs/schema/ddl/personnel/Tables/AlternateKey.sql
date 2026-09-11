-- SCHEMA-DESIGN §0.4 (68). The identities the field uses for a personnel entity. Each key row has its own identity
-- (EntityId → AlternateKeyRegistry) and SubjectEntityId names the thing (STEPS.md step 3 flag).
CREATE TABLE [personnel].[AlternateKey] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_AlternateKey_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AlternateKey_Registry] REFERENCES [personnel].[AlternateKeyRegistry] ([EntityId]),
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
    [SubjectEntityId]    UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_AlternateKey_Subject] REFERENCES [personnel].[PersonRegistry] ([EntityId]),
    [KeyKindCode]        NVARCHAR(50)     NOT NULL CONSTRAINT [FK_AlternateKey_Kind] REFERENCES [ref].[AlternateKeyKind] ([KeyKindCode]),
    [KeyValue]           NVARCHAR(200)    NOT NULL,
    [ScopeEntityId]      UNIQUEIDENTIFIER NULL,
    [IsPrimaryLabel]     BIT              NOT NULL CONSTRAINT [DF_AlternateKey_IsPrimaryLabel] DEFAULT 0,
    CONSTRAINT [PK_AlternateKey] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_AlternateKey_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [personnel].[AlternateKey_History]));
GO
CREATE INDEX [IX_AlternateKey_Entity] ON [personnel].[AlternateKey] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_AlternateKey_Value] ON [personnel].[AlternateKey] ([KeyKindCode], [KeyValue], [ScopeEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
CREATE INDEX [IX_AlternateKey_Subject] ON [personnel].[AlternateKey] ([SubjectEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'personnel', @level1type = N'TABLE', @level1name = N'AlternateKey';
GO
