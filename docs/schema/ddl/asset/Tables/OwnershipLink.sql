-- SCHEMA-DESIGN §4.6 (94). Ownership is a relation with role, share and valid time; several links may
-- coexist for one subject. SubjectEntityId is polymorphic (validated by meta.fEntityExists).
CREATE TABLE [asset].[OwnershipLink] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_OwnershipLink_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_OwnershipLink_Registry] REFERENCES [asset].[OwnershipLinkRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_OwnershipLink_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_OwnershipLink_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_OwnershipLink_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_OwnershipLink_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_OwnershipLink_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_OwnershipLink_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [SubjectKind]        NVARCHAR(40)     NOT NULL CONSTRAINT [CK_OwnershipLink_SubjectKind] CHECK ([SubjectKind] IN (N'Node', N'Asset', N'Scheme', N'RouteStep')),
    [SubjectEntityId]    UNIQUEIDENTIFIER NOT NULL,
    [EntityEntityId]     UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_OwnershipLink_Entity] REFERENCES [party].[EntityRegistry] ([EntityId]),
    [OwnershipRole]      NVARCHAR(20)     NOT NULL CONSTRAINT [CK_OwnershipLink_Role] CHECK ([OwnershipRole] IN (N'Owner', N'Operator', N'Maintainer', N'Lessor', N'Lessee')),
    [Share]              DECIMAL(5,2)     NULL     CONSTRAINT [CK_OwnershipLink_Share] CHECK ([Share] IS NULL OR ([Share] > 0 AND [Share] <= 100)),
    [IsResponsibleForReporting] BIT       NOT NULL CONSTRAINT [DF_OwnershipLink_IsResponsibleForReporting] DEFAULT 0,
    CONSTRAINT [PK_OwnershipLink] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_OwnershipLink_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [asset].[OwnershipLink_History]));
GO
CREATE INDEX [IX_OwnershipLink_Entity] ON [asset].[OwnershipLink] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_OwnershipLink_Subject] ON [asset].[OwnershipLink] ([SubjectKind], [SubjectEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'asset', @level1type = N'TABLE', @level1name = N'OwnershipLink';
GO
