-- SCHEMA-DESIGN §11.6 (157). Rows are migration. EntityId (2026-09-06, PROCEDURES.md #35): a Reference row a
-- record.Record can cite as its second subject (kind TrainingModule) — a code has no place in SecondSubjectEntityId.
CREATE TABLE [personnel].[TrainingModule] (
    [TrainingModuleCode] NVARCHAR(40)     NOT NULL CONSTRAINT [PK_TrainingModule] PRIMARY KEY CLUSTERED,
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_TrainingModule_EntityId] DEFAULT NEWID() CONSTRAINT [UQ_TrainingModule_EntityId] UNIQUE,
    [Name]              NVARCHAR(200)     NOT NULL,
    [Category]          NVARCHAR(40)      NULL,
    [DeliveryMethod]    NVARCHAR(40)      NULL,
    [RequiredFrequencyDays] INT           NULL,
    [DurationHours]     DECIMAL(6,2)      NULL,
    [CipModuleCode]     NVARCHAR(40)      NULL,
    [ProviderEntityEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_TrainingModule_Provider] REFERENCES [party].[EntityRegistry] ([EntityId]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_TrainingModule_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_TrainingModule_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_TrainingModule_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_TrainingModule_MigrationRun] REFERENCES [migration].[Run] ([RunId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [personnel].[TrainingModule_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'personnel', @level1type = N'TABLE', @level1name = N'TrainingModule';
GO
