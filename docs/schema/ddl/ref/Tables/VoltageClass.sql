-- SCHEMA-DESIGN §4.9 (97). Seeded from NB Power's actual set at migration; none here.
CREATE TABLE [ref].[VoltageClass] (
    [VoltageClassCode]  NVARCHAR(20)      NOT NULL,
    [NominalKv]         DECIMAL(10,3)     NOT NULL,
    [IsTransmission]    BIT               NOT NULL CONSTRAINT [DF_VoltageClass_IsTransmission] DEFAULT 0,
    [DisplayOrder]      INT               NOT NULL CONSTRAINT [DF_VoltageClass_DisplayOrder] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_VoltageClass_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_VoltageClass_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsActive]          BIT               NOT NULL CONSTRAINT [DF_VoltageClass_IsActive] DEFAULT 1,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_VoltageClass_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    CONSTRAINT [PK_VoltageClass] PRIMARY KEY CLUSTERED ([VoltageClassCode])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [ref].[VoltageClass_History]));
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'Reference',
    @level0type = N'SCHEMA', @level0name = N'ref', @level1type = N'TABLE', @level1name = N'VoltageClass';
GO
