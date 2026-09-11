-- SCHEMA-DESIGN §13.1 (171). Class ValidTime. Zero-sequence mutual coupling between two branches.
CREATE TABLE [network].[MutualCoupling] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_MutualCoupling_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_MutualCoupling_Registry] REFERENCES [network].[MutualCouplingRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_MutualCoupling_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_MutualCoupling_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_MutualCoupling_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_MutualCoupling_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_MutualCoupling_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_MutualCoupling_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [CaseEntityId]      UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_MutualCoupling_Case] REFERENCES [network].[CaseRegistry] ([EntityId]),
    [BranchAEntityId]   UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_MutualCoupling_BranchA] REFERENCES [network].[LayerBranchRegistry] ([EntityId]),
    [BranchBEntityId]   UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_MutualCoupling_BranchB] REFERENCES [network].[LayerBranchRegistry] ([EntityId]),
    [R0m]               DECIMAL(18,8)     NULL,
    [X0m]               DECIMAL(18,8)     NULL,
    CONSTRAINT [PK_MutualCoupling] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_MutualCoupling_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_MutualCoupling_NotSelf] CHECK ([BranchAEntityId] <> [BranchBEntityId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [network].[MutualCoupling_History]));
GO
CREATE INDEX [IX_MutualCoupling_Entity] ON [network].[MutualCoupling] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'network', @level1type = N'TABLE', @level1name = N'MutualCoupling';
GO
