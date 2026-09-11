-- PLATFORM-ARCHITECTURE §8.1 (226), §9.1 (228); SCHEMA-DESIGN §15.6 (233). Class AppendOnly. One row per
-- deployment of a release to an environment — the answer to "what were you running on that date" for the
-- database this row lives in. The checklist record (kind PlatformDeployment, subject Platform) carries the
-- relocation / deployment checklist outcome as characteristics.
CREATE TABLE [platform].[Deployment] (
    [DeploymentId]           BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_Deployment] PRIMARY KEY CLUSTERED,
    [ReleaseId]              BIGINT            NOT NULL CONSTRAINT [FK_Deployment_Release] REFERENCES [platform].[Release] ([ReleaseId]),
    [Environment]            NVARCHAR(10)      NOT NULL CONSTRAINT [CK_Deployment_Environment] CHECK ([Environment] IN (N'DEV', N'QA', N'TRAIN', N'PROD')),
    [DatabaseName]           SYSNAME           NOT NULL,
    [DeployedAt]             DATETIMEOFFSET(7) NOT NULL,
    [DeployedByActorId]      UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Deployment_DeployedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [Outcome]                NVARCHAR(20)      NOT NULL CONSTRAINT [CK_Deployment_Outcome] CHECK ([Outcome] IN (N'Succeeded', N'RolledBack', N'Failed')),
    [ChecklistRecordEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Deployment_Checklist] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [SmokeChecks]            INT               NULL,
    [Notes]                  NVARCHAR(MAX)     NULL
);
GO
CREATE INDEX [IX_Deployment_Env] ON [platform].[Deployment] ([Environment], [DeployedAt] DESC);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'platform', @level1type = N'TABLE', @level1name = N'Deployment';
GO
