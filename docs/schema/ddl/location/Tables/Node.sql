-- SCHEMA-DESIGN §3.2 (81, 83). The functional-location tree: one parent, materialised path, depth,
-- point or linear geography. Path/Depth are maintained by the node procedure (PROCEDURES.md #4).
-- Names the field uses (station number, Cascade FLOC, site alias, panel slot) are location.AlternateKey rows.
CREATE TABLE [location].[Node] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Node_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Node_Registry] REFERENCES [location].[NodeRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Node_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Node_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Node_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Node_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Node_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Node_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [NodeTypeCode]      NVARCHAR(40)      NOT NULL CONSTRAINT [FK_Node_Type] REFERENCES [ref].[LocationNodeType] ([NodeTypeCode]),
    [ParentEntityId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Node_Parent] REFERENCES [location].[NodeRegistry] ([EntityId]),
    [Path]              NVARCHAR(900)     NOT NULL,
    [Depth]             TINYINT           NOT NULL,
    [SiblingOrder]      INT               NOT NULL CONSTRAINT [DF_Node_SiblingOrder] DEFAULT 0,
    [Name]              NVARCHAR(200)     NOT NULL,
    [SubtypeCode]       NVARCHAR(40)      NULL,
    [Location]          GEOGRAPHY         NULL,
    [Extent]            GEOGRAPHY         NULL,
    [RegionSplitOfEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Node_RegionSplitOf] REFERENCES [location].[NodeRegistry] ([EntityId]),
    -- The job this version of the node was created under, so a re-parenting cites its authorising
    -- work request exactly as asset.Placement already does. Added 2026-09-09 for the panel
    -- confirmation passes: a position moved from PNL_UNKNOWN onto its real panel records which pass
    -- found it — the owner's desk review, the drawing review, or field verification — without a
    -- work request per correction (MIGRATION-FLOC-PLAN §16).
    [WorkRequestEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Node_WorkRequest] REFERENCES [work].[WorkRequestRegistry] ([EntityId]),
    [Notes]             NVARCHAR(MAX)     NULL,
    -- #175 (2026-09-17). The owner: "for each of the various levels, ie. Y230, T3 etc. can we have a field
    -- 'code' which contains the code used in the FLOC and then many a Name and/or Description etc. which
    -- allows the user to add more descriptive texts?" So Name stays the descriptive label ("230 kV yard")
    -- and Notes stays the description; Code is the short segment the FLOC is built from (TN, 4403, Y230, T3).
    -- Code may not hold the separator '-' nor any whitespace, or the composed FLOC would be ambiguous;
    -- location.AssertNodeCode is the one place that rule is enforced, and UX_Node_ParentCode below keeps a
    -- code unique among a parent's current children.
    -- FlocCode is the composed path of codes, materialised exactly as Path already is (#172's lesson: a read
    -- must not walk the tree per row). The rule lives in location.fComposeFloc and is three lines:
    --   no Code            -> no FLOC;
    --   parent has no FLOC -> the Code alone, which starts a fresh chain;
    --   otherwise          -> the parent's FlocCode + '-' + Code.
    -- The platform never invents a missing segment. NB Power carries no code, so the FLOC begins at the
    -- division: TN, TN-4403, TN-4403-Y230, TN-4403-Y230-T3. Withdraw Y230's code and T3 reads T3 — a visible
    -- gap — not the guessed TN-4403-T3 and not nothing at all. AddNode, RenameNode and MoveNode maintain
    -- both columns; nothing else may write them.
    [Code]              NVARCHAR(40)      NULL,
    [FlocCode]          NVARCHAR(400)     NULL,
    CONSTRAINT [PK_Node] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Node_RowId] UNIQUE NONCLUSTERED ([RowId]),
    -- The root types. A CHECK cannot read ref.LocationNodeTypeParent, so unlike location.AddNode
    -- these must name them. Region was the only one until 2026-09-09, when Owner was added above
    -- Division; Region stays rootable while the stations still hang from it and comes out of both
    -- lists when they are re-parented onto their division (MIGRATION-FLOC-PLAN §10).
    CONSTRAINT [CK_Node_RootHasNoParent] CHECK ([NodeTypeCode] NOT IN (N'Region', N'Owner') OR [ParentEntityId] IS NULL),
    CONSTRAINT [CK_Node_NonRootHasParent] CHECK ([NodeTypeCode] IN (N'Region', N'Owner') OR [ParentEntityId] IS NOT NULL)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [location].[Node_History]));
GO
CREATE INDEX [IX_Node_Entity] ON [location].[Node] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_Node_Path] ON [location].[Node] ([Path]) WHERE [IsDeleted] = 0 AND [ValidTo] IS NULL;
GO
CREATE INDEX [IX_Node_Parent] ON [location].[Node] ([ParentEntityId]) WHERE [IsDeleted] = 0 AND [ValidTo] IS NULL;
GO
-- #175: one code per parent among the current children. Roots share ParentEntityId NULL and a unique index
-- treats those NULLs as equal, which is the rule wanted there too — two roots cannot both be TN.
CREATE UNIQUE INDEX [UX_Node_ParentCode] ON [location].[Node] ([ParentEntityId], [Code])
    WHERE [Code] IS NOT NULL AND [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
-- #175: so a person can look a FLOC up, or a prefix of one, without a scan of the tree.
CREATE INDEX [IX_Node_FlocCode] ON [location].[Node] ([FlocCode])
    WHERE [FlocCode] IS NOT NULL AND [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'location', @level1type = N'TABLE', @level1name = N'Node';
GO
