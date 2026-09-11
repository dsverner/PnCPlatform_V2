-- SCHEMA-DESIGN §11.1 (152). EmployeeNumber and BadgeNumber are personnel.AlternateKey rows.
CREATE TABLE [personnel].[Person] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_Person_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Person_Registry] REFERENCES [personnel].[PersonRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_Person_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Person_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Person_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_Person_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Person_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Person_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [FirstName]          NVARCHAR(100)    NOT NULL,
    [LastName]           NVARCHAR(100)    NOT NULL,
    [DisplayName]        NVARCHAR(200)    NOT NULL,
    [EmployerEntityEntityId] UNIQUEIDENTIFIER NULL CONSTRAINT [FK_Person_Employer] REFERENCES [party].[EntityRegistry] ([EntityId]),
    [Email]              NVARCHAR(200)    NULL,
    [Phone]              NVARCHAR(50)     NULL,
    [IsSystemAccount]    BIT              NOT NULL CONSTRAINT [DF_Person_IsSystemAccount] DEFAULT 0,
    [Notes]              NVARCHAR(MAX)    NULL,
    CONSTRAINT [PK_Person] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_Person_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [personnel].[Person_History]));
GO
CREATE INDEX [IX_Person_Entity] ON [personnel].[Person] ([EntityId], [ValidFrom]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'ValidTime',
    @level0type = N'SCHEMA', @level0name = N'personnel', @level1type = N'TABLE', @level1name = N'Person';
GO
