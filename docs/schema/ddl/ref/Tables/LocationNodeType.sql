-- SCHEMA-DESIGN §3.1 (80). Node types are data: point or linear, Cascade-supplied or platform-authored,
-- optional subtype list (an Enumeration definition version). Seeded from the design's list.
CREATE TABLE [ref].[LocationNodeType] (
    [NodeTypeCode]      NVARCHAR(40)      NOT NULL,
    [Name]              NVARCHAR(200)     NOT NULL,
    [Description]       NVARCHAR(MAX)     NULL,
    [Geometry]          NVARCHAR(20)      NOT NULL CONSTRAINT [CK_LocationNodeType_Geometry] CHECK ([Geometry] IN (N'Point', N'Linear')),
    [IsCascadeSupplied] BIT               NOT NULL CONSTRAINT [DF_LocationNodeType_IsCascadeSupplied] DEFAULT 0,
    -- #180 (2026-09-17): does a node of this type add a segment to the FLOC? The owner: "the device FLOC should stop
    -- at TN-4134-BDG1-PNL12-21A and that FLOC position should be assigned to the device (SEL-411L etc.)" — a relay's
    -- tag ends at the position it stands in. The elements inside it (21, 51N ...) are recorded as nodes, because a
    -- scheme's members are protection functions, but they are NOT part of anyone's tag: his client shortened the tag
    -- to 21A deliberately so schematic drawings would not get busy. NULL or 1 means the type carries a segment, which
    -- is every type's answer but the ones named in Seed_ref_LocationNodeType. Nullable because the column is added to
    -- a table that already has history rows.
    [CarriesFlocSegment] BIT          NULL,
    [SubtypeListDefinitionRowId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_LocationNodeType_SubtypeList] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LocationNodeType_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LocationNodeType_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_LocationNodeType_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_LocationNodeType_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_LocationNodeType] PRIMARY KEY CLUSTERED ([NodeTypeCode])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [ref].[LocationNodeType_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'ref', @level1type = N'TABLE', @level1name = N'LocationNodeType';
GO
