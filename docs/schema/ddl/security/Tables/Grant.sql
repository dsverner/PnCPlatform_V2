-- SCHEMA-DESIGN §11.4 (155). Bi-temporal: who held what, when, and when we believed it. One scope column set
-- per ScopeKind (CHECK). Assignment = a grant with ScopeKind WorkRequest (decision 141), gated by
-- Program.QualificationRequirement (PROCEDURES.md #18).
CREATE TABLE [security].[Grant] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Grant_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Grant_Registry] REFERENCES [security].[GrantRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Grant_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Grant_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Grant_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Grant_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Grant_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Grant_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [GranteeKind]        NVARCHAR(40)     NOT NULL CONSTRAINT [CK_Grant_GranteeKind] CHECK ([GranteeKind] IN (N'User', N'Group')),
    [GranteeEntityId]    UNIQUEIDENTIFIER NOT NULL,
    [RoleCode]           NVARCHAR(40)     NOT NULL CONSTRAINT [FK_Grant_Role] REFERENCES [security].[Role] ([RoleCode]),
    [ScopeKind]          NVARCHAR(40)     NOT NULL CONSTRAINT [CK_Grant_ScopeKind] CHECK ([ScopeKind] IN (N'NodeSubtree', N'WorkRequest', N'OwnershipRelation', N'Global')),
    [ScopeNodeEntityId]  UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Grant_ScopeNode] REFERENCES [location].[NodeRegistry] ([EntityId]),
    [ScopeAssetClassCode] NVARCHAR(40)    NULL     CONSTRAINT [FK_Grant_ScopeAssetClass] REFERENCES [ref].[AssetClass] ([AssetClassCode]),
    [ScopeDeviceCategory] NVARCHAR(40)    NULL,
    [ScopeWorkRequestEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Grant_ScopeWorkRequest] REFERENCES [work].[WorkRequestRegistry] ([EntityId]),
    [ScopeEntityEntityId] UNIQUEIDENTIFIER NULL    CONSTRAINT [FK_Grant_ScopeEntity] REFERENCES [party].[EntityRegistry] ([EntityId]),
    [ScopeOwnershipRole] NVARCHAR(20)     NULL     CONSTRAINT [CK_Grant_ScopeOwnershipRole] CHECK ([ScopeOwnershipRole] IS NULL OR [ScopeOwnershipRole] IN (N'Owner', N'Operator', N'Maintainer', N'Lessor', N'Lessee')),
    [GrantedByActorId]   UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Grant_GrantedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [RevokedByActorId]   UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Grant_RevokedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [RevocationReason]   NVARCHAR(400)    NULL,
    CONSTRAINT [PK_Grant] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Grant_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_Grant_Scope] CHECK (
        ([ScopeKind] = N'NodeSubtree'       AND [ScopeNodeEntityId] IS NOT NULL AND [ScopeWorkRequestEntityId] IS NULL AND [ScopeEntityEntityId] IS NULL AND [ScopeOwnershipRole] IS NULL)
     OR ([ScopeKind] = N'WorkRequest'       AND [ScopeWorkRequestEntityId] IS NOT NULL AND [ScopeNodeEntityId] IS NULL AND [ScopeAssetClassCode] IS NULL AND [ScopeDeviceCategory] IS NULL AND [ScopeEntityEntityId] IS NULL AND [ScopeOwnershipRole] IS NULL)
     OR ([ScopeKind] = N'OwnershipRelation' AND [ScopeEntityEntityId] IS NOT NULL AND [ScopeOwnershipRole] IS NOT NULL AND [ScopeNodeEntityId] IS NULL AND [ScopeWorkRequestEntityId] IS NULL)
     OR ([ScopeKind] = N'Global'            AND [ScopeNodeEntityId] IS NULL AND [ScopeAssetClassCode] IS NULL AND [ScopeDeviceCategory] IS NULL AND [ScopeWorkRequestEntityId] IS NULL AND [ScopeEntityEntityId] IS NULL AND [ScopeOwnershipRole] IS NULL))
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [security].[Grant_History]));
GO
CREATE INDEX [IX_Grant_Entity] ON [security].[Grant] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_Grant_Grantee] ON [security].[Grant] ([GranteeKind], [GranteeEntityId], [RoleCode]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'security', @level1type = N'TABLE', @level1name = N'Grant';
GO
