-- #171 (2026-09-16): the ratings of a transmission asset — the current, four-hour, fifteen-minute and practical-limitation
-- amperes a line or transformer is rated for, by season. The values live in another group's ratings database, which the OT
-- network cannot reach today; the owner's ruling, 2026-09-16: "make room for the given values in our application… create the
-- connector later". Until that DMZ connector exists a person enters them by hand and Source names the document they came from;
-- the connector will write its own SourceSystem so hand-entered and delivered values stay distinguishable. PRC-023 R1 reads
-- them: criterion 1 the four-hour rating, criterion 2 the fifteen-minute, criterion 13 the practical limitation.
-- Bi-temporal; one current row per asset, rating kind and season.
CREATE TABLE [asset].[AssetRating] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_AssetRating_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AssetRating_Registry] REFERENCES [asset].[AssetRatingRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_AssetRating_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AssetRating_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AssetRating_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_AssetRating_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AssetRating_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AssetRating_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [AssetEntityId]     UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AssetRating_Asset] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [RatingKind]        NVARCHAR(30)      NOT NULL CONSTRAINT [CK_AssetRating_Kind] CHECK ([RatingKind] IN (N'Continuous', N'FourHour', N'FifteenMinute', N'PracticalLimitation')),
    [Season]            NVARCHAR(10)      NOT NULL CONSTRAINT [CK_AssetRating_Season] CHECK ([Season] IN (N'Summer', N'Winter', N'Spring', N'Fall', N'All')),
    [Amperes]           DECIMAL(12,2)     NOT NULL CONSTRAINT [CK_AssetRating_Amperes] CHECK ([Amperes] > 0),
    [Source]            NVARCHAR(200)     NULL,     -- the document or system the value came from, in the enterer's words
    [SourceSystem]      NVARCHAR(40)      NOT NULL CONSTRAINT [DF_AssetRating_SourceSystem] DEFAULT N'Recorded',   -- 'Recorded' = entered by a person here; the ratings connector will write its own name
    [Notes]             NVARCHAR(MAX)     NULL,
    CONSTRAINT [PK_AssetRating] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_AssetRating_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [asset].[AssetRating_History]));
GO
CREATE INDEX [IX_AssetRating_Entity] ON [asset].[AssetRating] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_AssetRating_AssetKindSeason] ON [asset].[AssetRating] ([AssetEntityId], [RatingKind], [Season]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'asset', @level1type = N'TABLE', @level1name = N'AssetRating';
GO
