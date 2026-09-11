-- SCHEMA-DESIGN §12.1 (161). Family identifier as the body publishes it. Rows are migration/Administrator content.
CREATE TABLE [compliance].[Standard] (
    [StandardCode]      NVARCHAR(40)      NOT NULL CONSTRAINT [PK_Standard] PRIMARY KEY CLUSTERED,
    [IssuingEntityEntityId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_Standard_IssuingEntity] REFERENCES [party].[EntityRegistry] ([EntityId]),
    [Family]            NVARCHAR(40)      NULL,
    [Subject]           NVARCHAR(200)     NULL,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Standard_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Standard_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_Standard_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Standard_MigrationRun] REFERENCES [migration].[Run] ([RunId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [compliance].[Standard_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'compliance', @level1type = N'TABLE', @level1name = N'Standard';
GO
