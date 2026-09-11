-- SCHEMA-DESIGN §7.5 (120): protection condition kinds; extensible.
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [ref].[ConditionKind] AS t
USING (VALUES
    (N'ActiveSettingsGroup', N'Active settings group'),
    (N'TemporarySetting',    N'Temporary setting'),
    (N'FunctionBlocked',     N'Function blocked'),
    (N'TestSwitchOpen',      N'Test switch open'),
    (N'OutOfService',        N'Out of service'),
    (N'ConstructionCutover', N'Construction cutover'),
    (N'Armed',               N'Armed'),
    (N'Disarmed',            N'Disarmed'),
    (N'AbnormalCondition',   N'Abnormal condition'),
    (N'AlarmInhibit',        N'Alarm inhibit')
) AS s ([ConditionKindCode], [Name])
ON t.[ConditionKindCode] = s.[ConditionKindCode]
WHEN MATCHED AND t.[Name] <> s.[Name] THEN UPDATE SET [Name] = s.[Name], [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET THEN INSERT ([ConditionKindCode], [Name], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
    VALUES (s.[ConditionKindCode], s.[Name], @actor, @now, @actor, @now);
GO
