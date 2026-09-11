-- SCHEMA-DESIGN §5.2 (100). Per model; linked to its parse transform and its ICD.
-- ParseTransformDefinitionEntityId is nullable so a firmware can be registered before its transform
-- is authored; §5.3's rule (transform must exist) is enforced when a FirmwareHistory row opens
-- (PROCEDURES.md #7). IcdDocumentEntityId → document.DocumentRegistry (step 8).
CREATE TABLE [ref].[FirmwareVersion] (
    [FirmwareVersionId] UNIQUEIDENTIFIER  NOT NULL,
    [ModelId]           UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_FirmwareVersion_Model] REFERENCES [ref].[Model] ([ModelId]),
    [VersionString]     NVARCHAR(100)     NOT NULL,
    [VendorReleaseReference] NVARCHAR(100) NULL,
    [ReleasedAt]        DATETIMEOFFSET(7) NULL,
    [ParseTransformDefinitionEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_FirmwareVersion_ParseTransform] REFERENCES [config].[DefinitionRegistry] ([EntityId]),
    [IcdDocumentEntityId] UNIQUEIDENTIFIER NULL   CONSTRAINT [FK_FirmwareVersion_IcdDocument] REFERENCES [document].[DocumentRegistry] ([EntityId]),
    [VendorLifecycleStatus] NVARCHAR(20)  NULL CONSTRAINT [CK_FirmwareVersion_LifecycleStatus] CHECK ([VendorLifecycleStatus] IS NULL OR [VendorLifecycleStatus] IN (N'Active', N'MatureSupport', N'EndOfSale', N'EndOfSupport', N'Obsolete')),
    [StatusAsOf]        DATETIMEOFFSET(7) NULL,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_FirmwareVersion_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_FirmwareVersion_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_FirmwareVersion_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_FirmwareVersion_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_FirmwareVersion] PRIMARY KEY CLUSTERED ([FirmwareVersionId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [ref].[FirmwareVersion_History]));
GO
CREATE UNIQUE INDEX [UX_FirmwareVersion_Version] ON [ref].[FirmwareVersion] ([ModelId], [VersionString]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'ref', @level1type = N'TABLE', @level1name = N'FirmwareVersion';
GO
