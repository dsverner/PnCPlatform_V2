-- SCHEMA-DESIGN §7.6 (122). Lifted from the predecessor's events.FaultRecord. Precisions are this project's
-- (design gives none): distances DECIMAL(12,3), percent DECIMAL(7,3), currents kA DECIMAL(12,4), impedances
-- ohm DECIMAL(18,6). PatrolRecordEntityId FK → record (step 10).
CREATE TABLE [scheme].[FaultRecord] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_FaultRecord_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_FaultRecord_Registry] REFERENCES [scheme].[FaultRecordRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_FaultRecord_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_FaultRecord_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_FaultRecord_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_FaultRecord_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_FaultRecord_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_FaultRecord_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [OperationEntityId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_FaultRecord_Operation] REFERENCES [scheme].[ProtectionOperationRegistry] ([EntityId]),
    [FaultType]          NVARCHAR(40)     NULL,
    [PhasesInvolved]     NVARCHAR(10)     NULL,
    [FaultedAssetEntityId] UNIQUEIDENTIFIER NULL   CONSTRAINT [FK_FaultRecord_Asset] REFERENCES [asset].[AssetRegistry] ([EntityId]),
    [LocationMethod]     NVARCHAR(40)     NULL,
    [DistanceKm]         DECIMAL(12,3)    NULL,
    [DistancePercent]    DECIMAL(7,3)     NULL,
    [CurrentKaA]         DECIMAL(12,4)    NULL,
    [CurrentKaB]         DECIMAL(12,4)    NULL,
    [CurrentKaC]         DECIMAL(12,4)    NULL,
    [CurrentKaN]         DECIMAL(12,4)    NULL,
    [ResistanceOhm]      DECIMAL(18,6)    NULL,
    [ReactanceOhm]       DECIMAL(18,6)    NULL,
    [IsFieldConfirmed]   BIT              NOT NULL CONSTRAINT [DF_FaultRecord_IsFieldConfirmed] DEFAULT 0,
    [FieldConfirmedAt]   DATETIMEOFFSET(7) NULL,
    [PatrolRecordEntityId] UNIQUEIDENTIFIER NULL   CONSTRAINT [FK_FaultRecord_PatrolRecord] REFERENCES [record].[RecordRegistry] ([EntityId]),
    [OscillographyDocumentEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_FaultRecord_Oscillography] REFERENCES [document].[DocumentRegistry] ([EntityId]),
    [ComputedByActorId]  UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_FaultRecord_ComputedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    CONSTRAINT [PK_FaultRecord] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_FaultRecord_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [scheme].[FaultRecord_History]));
GO
CREATE INDEX [IX_FaultRecord_Entity] ON [scheme].[FaultRecord] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'scheme', @level1type = N'TABLE', @level1name = N'FaultRecord';
GO
