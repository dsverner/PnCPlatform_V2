-- SCHEMA-DESIGN §9.6 (140). ScopeFilter is a catalogue predicate (JSON placeholder grammar, as the rule payloads).
CREATE TABLE [work].[Subscription] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Subscription_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Subscription_Registry] REFERENCES [work].[SubscriptionRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Subscription_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Subscription_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Subscription_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Subscription_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Subscription_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Subscription_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [PersonEntityId]     UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Subscription_Person] REFERENCES [personnel].[PersonRegistry] ([EntityId]),
    [NotificationTypeDefinitionEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Subscription_Type] REFERENCES [config].[DefinitionRegistry] ([EntityId]),
    [ScopeFilter]        NVARCHAR(MAX)    NULL CONSTRAINT [CK_Subscription_ScopeFilterJson] CHECK ([ScopeFilter] IS NULL OR ISJSON([ScopeFilter]) = 1),
    CONSTRAINT [PK_Subscription] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Subscription_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [work].[Subscription_History]));
GO
CREATE INDEX [IX_Subscription_Entity] ON [work].[Subscription] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'work', @level1type = N'TABLE', @level1name = N'Subscription';
GO
