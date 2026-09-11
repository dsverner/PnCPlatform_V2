-- SCHEMA-DESIGN §11.8 (159), decision 56. A compliance subject in its own right. Scope per the design's four
-- kinds; DeviceCategory is a code, so ScopeCode carries it (ScopeEntityId null) — STEPS.md.
CREATE TABLE [personnel].[Authorisation] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Authorisation_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Authorisation_Registry] REFERENCES [personnel].[AuthorisationRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Authorisation_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Authorisation_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Authorisation_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Authorisation_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Authorisation_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Authorisation_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [PersonEntityId]     UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Authorisation_Person] REFERENCES [personnel].[PersonRegistry] ([EntityId]),
    [RightKindCode]      NVARCHAR(40)     NOT NULL CONSTRAINT [FK_Authorisation_RightKind] REFERENCES [ref].[AuthorisationRightKind] ([RightKindCode]),
    [ScopeKind]          NVARCHAR(40)     NOT NULL CONSTRAINT [CK_Authorisation_ScopeKind] CHECK ([ScopeKind] IN (N'NodeSubtree', N'DeviceCategory', N'SecurityPerimeter', N'DocumentClass')),
    [ScopeEntityId]      UNIQUEIDENTIFIER NULL,
    [ScopeCode]          NVARCHAR(40)     NULL,
    [AuthorisationBasis] NVARCHAR(200)    NULL,
    [RiskAssessmentAt]   DATETIMEOFFSET(7) NULL,
    [TrainingCurrentAsOf] DATETIMEOFFSET(7) NULL,
    [GrantedByActorId]   UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Authorisation_GrantedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [RevokedByActorId]   UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Authorisation_RevokedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [RevokedAt]          DATETIMEOFFSET(7) NULL,
    [RevocationReason]   NVARCHAR(400)    NULL,
    CONSTRAINT [PK_Authorisation] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Authorisation_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_Authorisation_Scope] CHECK (
        ([ScopeKind] = N'DeviceCategory' AND [ScopeCode] IS NOT NULL AND [ScopeEntityId] IS NULL)
     OR ([ScopeKind] <> N'DeviceCategory' AND [ScopeEntityId] IS NOT NULL AND [ScopeCode] IS NULL))
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [personnel].[Authorisation_History]));
GO
CREATE INDEX [IX_Authorisation_Entity] ON [personnel].[Authorisation] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_Authorisation_Person] ON [personnel].[Authorisation] ([PersonEntityId], [RightKindCode]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'personnel', @level1type = N'TABLE', @level1name = N'Authorisation';
GO
