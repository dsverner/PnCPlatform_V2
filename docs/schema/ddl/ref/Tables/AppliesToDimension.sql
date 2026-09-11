-- SCHEMA-DESIGN §2.3 (75). The dimensions a definition version's applies-to rows may select on.
CREATE TABLE [ref].[AppliesToDimension] (
    [DimensionCode]     NVARCHAR(40)      NOT NULL CONSTRAINT [PK_AppliesToDimension] PRIMARY KEY CLUSTERED,
    [Name]              NVARCHAR(200)     NOT NULL,
    [ValueKind]         NVARCHAR(20)      NOT NULL CONSTRAINT [CK_AppliesToDimension_ValueKind] CHECK ([ValueKind] IN (N'Entity', N'Code')),
    [SubjectKindCode]   NVARCHAR(40)      NULL CONSTRAINT [FK_AppliesToDimension_SubjectKind] REFERENCES [ref].[SubjectKind] ([SubjectKindCode]),  -- for Entity-valued dimensions
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AppliesToDimension_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AppliesToDimension_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_AppliesToDimension_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [ref].[AppliesToDimension_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'ref', @level1type = N'TABLE', @level1name = N'AppliesToDimension';
GO
