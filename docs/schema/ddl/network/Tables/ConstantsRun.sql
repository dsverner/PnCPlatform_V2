-- SCHEMA-DESIGN §13.2 (172). Class AppendOnly. One run of the line-constants engine (a
-- Program.Formula-family definition version), reproducible from the run and each result's InputHash.
-- Status has no value list in the design: no CHECK.
CREATE TABLE [network].[ConstantsRun] (
    [RunId]                     UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [PK_ConstantsRun] PRIMARY KEY CLUSTERED CONSTRAINT [DF_ConstantsRun_RunId] DEFAULT NEWSEQUENTIALID(),
    [StartedAt]                 DATETIMEOFFSET(7) NOT NULL,
    [ActorId]                   UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_ConstantsRun_Actor] REFERENCES [personnel].[Actor] ([ActorId]),
    [EngineDefinitionVersionRowId] UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_ConstantsRun_Engine] REFERENCES [config].[DefinitionVersion] ([RowId]),
    [Method]                    NVARCHAR(40)      NOT NULL CONSTRAINT [CK_ConstantsRun_Method] CHECK ([Method] IN (N'CarsonSimplified', N'DeriSemlyen')),
    [EarthResistivityOhmM]      DECIMAL(18,4)     NULL,
    [FrequencyHz]               DECIMAL(18,4)     NULL,
    [SectionsCalculated]        INT               NULL,
    [Status]                    NVARCHAR(20)      NULL
);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'network', @level1type = N'TABLE', @level1name = N'ConstantsRun';
GO
