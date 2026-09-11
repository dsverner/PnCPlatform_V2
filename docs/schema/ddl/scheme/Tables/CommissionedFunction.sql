-- SCHEMA-DESIGN §7.3 (117). One row per enabled function at a protection-function position. The designation
-- (87A) is a location.AlternateKey of kind Designation on the node, scoped to the panel.
CREATE TABLE [scheme].[CommissionedFunction] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_CommissionedFunction_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_CommissionedFunction_Registry] REFERENCES [scheme].[CommissionedFunctionRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_CommissionedFunction_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_CommissionedFunction_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_CommissionedFunction_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_CommissionedFunction_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_CommissionedFunction_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_CommissionedFunction_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [ProtectionFunctionNodeEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_CommissionedFunction_Node] REFERENCES [location].[NodeRegistry] ([EntityId]),
    [AnsiCode]           NVARCHAR(10)     NOT NULL CONSTRAINT [FK_CommissionedFunction_Ansi] REFERENCES [ref].[AnsiFunction] ([AnsiCode]),
    [IsPrincipal]        BIT              NOT NULL CONSTRAINT [DF_CommissionedFunction_IsPrincipal] DEFAULT 0,
    [LogicalNodeEntityId] UNIQUEIDENTIFIER NULL    CONSTRAINT [FK_CommissionedFunction_LogicalNode] REFERENCES [connection].[LogicalNodeRegistry] ([EntityId]),
    [EnabledFromConfigurationFileRevisionRowId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_CommissionedFunction_EnabledFrom] REFERENCES [document].[ConfigurationFile] ([RevisionRowId]),
    CONSTRAINT [PK_CommissionedFunction] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_CommissionedFunction_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [scheme].[CommissionedFunction_History]));
GO
CREATE INDEX [IX_CommissionedFunction_Entity] ON [scheme].[CommissionedFunction] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_CommissionedFunction] ON [scheme].[CommissionedFunction] ([ProtectionFunctionNodeEntityId], [AnsiCode]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'scheme', @level1type = N'TABLE', @level1name = N'CommissionedFunction';
GO
