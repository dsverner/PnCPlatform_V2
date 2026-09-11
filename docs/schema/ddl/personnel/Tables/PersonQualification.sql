-- SCHEMA-DESIGN §11.6 (157). Valid period = while held. OjtHoursCompleted is derived from OJT records by rule.
CREATE TABLE [personnel].[PersonQualification] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_PersonQualification_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_PersonQualification_Registry] REFERENCES [personnel].[PersonQualificationRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_PersonQualification_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_PersonQualification_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_PersonQualification_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_PersonQualification_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_PersonQualification_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_PersonQualification_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [PersonEntityId]     UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_PersonQualification_Person] REFERENCES [personnel].[PersonRegistry] ([EntityId]),
    [QualificationTypeCode] NVARCHAR(40)  NOT NULL CONSTRAINT [FK_PersonQualification_Type] REFERENCES [personnel].[QualificationType] ([QualificationTypeCode]),
    [GrantedAt]          DATETIMEOFFSET(7) NOT NULL,
    [GrantedByActorId]   UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_PersonQualification_GrantedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ExpiresAt]          DATETIMEOFFSET(7) NULL,
    [AssessmentRecordEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_PersonQualification_Assessment] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [OjtHoursCompleted]  DECIMAL(8,2)     NULL,
    [RevokedAt]          DATETIMEOFFSET(7) NULL,
    [RevocationReason]   NVARCHAR(400)    NULL,
    CONSTRAINT [PK_PersonQualification] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_PersonQualification_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [personnel].[PersonQualification_History]));
GO
CREATE INDEX [IX_PersonQualification_Entity] ON [personnel].[PersonQualification] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_PersonQualification_Person] ON [personnel].[PersonQualification] ([PersonEntityId], [QualificationTypeCode]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'personnel', @level1type = N'TABLE', @level1name = N'PersonQualification';
GO
