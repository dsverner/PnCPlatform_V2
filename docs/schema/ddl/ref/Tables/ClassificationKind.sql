-- SCHEMA-DESIGN §4.7 (95). Kinds of classification; allowed values are an Enumeration definition.
CREATE TABLE [ref].[ClassificationKind] (
    [ClassificationKindCode] NVARCHAR(40) NOT NULL,
    [Name]              NVARCHAR(200)     NOT NULL,
    [Description]       NVARCHAR(MAX)     NULL,
    [AllowedValuesDefinitionRowId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_ClassificationKind_AllowedValues] REFERENCES [config].[DefinitionVersion] ([RowId]),
    -- #171 (2026-09-16): what the kind is recorded against — a JSON array of subject kinds: N'Station' (a location.Node
    -- station), N'Asset' (a primary asset or a bus) and N'Device'. compliance.vFactCatalogue generates one classification
    -- fact per kind per subject it applies to, so a station rating no longer appears as a line fact and the other way about.
    [SubjectKinds]      NVARCHAR(100)     NULL     CONSTRAINT [CK_ClassificationKind_SubjectKinds] CHECK ([SubjectKinds] IS NULL OR ISJSON([SubjectKinds]) = 1),
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ClassificationKind_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ClassificationKind_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_ClassificationKind_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ClassificationKind_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_ClassificationKind] PRIMARY KEY CLUSTERED ([ClassificationKindCode])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [ref].[ClassificationKind_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'ref', @level1type = N'TABLE', @level1name = N'ClassificationKind';
GO
