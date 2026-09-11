-- SCHEMA-DESIGN §7.1 (116). The non-physical anchor. Scheme type is a Program.SchemeType definition
-- version. Alternate key SchemeNumber in scheme.AlternateKey. Stations spanned are derived, not stored.
CREATE TABLE [scheme].[Scheme] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Scheme_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Scheme_Registry] REFERENCES [scheme].[SchemeRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Scheme_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Scheme_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Scheme_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Scheme_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Scheme_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Scheme_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [SchemeTypeDefinitionVersionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Scheme_Type] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [Name]               NVARCHAR(200)    NOT NULL,
    [SystemDesignation]  NVARCHAR(10)     NULL,
    [Status]             NVARCHAR(20)     NOT NULL CONSTRAINT [CK_Scheme_Status] CHECK ([Status] IN (N'Designed', N'Commissioned', N'InService', N'Retired')),
    [Notes]              NVARCHAR(MAX)    NULL,
    CONSTRAINT [PK_Scheme] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Scheme_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [scheme].[Scheme_History]));
GO
CREATE INDEX [IX_Scheme_Entity] ON [scheme].[Scheme] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'scheme', @level1type = N'TABLE', @level1name = N'Scheme';
GO
