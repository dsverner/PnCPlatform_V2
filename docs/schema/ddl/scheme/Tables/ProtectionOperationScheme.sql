-- SCHEMA-DESIGN §7.6 (122). Which schemes an operation involved, and in what role. Class ValidTime (design gives none).
CREATE TABLE [scheme].[ProtectionOperationScheme] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_ProtectionOperationScheme_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProtectionOperationScheme_Registry] REFERENCES [scheme].[ProtectionOperationSchemeRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_ProtectionOperationScheme_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProtectionOperationScheme_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ProtectionOperationScheme_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_ProtectionOperationScheme_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ProtectionOperationScheme_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_ProtectionOperationScheme_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [OperationEntityId]  UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_ProtectionOperationScheme_Operation] REFERENCES [scheme].[ProtectionOperationRegistry] ([EntityId]),
    [SchemeEntityId]     UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_ProtectionOperationScheme_Scheme] REFERENCES [scheme].[SchemeRegistry] ([EntityId]),
    [Role]               NVARCHAR(20)     NOT NULL CONSTRAINT [CK_ProtectionOperationScheme_Role] CHECK ([Role] IN (N'Operated', N'ShouldHaveOperated', N'Blocked')),
    [SchemeMemberRowId]  UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_ProtectionOperationScheme_Member] REFERENCES [scheme].[SchemeMember] ([RowId]),
    CONSTRAINT [PK_ProtectionOperationScheme] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_ProtectionOperationScheme_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [scheme].[ProtectionOperationScheme_History]));
GO
CREATE INDEX [IX_ProtectionOperationScheme_Entity] ON [scheme].[ProtectionOperationScheme] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'scheme', @level1type = N'TABLE', @level1name = N'ProtectionOperationScheme';
GO
