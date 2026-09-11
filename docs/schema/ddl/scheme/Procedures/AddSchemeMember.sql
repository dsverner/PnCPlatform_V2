-- SCHEMA-DESIGN §7.2 (decision 116); PROCEDURES.md #12.
-- Adds a member to a scheme after the polymorphic check the design puts in the procedure:
-- ProtectionFunction → a current node of that type; Asset and Channel → a current asset (a
-- channel is an asset, §7.2); Connection → a current connection. Members are functions,
-- assets and connections, never devices, so a relay swap leaves the scheme intact.
CREATE PROCEDURE [scheme].[AddSchemeMember]
    @SchemeEntityId UNIQUEIDENTIFIER,
    @MemberKind NVARCHAR(40),
    @MemberEntityId UNIQUEIDENTIFIER,
    @MemberRoleCode NVARCHAR(40),
    @IsInService BIT = 1,
    @Notes NVARCHAR(MAX) = NULL,
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
    EXEC [scheme].[SchemeMember_Add] @SchemeEntityId = @SchemeEntityId, @MemberKind = @MemberKind, @MemberEntityId = @MemberEntityId, @MemberRoleCode = @MemberRoleCode,
         @IsInService = @IsInService, @Notes = @Notes, @ValidFrom = @ValidFrom, @ValidFromQuality = @ValidFromQuality,
         @ActorId = @ActorId, @MigrationRunId = @MigrationRunId, @EntityId = @EntityId OUTPUT, @RowId = @RowId OUTPUT;
END;
GO
