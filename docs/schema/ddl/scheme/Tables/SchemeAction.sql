-- SCHEMA-DESIGN §7.4 (119). Ordered actions of a RAS / SPS scheme. MW / Mvar measures DECIMAL(18,4) (CONVENTIONS).
CREATE TABLE [scheme].[SchemeAction] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_SchemeAction_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SchemeAction_Registry] REFERENCES [scheme].[SchemeActionRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_SchemeAction_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SchemeAction_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SchemeAction_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_SchemeAction_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_SchemeAction_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_SchemeAction_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [SchemeEntityId]     UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_SchemeAction_Scheme] REFERENCES [scheme].[SchemeRegistry] ([EntityId]),
    [Sequence]           INT              NOT NULL,
    [ActionKind]         NVARCHAR(20)     NOT NULL CONSTRAINT [CK_SchemeAction_Kind] CHECK ([ActionKind] IN (N'TripBreaker', N'ShedLoad', N'RejectGeneration', N'SwitchReactor', N'Alarm', N'Transfer')),
    [TargetAssetEntityId] UNIQUEIDENTIFIER NULL    CONSTRAINT [FK_SchemeAction_Asset] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [TargetNodeEntityId] UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_SchemeAction_Node] REFERENCES [location].[NodeRegistry] ([EntityId]),
    [LoadMw]             DECIMAL(18,4)    NULL,
    [GenerationMw]       DECIMAL(18,4)    NULL,
    [Mvar]               DECIMAL(18,4)    NULL,
    [MaxExecutionMs]     INT              NULL,
    [Description]        NVARCHAR(MAX)    NULL,
    CONSTRAINT [PK_SchemeAction] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_SchemeAction_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [scheme].[SchemeAction_History]));
GO
CREATE INDEX [IX_SchemeAction_Entity] ON [scheme].[SchemeAction] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_SchemeAction_Sequence] ON [scheme].[SchemeAction] ([SchemeEntityId], [Sequence]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'scheme', @level1type = N'TABLE', @level1name = N'SchemeAction';
GO
