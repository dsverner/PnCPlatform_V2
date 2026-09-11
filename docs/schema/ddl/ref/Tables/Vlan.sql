-- SCHEMA-DESIGN §6.5 (111). A reference list the Administrator maintains; the columns are this project's (design names none).
CREATE TABLE [ref].[Vlan] (
    [VlanId]            INT               NOT NULL,
    [Name]              NVARCHAR(200)     NOT NULL,
    [Description]       NVARCHAR(MAX)     NULL,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Vlan_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_Vlan_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_Vlan_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_Vlan_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_Vlan] PRIMARY KEY CLUSTERED ([VlanId]),
    CONSTRAINT [CK_Vlan_Range] CHECK ([VlanId] BETWEEN 1 AND 4094)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [ref].[Vlan_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'ref', @level1type = N'TABLE', @level1name = N'Vlan';
GO
