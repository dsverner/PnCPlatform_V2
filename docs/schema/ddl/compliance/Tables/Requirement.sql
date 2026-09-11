-- SCHEMA-DESIGN §12.1 (161). Summary is NB Power's paraphrase, never the standard's text. SubjectKinds is a
-- JSON array of the kinds the requirement addresses.
--
-- Title is optional (owner, 2026-09-10). Many requirements have no title: PRC-023 R1 is a number and a
-- body of procedural text, and forcing a title made an author invent one, which is worse than none.
CREATE TABLE [compliance].[Requirement] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Requirement_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Requirement_Registry] REFERENCES [compliance].[RequirementRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Requirement_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Requirement_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Requirement_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Requirement_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Requirement_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Requirement_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [StandardVersionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Requirement_StandardVersion] REFERENCES [compliance].[StandardVersion] ([RowId]),
    [RequirementNumber]  NVARCHAR(40)     NOT NULL,
    [SubRequirement]     NVARCHAR(40)     NULL,
    [Title]              NVARCHAR(200)    NULL,
    [Summary]            NVARCHAR(MAX)    NULL,
    [EvidenceGuidance]   NVARCHAR(MAX)    NULL,
    [SubjectKinds]       NVARCHAR(400)    NULL CONSTRAINT [CK_Requirement_SubjectKindsJson] CHECK ([SubjectKinds] IS NULL OR ISJSON([SubjectKinds]) = 1),
    CONSTRAINT [PK_Requirement] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Requirement_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [compliance].[Requirement_History]));
GO
CREATE INDEX [IX_Requirement_Entity] ON [compliance].[Requirement] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_Requirement_Version] ON [compliance].[Requirement] ([StandardVersionRowId], [RequirementNumber]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'compliance', @level1type = N'TABLE', @level1name = N'Requirement';
GO
