-- SCHEMA-DESIGN §7.2 (116). Members are functions and connections, not devices. Polymorphic member
-- validation is meta.fEntityExists in the generated procedures; vSchemeExpanded is PROCEDURES.md #12.
CREATE TABLE [scheme].[SchemeMember] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_SchemeMember_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SchemeMember_Registry] REFERENCES [scheme].[SchemeMemberRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_SchemeMember_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SchemeMember_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_SchemeMember_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_SchemeMember_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_SchemeMember_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_SchemeMember_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [SchemeEntityId]     UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_SchemeMember_Scheme] REFERENCES [scheme].[SchemeRegistry] ([EntityId]),
    [MemberKind]         NVARCHAR(40)     NOT NULL CONSTRAINT [CK_SchemeMember_Kind] CHECK ([MemberKind] IN (N'ProtectionFunction', N'Asset', N'Connection', N'Channel')),
    [MemberEntityId]     UNIQUEIDENTIFIER NOT NULL,
    [MemberRoleCode]     NVARCHAR(40)     NOT NULL CONSTRAINT [FK_SchemeMember_Role] REFERENCES [ref].[SchemeMemberRole] ([MemberRoleCode]),
    [IsInService]        BIT              NOT NULL CONSTRAINT [DF_SchemeMember_IsInService] DEFAULT 1,
    [Notes]              NVARCHAR(MAX)    NULL,
    CONSTRAINT [PK_SchemeMember] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_SchemeMember_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [scheme].[SchemeMember_History]));
GO
CREATE INDEX [IX_SchemeMember_Entity] ON [scheme].[SchemeMember] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_SchemeMember_Scheme] ON [scheme].[SchemeMember] ([SchemeEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
CREATE INDEX [IX_SchemeMember_Member] ON [scheme].[SchemeMember] ([MemberKind], [MemberEntityId]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'scheme', @level1type = N'TABLE', @level1name = N'SchemeMember';
GO
