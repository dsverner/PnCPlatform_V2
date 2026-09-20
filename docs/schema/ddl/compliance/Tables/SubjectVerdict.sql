-- #214 (2026-09-20): the platform's standing verdict for one subject and one rule (or one classification derivation): what
-- the last Effective pass decided, why, and what it read. This is what replaced the Compliance tab's preview — the owner
-- asked why an Evaluate now button was necessary; now the tab reads the decision the platform already made. A rule that
-- has never applied to a device has a row here saying so with its reason (#197: "there must be a reason"), which the
-- obligation trail alone never held. Written only when the verdict changes (compliance.RecordSubjectVerdict), so SinceAt is
-- when the present verdict began; when the subject was last looked at is compliance.SubjectEvaluation. Current state,
-- system-versioned: the history table keeps every earlier verdict.
--   VerdictKind  Rule | Derivation
--   Result       a rule: true | false | unknown | error; a derivation: the value derived (BCA, Not BCA) or null when undetermined
--   Reason       in words, from the reads (Engine/ComplianceEvaluator.cs Reasons): "no in-service load-responsive element — …"
--   ReadsJson    the facts read, [{"name","params","value"}], the same trail an obligation instance carries
CREATE TABLE [compliance].[SubjectVerdict] (
    [SubjectKind]        NVARCHAR(40)      NOT NULL,
    [SubjectEntityId]    UNIQUEIDENTIFIER  NOT NULL,
    [VerdictKind]        NVARCHAR(20)      NOT NULL CONSTRAINT [CK_SubjectVerdict_Kind] CHECK ([VerdictKind] IN (N'Rule', N'Derivation')),
    [DefinitionEntityId] UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SubjectVerdict_Definition] REFERENCES [config].[DefinitionRegistry] ([EntityId]),
    [VersionRowId]       UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SubjectVerdict_Version] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [Result]             NVARCHAR(60)      NULL,
    [Reason]             NVARCHAR(400)     NULL,
    [ReadsJson]          NVARCHAR(MAX)     NULL,
    [Error]              NVARCHAR(400)     NULL,
    [SinceRunId]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SubjectVerdict_SinceRun] REFERENCES [compliance].[RuleEvaluationRun] ([RunId]),
    [SinceAt]            DATETIMEOFFSET(7) NOT NULL,
    [SysStart]           DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]             DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SubjectVerdict_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]          DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SubjectVerdict_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]         DATETIMEOFFSET(7) NOT NULL,
    [IsActive]           BIT               NOT NULL CONSTRAINT [DF_SubjectVerdict_IsActive] DEFAULT 1,
    [MigrationRunId]     UNIQUEIDENTIFIER  NULL CONSTRAINT [FK_SubjectVerdict_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_SubjectVerdict] PRIMARY KEY CLUSTERED ([SubjectKind], [SubjectEntityId], [VerdictKind], [DefinitionEntityId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [compliance].[SubjectVerdict_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'compliance', @level1type = N'TABLE', @level1name = N'SubjectVerdict';
GO
