-- SCHEMA-DESIGN §11.6 (157).
CREATE TABLE [personnel].[QualificationTypeModule] (
    [QualificationTypeCode] NVARCHAR(40)  NOT NULL CONSTRAINT [FK_QualificationTypeModule_Type] REFERENCES [personnel].[QualificationType] ([QualificationTypeCode]),
    [TrainingModuleCode] NVARCHAR(40)     NOT NULL CONSTRAINT [FK_QualificationTypeModule_Module] REFERENCES [personnel].[TrainingModule] ([TrainingModuleCode]),
    [IsPrerequisite]    BIT               NOT NULL CONSTRAINT [DF_QualificationTypeModule_IsPrerequisite] DEFAULT 0,
    [MinimumPassScore]  DECIMAL(5,2)      NULL,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_QualificationTypeModule_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_QualificationTypeModule_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_QualificationTypeModule_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_QualificationTypeModule_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_QualificationTypeModule] PRIMARY KEY CLUSTERED ([QualificationTypeCode], [TrainingModuleCode])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [personnel].[QualificationTypeModule_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'personnel', @level1type = N'TABLE', @level1name = N'QualificationTypeModule';
GO
