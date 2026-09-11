-- Enumeration definitions the design states literally, created through the definition
-- procedures (a definition is data, decision 74) and approved by a second System actor so the
-- segregation rule holds. Idempotent: a definition key that exists is left alone.
--   StationKind        — SCHEMA-DESIGN §3.9 decision 86 (station subtypes)
--   RacewayKind        — §3.1 (decision 25)
--   DevicePositionKind — §5.7 (101)
-- Each list is then attached to its node type's SubtypeListDefinitionRowId (§3.1).
IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @author   UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';
IF NOT EXISTS (SELECT 1 FROM [personnel].[Actor] WHERE [ActorId] = @approver)
    INSERT [personnel].[Actor] ([ActorId], [ActorKind], [SystemName]) VALUES (@approver, N'System', N'Platform.SeedApprover');

DECLARE @lists TABLE ([DefinitionKey] NVARCHAR(100), [Name] NVARCHAR(200), [NodeTypeCode] NVARCHAR(40));
INSERT @lists VALUES
    (N'StationKind',        N'Station kind (decision 86)',        N'Station'),
    (N'RacewayKind',        N'Raceway kind (decision 25)',        N'Raceway'),
    (N'DevicePositionKind', N'Device position kind (decision 101)', N'DevicePosition');

DECLARE @values TABLE ([DefinitionKey] NVARCHAR(100), [ValueCode] NVARCHAR(60), [Name] NVARCHAR(200), [DisplayOrder] INT);
INSERT @values VALUES
    (N'StationKind', N'Terminal',          N'Terminal',           1),
    (N'StationKind', N'Substation',        N'Substation',         2),
    (N'StationKind', N'GeneratingStation', N'Generating station', 3),
    (N'StationKind', N'RepeaterSite',      N'Repeater site',      4),
    (N'StationKind', N'SwitchingStation',  N'Switching station',  5),
    (N'StationKind', N'ControlCentre',     N'Control centre',     6),
    (N'StationKind', N'FieldSite',         N'Field site',         7),
    (N'RacewayKind', N'Trench',            N'Trench',             1),
    (N'RacewayKind', N'Duct',              N'Duct',               2),
    (N'RacewayKind', N'Tray',              N'Tray',               3),
    (N'DevicePositionKind', N'Relay',                   N'Relay',                    1),
    (N'DevicePositionKind', N'Meter',                   N'Meter',                    2),
    (N'DevicePositionKind', N'Recorder',                N'Recorder',                 3),
    (N'DevicePositionKind', N'Rtu',                     N'RTU',                      4),
    (N'DevicePositionKind', N'EthernetSwitch',          N'Ethernet switch',          5),
    (N'DevicePositionKind', N'TimeClock',               N'Time clock',               6),
    (N'DevicePositionKind', N'Multiplexer',             N'Multiplexer',              7),
    (N'DevicePositionKind', N'Radio',                   N'Radio',                    8),
    (N'DevicePositionKind', N'TeleprotectionInterface', N'Teleprotection interface', 9),
    (N'DevicePositionKind', N'MergingUnit',             N'Merging unit',             10),
    (N'DevicePositionKind', N'SubstationPc',            N'Substation PC',            11),
    (N'DevicePositionKind', N'TerminalServer',          N'Terminal server',          12),
    (N'DevicePositionKind', N'Other',                   N'Other',                    13),
    (N'DevicePositionKind', N'LogicProcessor',          N'Logic processor',          14),   -- owner decision 2026-09-05 (MIGRATION-PLAN Q20)
    (N'DevicePositionKind', N'TapchangerController',    N'Tapchanger controller',    15);   -- owner decision 2026-09-05 (MIGRATION-PLAN Q21), spelling the owner's

DECLARE @key NVARCHAR(100), @name NVARCHAR(200), @nodeType NVARCHAR(40);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT [DefinitionKey], [Name], [NodeTypeCode] FROM @lists;
OPEN c; FETCH NEXT FROM c INTO @key, @name, @nodeType;
WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @defEntity UNIQUEIDENTIFIER, @verRowId UNIQUEIDENTIFIER, @verNo INT, @exists BIT, @missing INT;
    SELECT @defEntity = NULL, @verRowId = NULL, @verNo = NULL;   -- DECLARE inside a loop does not reset
    SET @exists = CASE WHEN EXISTS (SELECT 1 FROM [config].[Definition] WHERE [DefinitionKind] = N'CharacteristicSchema.Enumeration' AND [DefinitionKey] = @key AND [IsDeleted] = 0) THEN 1 ELSE 0 END;
    -- a seeded value absent from the effective list (a later seed revision, e.g. LogicProcessor, Q20) → a new approved version carrying every value
    SET @missing = 0;
    IF @exists = 1
        SELECT @missing = COUNT(*) FROM @values s
        WHERE s.[DefinitionKey] = @key AND NOT EXISTS (
            SELECT 1 FROM [config].[EnumerationValue] ev
            JOIN [config].[DefinitionVersion] dv ON dv.[RowId] = ev.[DefinitionVersionRowId] AND dv.[Status] = N'Effective' AND dv.[EffectiveTo] IS NULL AND dv.[IsDeleted] = 0
            JOIN [config].[Definition] d ON d.[EntityId] = dv.[DefinitionEntityId] AND d.[DefinitionKind] = N'CharacteristicSchema.Enumeration' AND d.[DefinitionKey] = @key AND d.[IsDeleted] = 0
            WHERE ev.[ValueCode] = s.[ValueCode] AND ev.[IsDeleted] = 0);
    IF @exists = 0 OR @missing > 0
    BEGIN
        DECLARE @note NVARCHAR(200) = CASE WHEN @exists = 0 THEN N'seed' ELSE N'seed revision: values added' END;
        IF @exists = 0
            EXEC [config].[AddDefinition] @DefinitionKind = N'CharacteristicSchema.Enumeration', @DefinitionKey = @key, @Name = @name, @ActorId = @author, @EntityId = @defEntity OUTPUT;
        EXEC [config].[AddDefinitionVersion] @DefinitionKey = @key, @DefinitionKind = N'CharacteristicSchema.Enumeration', @ChangeNote = @note, @ActorId = @author, @VersionRowId = @verRowId OUTPUT, @VersionNumber = @verNo OUTPUT;
        DECLARE @vc NVARCHAR(60), @vn NVARCHAR(200), @vo INT;
        DECLARE v CURSOR LOCAL FAST_FORWARD FOR SELECT [ValueCode], [Name], [DisplayOrder] FROM @values WHERE [DefinitionKey] = @key ORDER BY [DisplayOrder];
        OPEN v; FETCH NEXT FROM v INTO @vc, @vn, @vo;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC [config].[EnumerationValue_Add] @DefinitionVersionRowId = @verRowId, @ValueCode = @vc, @Name = @vn, @DisplayOrder = @vo, @ActorId = @author;
            FETCH NEXT FROM v INTO @vc, @vn, @vo;
        END
        CLOSE v; DEALLOCATE v;
        EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @verRowId, @ActorId = @approver;
    END
    -- attach the effective list to the node type (idempotent)
    UPDATE nt SET [SubtypeListDefinitionRowId] = dv.[RowId], [ModifiedBy] = @author, [ModifiedAt] = SYSDATETIMEOFFSET()
    FROM [ref].[LocationNodeType] nt
    JOIN [config].[Definition] d ON d.[DefinitionKind] = N'CharacteristicSchema.Enumeration' AND d.[DefinitionKey] = @key AND d.[IsDeleted] = 0
    JOIN [config].[DefinitionVersion] dv ON dv.[DefinitionEntityId] = d.[EntityId] AND dv.[Status] = N'Effective' AND dv.[EffectiveTo] IS NULL AND dv.[IsDeleted] = 0
    WHERE nt.[NodeTypeCode] = @nodeType AND ISNULL(nt.[SubtypeListDefinitionRowId], '00000000-0000-0000-0000-000000000000') <> dv.[RowId];
    FETCH NEXT FROM c INTO @key, @name, @nodeType;
END
CLOSE c; DEALLOCATE c;
GO
