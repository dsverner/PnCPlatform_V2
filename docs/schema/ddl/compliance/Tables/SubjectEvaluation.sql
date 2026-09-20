-- #214 (2026-09-20): when a subject was last evaluated, and by which pass. One row per subject the evaluator has seen; the
-- Effective pass upserts it (compliance.SubjectEvaluation_Upsert, generated) at the end of each subject. This is what a
-- device's Compliance tab reads for "Evaluated 16:43 · hourly pass" — the platform's own timestamp, never a preview's.
-- Current state, system-versioned: what the platform believed on a date is the history table; the run it names is the
-- actor-attributed record of the pass.
CREATE TABLE [compliance].[SubjectEvaluation] (
    [SubjectKind]        NVARCHAR(40)      NOT NULL,
    [SubjectEntityId]    UNIQUEIDENTIFIER  NOT NULL,
    [LastRunId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SubjectEvaluation_Run] REFERENCES [compliance].[RuleEvaluationRun] ([RunId]),
    [LastEvaluatedAt]    DATETIMEOFFSET(7) NOT NULL,
    [LastTrigger]        NVARCHAR(20)      NOT NULL,   -- Scheduled | FactChanged | RuleApproved | Manual (the run's)
    [RulesEvaluated]     INT               NOT NULL,
    [SysStart]           DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]             DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SubjectEvaluation_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]          DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SubjectEvaluation_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]         DATETIMEOFFSET(7) NOT NULL,
    [IsActive]           BIT               NOT NULL CONSTRAINT [DF_SubjectEvaluation_IsActive] DEFAULT 1,
    [MigrationRunId]     UNIQUEIDENTIFIER  NULL CONSTRAINT [FK_SubjectEvaluation_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_SubjectEvaluation] PRIMARY KEY CLUSTERED ([SubjectKind], [SubjectEntityId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [compliance].[SubjectEvaluation_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'compliance', @level1type = N'TABLE', @level1name = N'SubjectEvaluation';
GO
