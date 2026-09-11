-- SCHEMA-DESIGN §3.5 (84). Deliberately not a node. The design writes the owner as
-- "OwnerEntityId → asset.EntityRegistry"; organisations live in party.Entity (§4.5), so the FK is there.
CREATE TABLE [location].[CustodyLocation] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_CustodyLocation_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_CustodyLocation_Registry] REFERENCES [location].[CustodyLocationRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_CustodyLocation_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_CustodyLocation_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_CustodyLocation_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_CustodyLocation_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_CustodyLocation_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_CustodyLocation_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [Name]               NVARCHAR(200)    NOT NULL,
    [CustodyKind]        NVARCHAR(20)     NOT NULL CONSTRAINT [CK_CustodyLocation_Kind] CHECK ([CustodyKind] IN (N'Store', N'Vendor', N'ForensicHold', N'Calibration')),
    [OwnerEntityEntityId] UNIQUEIDENTIFIER NULL    CONSTRAINT [FK_CustodyLocation_Owner] REFERENCES [party].[EntityRegistry] ([EntityId]),
    [Address]            NVARCHAR(400)    NULL,
    [Notes]              NVARCHAR(MAX)    NULL,
    CONSTRAINT [PK_CustodyLocation] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_CustodyLocation_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [location].[CustodyLocation_History]));
GO
CREATE INDEX [IX_CustodyLocation_Entity] ON [location].[CustodyLocation] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'location', @level1type = N'TABLE', @level1name = N'CustodyLocation';
GO
