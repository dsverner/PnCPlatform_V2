-- MIGRATION-FLOC-PLAN §5.2. Class Versioned. One row per distinct legacy station name.
--
-- The owner's decision of what each legacy LOCATION value is, so that a re-run against the client's
-- present-day database applies the same answer instead of asking again. This is why the plan is a
-- procedure and not a cleanup: a row typed into QA would be lost at cutover, but a catalogue row
-- keyed by the source's own natural key survives.
--
-- It lives in [migration] rather than [config] because its key is a legacy source value, it is
-- meaningless without that source, and it is read only by the loaders. It is Versioned rather than
-- AppendOnly because a row is revised as it moves from proposed to confirmed, and that history is
-- worth keeping.
CREATE TABLE [migration].[StationCatalogue] (
    [RowSeq]              BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]               UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_StationCatalogue_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]            UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_StationCatalogue_Registry] REFERENCES [migration].[StationCatalogueRegistry] ([EntityId]),
    [SysStart]            DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]              DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]           UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_StationCatalogue_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]           DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_StationCatalogue_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]          DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]           BIT               NOT NULL CONSTRAINT [DF_StationCatalogue_IsDeleted] DEFAULT 0,
    [DeletedBy]           UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_StationCatalogue_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]           DATETIMEOFFSET(7) NULL,
    [MigrationRunId]      UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_StationCatalogue_MigrationRun] REFERENCES [migration].[Run] ([RunId]),

    -- The key. SourceSystem is carried explicitly so a second legacy source cannot collide with the
    -- first; LegacyLocation is stored uppercased with internal whitespace collapsed (plan §6 rule 1).
    [SourceSystem]        NVARCHAR(128)     NOT NULL,
    [LegacyLocation]      NVARCHAR(60)      NOT NULL,

    -- The answer.
    [AssetNumber]         CHAR(4)           NULL CONSTRAINT [CK_StationCatalogue_AssetNumber] CHECK ([AssetNumber] LIKE '[0-9][0-9][0-9][0-9]'),
    [DivisionCode]        NVARCHAR(8)       NULL,
    [NodeEntityId]        UNIQUEIDENTIFIER  NULL CONSTRAINT [FK_StationCatalogue_Node] REFERENCES [location].[NodeRegistry] ([EntityId]),
    [Disposition]         NVARCHAR(20)      NOT NULL CONSTRAINT [DF_StationCatalogue_Disposition] DEFAULT N'Proposed'
                          CONSTRAINT [CK_StationCatalogue_Disposition] CHECK ([Disposition] IN (N'Proposed', N'Confirmed', N'NotAStation')),

    -- How the answer was arrived at, so a reviewer can weigh it (plan §2b).
    -- LegacyAssetNumber is the primary basis: SETTINGS.ASSET carries the station's own number and
    -- its dominant value per location matches the enterprise station table 25 times out of 25.
    -- EquipmentOverlap is retained for rows seeded before 2026-09-09, when it was the method.
    [Basis]               NVARCHAR(40)      NULL CONSTRAINT [CK_StationCatalogue_Basis] CHECK ([Basis] IN (N'LegacyAssetNumber', N'EnterpriseName', N'EquipmentOverlap', N'Owner')),
    [Confidence]          DECIMAL(5,2)      NULL CONSTRAINT [CK_StationCatalogue_Confidence] CHECK ([Confidence] BETWEEN 0 AND 100),
    [Notes]               NVARCHAR(MAX)     NULL,

    CONSTRAINT [PK_StationCatalogue] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_StationCatalogue_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [migration].[StationCatalogue_History]));
GO
CREATE INDEX [IX_StationCatalogue_Entity] ON [migration].[StationCatalogue] ([EntityId]);
GO
-- The natural key, enforced on the current row only. This is the whole point of the table: one
-- answer per legacy location per source, and a re-run finds it rather than asking again.
CREATE UNIQUE INDEX [UX_StationCatalogue_Key] ON [migration].[StationCatalogue] ([SourceSystem], [LegacyLocation]) WHERE [IsDeleted] = 0;
GO
CREATE INDEX [IX_StationCatalogue_Disposition] ON [migration].[StationCatalogue] ([Disposition]) WHERE [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Versioned',
    @level0type = N'SCHEMA', @level0name = N'migration', @level1type = N'TABLE', @level1name = N'StationCatalogue';
GO
