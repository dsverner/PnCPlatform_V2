-- SCHEMA-DESIGN §2.2 (74, 78). Class Versioned. Exactly one version of a definition may be
-- Effective at an instant for a given applies-to match (enforced by config.ApproveDefinitionVersion).
-- TestEvidenceRecordId → record.RecordRegistry: FK added with step 10.
CREATE TABLE [config].[DefinitionVersion] (
    [RowSeq]                BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]                 UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_DefinitionVersion_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]              UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_DefinitionVersion_Registry] REFERENCES [config].[DefinitionVersionRegistry] ([EntityId]),
    [SysStart]              DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]                DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_DefinitionVersion_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]             DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]            UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_DefinitionVersion_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]            DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]             BIT               NOT NULL CONSTRAINT [DF_DefinitionVersion_IsDeleted] DEFAULT 0,
    [DeletedBy]             UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_DefinitionVersion_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]             DATETIMEOFFSET(7) NULL,
    [MigrationRunId]        UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_DefinitionVersion_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [DefinitionEntityId]    UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_DefinitionVersion_Definition] REFERENCES [config].[DefinitionRegistry] ([EntityId]),
    [VersionNumber]         INT               NOT NULL,
    [Status]                NVARCHAR(20)      NOT NULL CONSTRAINT [CK_DefinitionVersion_Status] CHECK ([Status] IN (N'Draft', N'Approved', N'Effective', N'Retired')),
    [EffectiveFrom]         DATETIMEOFFSET(7) NULL,
    [EffectiveTo]           DATETIMEOFFSET(7) NULL,
    [ApprovedBy]            UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_DefinitionVersion_ApprovedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ApprovedAt]            DATETIMEOFFSET(7) NULL,
    [ChangeNote]            NVARCHAR(MAX)     NULL,
    [TestEvidenceRecordId]  UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_DefinitionVersion_TestEvidenceRecord] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [PayloadText]           NVARCHAR(MAX)     NULL,     -- programs only (decision 78)
    [PayloadHash]           BINARY(32)        NULL,
    CONSTRAINT [PK_DefinitionVersion] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_DefinitionVersion_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_DefinitionVersion_Period] CHECK ([EffectiveTo] IS NULL OR [EffectiveFrom] IS NULL OR [EffectiveTo] > [EffectiveFrom])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [config].[DefinitionVersion_History]));
GO
CREATE INDEX [IX_DefinitionVersion_Entity] ON [config].[DefinitionVersion] ([EntityId]);
GO
CREATE UNIQUE INDEX [UX_DefinitionVersion_Number] ON [config].[DefinitionVersion] ([DefinitionEntityId], [VersionNumber]) WHERE [IsDeleted] = 0;
GO
CREATE INDEX [IX_DefinitionVersion_Effective] ON [config].[DefinitionVersion] ([DefinitionEntityId], [Status], [EffectiveFrom], [EffectiveTo]) WHERE [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'config', @level1type = N'TABLE', @level1name = N'DefinitionVersion';
GO
