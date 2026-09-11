-- SCHEMA-DESIGN §13.4 (177). Class Reference. Per record kind or event kind, the retention rule —
-- which is a definition the Administrator sets (never a purge, vision §10.6).
-- Shape chosen: one row keyed by RetentionCode, naming exactly one of a record kind
-- (ref.RecordKind) or an event kind (event.Event.SourceKind values), and the definition that holds
-- the rule. No seed: no retention values are stated in the design.
CREATE TABLE [archive].[Retention] (
    [RetentionCode]             NVARCHAR(40)      NOT NULL CONSTRAINT [PK_Retention] PRIMARY KEY CLUSTERED,
    [RecordKindCode]            NVARCHAR(40)      NULL CONSTRAINT [FK_Retention_RecordKind] REFERENCES [ref].[RecordKind] ([RecordKindCode]),
    [EventKind]                 NVARCHAR(40)      NULL CONSTRAINT [CK_Retention_EventKind] CHECK ([EventKind] IS NULL OR [EventKind] IN (N'Dfr', N'RelayEventReport', N'Pmu', N'Ser')),
    [RuleDefinitionEntityId]    UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Retention_RuleDefinition] REFERENCES [config].[DefinitionRegistry] ([EntityId]),
    [Description]               NVARCHAR(MAX)     NULL,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Retention_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Retention_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_Retention_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL CONSTRAINT [FK_Retention_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [CK_Retention_OneKind] CHECK (
        ([RecordKindCode] IS NOT NULL AND [EventKind] IS NULL)
     OR ([RecordKindCode] IS NULL AND [EventKind] IS NOT NULL))
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [archive].[Retention_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'archive', @level1type = N'TABLE', @level1name = N'Retention';
GO
