-- SCHEMA-DESIGN §2.1 (74). The three meta-kinds and their sub-kinds; seeded from the design's
-- list, extensible by the Administrator.
CREATE TABLE [ref].[DefinitionKind] (
    [DefinitionKind]    NVARCHAR(40)      NOT NULL CONSTRAINT [PK_DefinitionKind] PRIMARY KEY CLUSTERED,
    [MetaKind]          NVARCHAR(20)      NOT NULL CONSTRAINT [CK_DefinitionKind_MetaKind] CHECK ([MetaKind] IN (N'CharacteristicSchema', N'Transform', N'Program')),
    [Name]              NVARCHAR(200)     NOT NULL,
    [Description]       NVARCHAR(MAX)     NULL,
    [HasPayloadText]    BIT               NOT NULL,   -- decision 78: programs yes; schemas and transforms no
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_DefinitionKind_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_DefinitionKind_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_DefinitionKind_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL,
    CONSTRAINT [CK_DefinitionKind_Payload] CHECK (
        ([MetaKind] = N'Program' AND [HasPayloadText] = 1)
     OR ([MetaKind] <> N'Program' AND [HasPayloadText] = 0))
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [ref].[DefinitionKind_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'ref', @level1type = N'TABLE', @level1name = N'DefinitionKind';
GO
