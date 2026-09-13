-- SCHEMA-DESIGN §3.6 (85). The function a position carries over time, separate from its identity.
-- SchemeEntityId → scheme.SchemeRegistry (step 7).
CREATE TABLE [location].[NodeFunction] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_NodeFunction_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_NodeFunction_Registry] REFERENCES [location].[NodeFunctionRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_NodeFunction_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_NodeFunction_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_NodeFunction_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_NodeFunction_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_NodeFunction_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_NodeFunction_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [NodeEntityId]       UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_NodeFunction_Node] REFERENCES [location].[NodeRegistry] ([EntityId]),
    [FunctionLabel]      NVARCHAR(200)    NOT NULL,
    [CascadeName]        NVARCHAR(200)    NULL,
    [SchemeEntityId]     UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_NodeFunction_Scheme] REFERENCES [scheme].[SchemeRegistry] ([EntityId]),
    CONSTRAINT [PK_NodeFunction] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_NodeFunction_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [location].[NodeFunction_History]));
GO
CREATE INDEX [IX_NodeFunction_Entity] ON [location].[NodeFunction] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'location', @level1type = N'TABLE', @level1name = N'NodeFunction';
GO
-- W7: the FLOC view lists a position's function labels (vFloc); the migrated positions made the lookup a scan
CREATE INDEX [IX_NodeFunction_Node] ON [location].[NodeFunction] ([NodeEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
