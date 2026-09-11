-- SCHEMA-DESIGN §1.2. A migration run: source, capture instant, cleansing-rule version applied.
-- Class AppendOnly; CompletedAt is set once by migration.CompleteRun (hand-written) — the row is
-- otherwise never changed.
-- CleansingRuleVersionRowId is nullable here because development and training loads (§14.1)
-- run before any cleansing definition has been authored; production runs must supply it
-- (checked by the migration procedure, MIGRATION-PLAN.md).
CREATE TABLE [migration].[Run] (
    [RunId]                     UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [PK_Run] PRIMARY KEY CLUSTERED CONSTRAINT [DF_Run_RunId] DEFAULT NEWSEQUENTIALID(),
    [SourceSystem]              NVARCHAR(50)      NOT NULL,
    [SourceCaptureAt]           DATETIMEOFFSET(7) NOT NULL,
    [CleansingRuleVersionRowId] UNIQUEIDENTIFIER  NULL CONSTRAINT [FK_Run_CleansingRuleVersion] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [StartedAt]                 DATETIMEOFFSET(7) NOT NULL,
    [CompletedAt]               DATETIMEOFFSET(7) NULL,
    [RunByActorId]              UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Run_RunBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [Notes]                     NVARCHAR(MAX)     NULL
);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'migration', @level1type = N'TABLE', @level1name = N'Run';
GO
