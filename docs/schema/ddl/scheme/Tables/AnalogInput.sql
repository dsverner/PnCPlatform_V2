-- #208 (2026-09-20): a protection scheme's ANALOG INPUT — the relay-side endpoint a source feeds: "Current 1", "Current 2",
-- "Voltage", "Sync voltage". Every source membership (scheme.SchemeMember with role CtSource / VtSource / SyncVtSource)
-- feeds exactly one input; the transformers on the same current input are PARALLELED (the owner, 2026-09-20: line 2103 is
-- fed breaker-and-a-half from E2103 and E2103-TC4, "each of the breakers will have their own set of CTs feeding into the
-- SEL-221F … the two sets of CTs will be paralleled before being brought in to the device"; "they will always be connected
-- in parallel"), so "parallel" is the count of members on the input, never a stored flag. The input is also where the
-- coming cabling work lands (the transformer's secondary at the yard end, the input at the relay end, cables, trenches and
-- terminal blocks between — later entities that reference both ends), so nothing here is undone for it.
-- One row per input per scheme among current rows; BiTemporal like SchemeMember.
CREATE TABLE [scheme].[AnalogInput] (
    [RowSeq]            BIGINT IDENTITY(1,1) NOT NULL,
    [RowId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [DF_AnalogInput_RowId] DEFAULT NEWSEQUENTIALID(),
    [EntityId]          UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AnalogInput_Registry] REFERENCES [scheme].[AnalogInputRegistry] ([EntityId]),
    [ValidFrom]         DATETIMEOFFSET(7) NOT NULL,
    [ValidTo]           DATETIMEOFFSET(7) NULL,
    [ValidFromQuality]  TINYINT           NOT NULL CONSTRAINT [DF_AnalogInput_ValidFromQuality] DEFAULT 0,
    [SysStart]          DATETIME2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    [SysEnd]            DATETIME2(7) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME ([SysStart], [SysEnd]),
    [CreatedBy]         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AnalogInput_CreatedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [CreatedAt]         DATETIMEOFFSET(7) NOT NULL,
    [ModifiedBy]        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_AnalogInput_ModifiedBy] REFERENCES [personnel].[Actor] ([ActorId]),
    [ModifiedAt]        DATETIMEOFFSET(7) NOT NULL,
    [IsDeleted]         BIT               NOT NULL CONSTRAINT [DF_AnalogInput_IsDeleted] DEFAULT 0,
    [DeletedBy]         UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AnalogInput_DeletedBy]  REFERENCES [personnel].[Actor] ([ActorId]),
    [DeletedAt]         DATETIMEOFFSET(7) NULL,
    [MigrationRunId]    UNIQUEIDENTIFIER  NULL     CONSTRAINT [FK_AnalogInput_MigrationRun] REFERENCES [migration].[Run] ([RunId]),
    [SchemeEntityId]     UNIQUEIDENTIFIER NOT NULL CONSTRAINT [FK_AnalogInput_Scheme] REFERENCES [scheme].[SchemeRegistry] ([EntityId]),
    [InputCode]          NVARCHAR(40)     NOT NULL,   -- Current 1, Current 2, Voltage 1, Sync voltage 1
    [InputKind]          NVARCHAR(20)     NOT NULL CONSTRAINT [CK_AnalogInput_Kind] CHECK ([InputKind] IN (N'Current', N'Voltage', N'SyncVoltage')),
    [Notes]              NVARCHAR(MAX)    NULL,
    CONSTRAINT [PK_AnalogInput] PRIMARY KEY CLUSTERED ([RowSeq]),
    CONSTRAINT [UQ_AnalogInput_RowId] UNIQUE NONCLUSTERED ([RowId])
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [scheme].[AnalogInput_History]));
GO
CREATE INDEX [IX_AnalogInput_Entity] ON [scheme].[AnalogInput] ([EntityId], [ValidFrom]);
GO
CREATE UNIQUE INDEX [UX_AnalogInput_SchemeCode] ON [scheme].[AnalogInput] ([SchemeEntityId], [InputCode]) WHERE [ValidTo] IS NULL AND [IsDeleted] = 0;
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'BiTemporal',
    @level0type = N'SCHEMA', @level0name = N'scheme', @level1type = N'TABLE', @level1name = N'AnalogInput';
GO
