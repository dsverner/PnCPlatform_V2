-- SCHEMA-DESIGN §11.6 (157). Lifted from the predecessor's QualificationPath; rows are migration.
CREATE TABLE [personnel].[QualificationType] (
    [QualificationTypeCode] NVARCHAR(40)  NOT NULL CONSTRAINT [PK_QualificationType] PRIMARY KEY CLUSTERED,
    [Name]              NVARCHAR(200)     NOT NULL,
    [WorkCategory]      NVARCHAR(40)      NULL,
    [ApplicableAssetTypeCode] NVARCHAR(40) NULL   CONSTRAINT [FK_QualificationType_AssetType] REFERENCES [ref].[AssetType] ([AssetTypeCode]),
    [RequiredOjtHours]  DECIMAL(8,2)      NULL,
    [RequiredExperienceYears] DECIMAL(4,1) NULL,
    [RecertificationDays] INT             NULL,
    [RequiresSupervisorSignOff] BIT       NOT NULL CONSTRAINT [DF_QualificationType_SupervisorSignOff] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_QualificationType_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_QualificationType_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_QualificationType_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_QualificationType_MigrationRun] REFERENCES [migration].[Run] ([RunId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [personnel].[QualificationType_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'personnel', @level1type = N'TABLE', @level1name = N'QualificationType';
GO
