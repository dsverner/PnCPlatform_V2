-- SCHEMA-DESIGN §6.2 (108, 109). One record for every joining of two things, whatever carries it.
-- Endpoint kinds per §6.2. Endpoint/carrier rules per realisation are PROCEDURES.md #9.
-- VerifiedByRecordEntityId FK → record.RecordRegistry (step 10); WorkRequestEntityId FK → work (step 9).
CREATE TABLE [connection].[Connection] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Connection_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Connection_Registry] REFERENCES [connection].[ConnectionRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Connection_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Connection_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Connection_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Connection_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Connection_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Connection_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [FromKind]           NVARCHAR(40)     NOT NULL CONSTRAINT [CK_Connection_FromKind] CHECK ([FromKind] IN (N'Stud', N'Port', N'ProtectionFunction', N'Dataset', N'NetworkPort')),
    [FromEntityId]       UNIQUEIDENTIFIER NOT NULL,
    [ToKind]             NVARCHAR(40)     NOT NULL CONSTRAINT [CK_Connection_ToKind] CHECK ([ToKind] IN (N'Stud', N'Port', N'ProtectionFunction', N'Dataset', N'NetworkPort')),
    [ToEntityId]         UNIQUEIDENTIFIER NOT NULL,
    [RealisationCode]    NVARCHAR(40)     NOT NULL CONSTRAINT [FK_Connection_Realisation] REFERENCES [ref].[ConnectionRealisation] ([RealisationCode]),
    [CarrierAssetEntityId] UNIQUEIDENTIFIER NULL   CONSTRAINT [FK_Connection_Carrier] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [DesignStatus]       NVARCHAR(20)     NOT NULL CONSTRAINT [CK_Connection_DesignStatus] CHECK ([DesignStatus] IN (N'Designed', N'Installed', N'Verified')),
    [VerifiedByRecordEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Connection_VerifiedByRecord] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [WorkRequestEntityId] UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Connection_WorkRequest] REFERENCES [work].[WorkRequestRegistry] ([EntityId]),
    [DrawingKey]         NVARCHAR(100)    NULL,
    [Notes]              NVARCHAR(MAX)    NULL,
    CONSTRAINT [PK_Connection] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Connection_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_Connection_NotSelf] CHECK (NOT ([FromKind] = [ToKind] AND [FromEntityId] = [ToEntityId]))
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [connection].[Connection_History]));
GO
CREATE INDEX [IX_Connection_Entity] ON [connection].[Connection] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_Connection_From] ON [connection].[Connection] ([FromKind], [FromEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
CREATE INDEX [IX_Connection_To] ON [connection].[Connection] ([ToKind], [ToEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'connection', @level1type = N'TABLE', @level1name = N'Connection';
GO
