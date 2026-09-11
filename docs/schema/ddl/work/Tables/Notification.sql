-- SCHEMA-DESIGN §9.6 (140). Class ValidTime. The notification type is a Program.NotificationType definition.
-- SubjectKind has no CHECK: the design lists no subject kinds for notifications (STEPS.md).
CREATE TABLE [work].[Notification] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Notification_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Notification_Registry] REFERENCES [work].[NotificationRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Notification_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Notification_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Notification_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Notification_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Notification_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Notification_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [NotificationTypeDefinitionVersionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Notification_Type] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [RecipientActorId]   UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Notification_RecipientActor] REFERENCES [personnel].[Actor] ([ActorId]),
    [RecipientRoleCode]  NVARCHAR(40)     NULL     CONSTRAINT [FK_Notification_RecipientRole] REFERENCES [security].[Role] ([RoleCode]),
    [SubjectKind]        NVARCHAR(40)     NOT NULL CONSTRAINT [FK_Notification_SubjectKind] REFERENCES [ref].[SubjectKind] ([SubjectKindCode]),
    [SubjectEntityId]    UNIQUEIDENTIFIER NULL,
    [Status]             NVARCHAR(20)     NOT NULL CONSTRAINT [CK_Notification_Status] CHECK ([Status] IN (N'Open', N'Acknowledged', N'Resolved', N'Escalated', N'Expired')),
    [CurrentEscalationStep] INT           NOT NULL CONSTRAINT [DF_Notification_EscalationStep] DEFAULT 0,
    [Summary]            NVARCHAR(400)    NOT NULL,
    [Detail]             NVARCHAR(MAX)    NULL,
    [ResolvedAt]         DATETIMEOFFSET(7) NULL,
    [ResolvedByActorId]  UNIQUEIDENTIFIER NULL     CONSTRAINT [FK_Notification_ResolvedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ResolutionRecordEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Notification_ResolutionRecord] REFERENCES [record].[RecordRegistry] ([EntityId]),
    CONSTRAINT [PK_Notification] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Notification_RowId] UNIQUE NONCLUSTERED ([RowId]),
    CONSTRAINT [CK_Notification_Recipient] CHECK ([RecipientActorId] IS NOT NULL OR [RecipientRoleCode] IS NOT NULL)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [work].[Notification_History]));
GO
CREATE INDEX [IX_Notification_Entity] ON [work].[Notification] ([EntityId], [ValidFrom]);
GO
CREATE INDEX [IX_Notification_Recipient] ON [work].[Notification] ([RecipientActorId], [Status]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'work', @level1type = N'TABLE', @level1name = N'Notification';
GO
