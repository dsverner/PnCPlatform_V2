-- SCHEMA-DESIGN §7.2 (116): scheme member roles; the design's list ends "… extensible".
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [ref].[SchemeMemberRole] AS t
USING (VALUES
    (N'EndA',             N'End A'),
    (N'EndB',             N'End B'),
    (N'InitiatingDevice', N'Initiating device'),
    (N'TrippedBreaker',   N'Tripped breaker'),
    (N'CtSource',         N'CT source'),
    (N'VtSource',         N'VT source'),
    (N'SyncVtSource',     N'Sync VT source'),          -- #206: the single-phase PT feeding a 25's sync input
    (N'DcSource',         N'DC source'),
    (N'Channel',          N'Channel'),
    (N'BlockingInput',    N'Blocking input'),
    (N'IntertripReceive', N'Intertrip receive'),
    (N'IntertripSend',    N'Intertrip send'),
    (N'TripCircuit',      N'Trip circuit'),
    (N'LockoutRelay',     N'Lockout relay'),
    (N'AuxiliaryTrip',    N'Auxiliary trip'),
    (N'Member',           N'Member')                    -- W8 (#158): the role of a migrated position in its equipment group, until curation names a better one
) AS s ([MemberRoleCode], [Name])
ON t.[MemberRoleCode] = s.[MemberRoleCode]
WHEN MATCHED AND t.[Name] <> s.[Name] THEN UPDATE SET [Name] = s.[Name], [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET THEN INSERT ([MemberRoleCode], [Name], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
    VALUES (s.[MemberRoleCode], s.[Name], @actor, @now, @actor, @now);
GO
