-- MIGRATION-FLOC-PLAN §5.2. Class Versioned. One row per distinct (legacy location, legacy
-- equipment) pair: 1,773 of them in the capture of 2026-04-22.
--
-- The legacy settings table is flat, one row per device, and its EQUIPMENT column is a device
-- position demoted to free text (plan §2). This table is where that text becomes a decision: what
-- node it is, what it is called, and where it hangs. The loader then only applies what it finds
-- here, and a value with no row falls through to today's behaviour — placed at the station and
-- flagged — rather than being guessed.
--
-- 1,685 of the 1,773 are answerable from the enterprise functional locations in dbGridInfo without
-- asking anyone (plan §2b), which is why Basis is recorded per row.
CREATE TABLE [migration].[PositionCatalogue] (
    [RowSeq]              BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]               UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_PositionCatalogue_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]            UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_PositionCatalogue_Registry] REFERENCES [migration].[PositionCatalogueRegistry] ([EntityId]),
    [SysStart]            DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]              DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]           UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_PositionCatalogue_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]           DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_PositionCatalogue_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]          DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]           BIT               NOT NULL CONSTRAINT [DF_PositionCatalogue_IsDeleted] DEFAULT 0,
    [DeletedBy]           UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_PositionCatalogue_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]           DATETIMEOFFSET(7) NULL,
    [MigrationRunId]      UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_PositionCatalogue_MigrationRun] REFERENCES [migration].[Run] ([RunId]),

    -- The key, normalised per plan §6 rule 1: uppercased, internal whitespace collapsed. That fold
    -- is not cosmetic; it merges 'UNIT 3 MCC' with 'Unit 3 MCC' and moves the count 1,775 to 1,773.
    [SourceSystem]        NVARCHAR(128)     NOT NULL,
    [LegacyLocation]      NVARCHAR(60)      NOT NULL,
    [LegacyEquipment]     NVARCHAR(100)     NOT NULL,

    -- The answer. NodeTypeCode is deliberately open to the whole vocabulary rather than pinned to
    -- DevicePosition: the owner's ruling of 2026-09-08 is that most of these are positions, but the
    -- outliers are real and are named as whatever they actually are.
    [NodeTypeCode]        NVARCHAR(40)      NULL CONSTRAINT [FK_PositionCatalogue_NodeType] REFERENCES [ref].[LocationNodeType] ([NodeTypeCode]),
    [SubtypeCode]         NVARCHAR(40)      NULL,
    [FlocSegment]         NVARCHAR(60)      NULL,
    [DisplayName]         NVARCHAR(200)     NULL,
    -- The parent is named by catalogue key, not by node id, so a row survives a rebuild of the tree.
    [ParentFlocPath]      NVARCHAR(400)     NULL,
    [Disposition]         NVARCHAR(20)      NOT NULL CONSTRAINT [DF_PositionCatalogue_Disposition] DEFAULT N'Proposed'
                          CONSTRAINT [CK_PositionCatalogue_Disposition] CHECK ([Disposition] IN (N'Proposed', N'Confirmed', N'NotAPosition')),

    [Basis]               NVARCHAR(40)      NULL CONSTRAINT [CK_PositionCatalogue_Basis] CHECK ([Basis] IN (N'EnterpriseFloc', N'PredecessorPosition', N'Owner')),
    [Notes]               NVARCHAR(MAX)     NULL,

    CONSTRAINT [PK_PositionCatalogue] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_PositionCatalogue_RowId] UNIQUE NONCLUSTERED ([RowId]),
    -- A confirmed row must say what it is; a row marked NotAPosition must not.
    CONSTRAINT [CK_PositionCatalogue_Answered] CHECK (
        ([Disposition] = N'Confirmed'    AND [NodeTypeCode] IS NOT NULL AND [DisplayName] IS NOT NULL)
     OR ([Disposition] = N'NotAPosition' AND [NodeTypeCode] IS NULL)
     OR ([Disposition] = N'Proposed'))
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [migration].[PositionCatalogue_History]));
GO
CREATE INDEX [IX_PositionCatalogue_Entity] ON [migration].[PositionCatalogue] ([EntityId]);
GO
-- The natural key. One answer per (source, location, equipment); a re-run finds it rather than
-- asking again, and the client's present-day data reuses every row whose pair is unchanged.
CREATE UNIQUE INDEX [UX_PositionCatalogue_Key] ON [migration].[PositionCatalogue] ([SourceSystem], [LegacyLocation], [LegacyEquipment]) WHERE [IsDeleted] = 0;
GO
-- The loader's read path: resolve every pair for one station in a single seek.
CREATE INDEX [IX_PositionCatalogue_Location] ON [migration].[PositionCatalogue] ([SourceSystem], [LegacyLocation]) INCLUDE ([LegacyEquipment], [NodeTypeCode], [Disposition]) WHERE [IsDeleted] = 0;
GO
CREATE INDEX [IX_PositionCatalogue_Disposition] ON [migration].[PositionCatalogue] ([Disposition]) WHERE [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'migration', @level1type = N'TABLE', @level1name = N'PositionCatalogue';
GO
