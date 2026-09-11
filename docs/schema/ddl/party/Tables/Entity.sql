-- SCHEMA-DESIGN §4.5 (93). Organisations: the utility and its divisions, neighbouring utilities,
-- carriers, manufacturers, contractors, regulators, standards bodies.
CREATE TABLE [party].[Entity] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Entity_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Entity_Registry] REFERENCES [party].[EntityRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Entity_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Entity_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Entity_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Entity_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Entity_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Entity_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [Name]               NVARCHAR(200)    NOT NULL,
    [ShortName]          NVARCHAR(40)     NULL,
    [EntityKind]         NVARCHAR(20)     NOT NULL CONSTRAINT [CK_Entity_Kind] CHECK ([EntityKind] IN (N'Utility', N'Division', N'Carrier', N'Manufacturer', N'Contractor', N'Regulator', N'StandardsBody', N'Other')),
    [ParentEntityEntityId] UNIQUEIDENTIFIER NULL  CONSTRAINT [FK_Entity_Parent] REFERENCES [party].[EntityRegistry] ([EntityId]),
    [IsOwnerOrganisation] BIT             NOT NULL CONSTRAINT [DF_Entity_IsOwnerOrganisation] DEFAULT 0,
    [ExternalIdentifier] NVARCHAR(100)    NULL,
    CONSTRAINT [PK_Entity] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Entity_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [party].[Entity_History]));
GO
CREATE INDEX [IX_Entity_Entity] ON [party].[Entity] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'party', @level1type = N'TABLE', @level1name = N'Entity';
GO
