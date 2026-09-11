-- SCHEMA-DESIGN §13.1 (171). Class ValidTime. Source equivalent at a layer node: Z1, Z0 as R/X pairs.
CREATE TABLE [network].[SourceEquivalent] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_SourceEquivalent_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SourceEquivalent_Registry] REFERENCES [network].[SourceEquivalentRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_SourceEquivalent_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SourceEquivalent_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SourceEquivalent_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_SourceEquivalent_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_SourceEquivalent_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_SourceEquivalent_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [CaseEntityId]      UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SourceEquivalent_Case] REFERENCES [network].[CaseRegistry] ([EntityId]),
    [LayerNodeEntityId] UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SourceEquivalent_Node] REFERENCES [network].[LayerNodeRegistry] ([EntityId]),
    [Z1R]               DECIMAL(18,8)     NULL,
    [Z1X]               DECIMAL(18,8)     NULL,
    [Z0R]               DECIMAL(18,8)     NULL,
    [Z0X]               DECIMAL(18,8)     NULL,
    CONSTRAINT [PK_SourceEquivalent] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_SourceEquivalent_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [network].[SourceEquivalent_History]));
GO
CREATE INDEX [IX_SourceEquivalent_Entity] ON [network].[SourceEquivalent] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'network', @level1type = N'TABLE', @level1name = N'SourceEquivalent';
GO
