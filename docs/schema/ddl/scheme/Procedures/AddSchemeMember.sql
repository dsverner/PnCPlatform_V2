-- SCHEMA-DESIGN §7.2 (decision 116); PROCEDURES.md #12.
-- Adds a member to a scheme after the polymorphic check the design puts in the procedure:
-- ProtectionFunction → a current node of that type; Asset and Channel → a current asset (a
-- channel is an asset, §7.2); Connection → a current connection. Members are functions,
-- assets and connections, never devices, so a relay swap leaves the scheme intact.
-- #208 (2026-09-20): a SOURCE member (role CtSource / VtSource / SyncVtSource) feeds one of the scheme's analog inputs.
-- Given @AnalogInputEntityId, it must be a current input of this scheme (50272). Given none, the input is found or made:
-- the scheme's lowest-numbered "Current n" for a CT source, "Voltage n" for a VT source, "Sync voltage n" for a sync-VT source —
-- made when the scheme has none — so every caller that never heard of inputs still lands its source on one. Two or more
-- sources on the same current input are paralleled (the owner: "they will always be connected in parallel").
CREATE PROCEDURE [scheme].[AddSchemeMember]
    @SchemeEntityId UNIQUEIDENTIFIER,
    @MemberKind NVARCHAR(40),
    @MemberEntityId UNIQUEIDENTIFIER,
    @MemberRoleCode NVARCHAR(40),
    @IsInService BIT = 1,
    @Notes NVARCHAR(MAX) = NULL,
    @AnalogInputEntityId UNIQUEIDENTIFIER = NULL,
    @WindingEntityId UNIQUEIDENTIFIER = NULL,   -- #212: the source transformer's secondary winding this membership uses
    @ValidFrom DATETIMEOFFSET(7) = NULL,
    @ValidFromQuality TINYINT = 0,
    @ActorId UNIQUEIDENTIFIER = NULL,
    @MigrationRunId UNIQUEIDENTIFIER = NULL,
    @EntityId UNIQUEIDENTIFIER = NULL OUTPUT,
    @RowId UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM [scheme].[vScheme] WHERE [EntityId] = @SchemeEntityId)
        THROW 50270, N'scheme.AddSchemeMember: the scheme is not a current scheme.', 1;
    DECLARE @ok BIT = CASE @MemberKind
        WHEN N'ProtectionFunction' THEN CASE WHEN EXISTS (SELECT 1 FROM [location].[vNode] WHERE [EntityId] = @MemberEntityId AND [NodeTypeCode] = N'ProtectionFunction') THEN 1 ELSE 0 END
        WHEN N'Asset'              THEN CASE WHEN EXISTS (SELECT 1 FROM [asset].[vAsset] WHERE [EntityId] = @MemberEntityId) THEN 1 ELSE 0 END
        WHEN N'Channel'            THEN CASE WHEN EXISTS (SELECT 1 FROM [asset].[vAsset] WHERE [EntityId] = @MemberEntityId) THEN 1 ELSE 0 END
        WHEN N'Connection'         THEN CASE WHEN EXISTS (SELECT 1 FROM [connection].[vConnection] WHERE [EntityId] = @MemberEntityId) THEN 1 ELSE 0 END
        ELSE 0 END;
    IF @ok = 0
    BEGIN
        DECLARE @m NVARCHAR(400) = CONCAT(N'scheme.AddSchemeMember: member kind ', @MemberKind, N' must name a current ', CASE @MemberKind WHEN N'ProtectionFunction' THEN N'ProtectionFunction node' WHEN N'Connection' THEN N'connection' WHEN N'Asset' THEN N'asset' WHEN N'Channel' THEN N'channel asset' ELSE N'member of the design''s list (ProtectionFunction, Asset, Connection, Channel)' END, N' (§7.2).');
        THROW 50271, @m, 1;
    END;

    -- #208: the analog input a source feeds
    DECLARE @kind NVARCHAR(20) = CASE @MemberRoleCode WHEN N'CtSource' THEN N'Current' WHEN N'VtSource' THEN N'Voltage' WHEN N'SyncVtSource' THEN N'SyncVoltage' END;
    IF @kind IS NOT NULL
    BEGIN
        IF @AnalogInputEntityId IS NOT NULL
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [scheme].[AnalogInput] WHERE [EntityId] = @AnalogInputEntityId AND [SchemeEntityId] = @SchemeEntityId AND [ValidTo] IS NULL AND [IsDeleted] = 0)
                THROW 50272, N'scheme.AddSchemeMember: the analog input is not a current input of this scheme.', 1;
        END
        ELSE
        BEGIN
            IF @ActorId IS NULL EXEC [personnel].[ResolveActor] @ActorId = @ActorId OUTPUT;
            SELECT TOP (1) @AnalogInputEntityId = [EntityId] FROM [scheme].[AnalogInput]
            WHERE [SchemeEntityId] = @SchemeEntityId AND [InputKind] = @kind AND [ValidTo] IS NULL AND [IsDeleted] = 0
            ORDER BY LEN([InputCode]), [InputCode];   -- Current 1 before Current 2 before Current 10
            IF @AnalogInputEntityId IS NULL
            BEGIN
                DECLARE @code NVARCHAR(40) = CASE @kind WHEN N'Current' THEN N'Current 1' WHEN N'Voltage' THEN N'Voltage 1' ELSE N'Sync voltage 1' END;
                EXEC [scheme].[AnalogInput_Add] @SchemeEntityId = @SchemeEntityId, @InputCode = @code, @InputKind = @kind,
                     @ValidFrom = @ValidFrom, @ValidFromQuality = @ValidFromQuality, @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @AnalogInputEntityId OUTPUT;
            END
        END
    END
    ELSE SET @AnalogInputEntityId = NULL;   -- only a source feeds an input

    -- #212: the winding used. Given, it must be a current winding of the member asset (50273); given none for a source, the
    -- asset's lowest-numbered winding is used when it has one (a transformer made from the legacy record has S1).
    IF @kind IS NOT NULL
    BEGIN
        IF @WindingEntityId IS NOT NULL
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [asset].[InstrumentWinding] WHERE [EntityId] = @WindingEntityId AND [AssetEntityId] = @MemberEntityId AND [ValidTo] IS NULL AND [IsDeleted] = 0)
                THROW 50273, N'scheme.AddSchemeMember: the winding is not a current secondary winding of this transformer.', 1;
        END
        ELSE
            SELECT TOP (1) @WindingEntityId = [EntityId] FROM [asset].[InstrumentWinding]
            WHERE [AssetEntityId] = @MemberEntityId AND [ValidTo] IS NULL AND [IsDeleted] = 0 ORDER BY [WindingNo];
    END
    ELSE SET @WindingEntityId = NULL;

    EXEC [scheme].[SchemeMember_Add] @SchemeEntityId = @SchemeEntityId, @MemberKind = @MemberKind, @MemberEntityId = @MemberEntityId, @MemberRoleCode = @MemberRoleCode,
         @IsInService = @IsInService, @Notes = @Notes, @AnalogInputEntityId = @AnalogInputEntityId, @WindingEntityId = @WindingEntityId, @ValidFrom = @ValidFrom, @ValidFromQuality = @ValidFromQuality,
         @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @EntityId OUTPUT, @RowId = @RowId OUTPUT;
END;
GO
