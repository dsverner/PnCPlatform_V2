-- SCHEMA-DESIGN §10.7 (149). Members of a commissioning-package record; acceptance cascades (PROCEDURES.md #20).
CREATE TABLE [record].[CommissioningPackageItem] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_CommissioningPackageItem_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_CommissioningPackageItem_Registry] REFERENCES [record].[CommissioningPackageItemRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_CommissioningPackageItem_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_CommissioningPackageItem_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_CommissioningPackageItem_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_CommissioningPackageItem_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_CommissioningPackageItem_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_CommissioningPackageItem_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [PackageEntityId]    UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_CommissioningPackageItem_Package] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [MemberRecordEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_CommissioningPackageItem_Member] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [Sequence]           INT              NOT NULL CONSTRAINT [DF_CommissioningPackageItem_Sequence] DEFAULT 0,
    [IsRequired]         BIT              NOT NULL CONSTRAINT [DF_CommissioningPackageItem_IsRequired] DEFAULT 1,
    CONSTRAINT [PK_CommissioningPackageItem] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_CommissioningPackageItem_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_CommissioningPackageItem_NotSelf] CHECK ([PackageEntityId] <> [MemberRecordEntityId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [record].[CommissioningPackageItem_History]));
GO
CREATE INDEX [IX_CommissioningPackageItem_Entity] ON [record].[CommissioningPackageItem] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_CommissioningPackageItem_Package] ON [record].[CommissioningPackageItem] ([PackageEntityId], [Sequence]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'record', @level1type = N'TABLE', @level1name = N'CommissioningPackageItem';
GO
