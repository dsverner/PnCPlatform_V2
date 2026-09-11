-- SCHEMA-DESIGN §11.5 (156). Authority passes and returns; never reassigned. Positional roles only (procedure rule).
CREATE TABLE [security].[Delegation] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Delegation_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Delegation_Registry] REFERENCES [security].[DelegationRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Delegation_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Delegation_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Delegation_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Delegation_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Delegation_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Delegation_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [FromPersonEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Delegation_FromPerson] REFERENCES [personnel].[PersonRegistry] ([EntityId]),
    [ToPersonEntityId]   UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Delegation_ToPerson] REFERENCES [personnel].[PersonRegistry] ([EntityId]),
    [RoleCode]           NVARCHAR(40)     NOT NULL CONSTRAINT [FK_Delegation_Role] REFERENCES [security].[Role] ([RoleCode]),
    [StartsAt]           DATETIMEOFFSET(7) NOT NULL,
    [EndsAt]             DATETIMEOFFSET(7) NULL,
    [Reason]             NVARCHAR(400)    NULL,
    [GrantedByActorId]   UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Delegation_GrantedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [RevokedByActorId]   UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Delegation_RevokedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    CONSTRAINT [PK_Delegation] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Delegation_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_Delegation_NotSelf] CHECK ([FromPersonEntityId] <> [ToPersonEntityId]),
    CONSTRAINT [CK_Delegation_Period] CHECK ([EndsAt] IS NULL OR [EndsAt] > [StartsAt])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [security].[Delegation_History]));
GO
CREATE INDEX [IX_Delegation_Entity] ON [security].[Delegation] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_Delegation_To] ON [security].[Delegation] ([ToPersonEntityId], [StartsAt]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'security', @level1type = N'TABLE', @level1name = N'Delegation';
GO
