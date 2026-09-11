-- SCHEMA-DESIGN §11.8 (159).
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [ref].[AuthorisationRightKind] AS t
USING (VALUES
    (N'PhysicalAccess',    N'Physical access'),
    (N'ElectronicAccess',  N'Electronic access'),
    (N'RemoteAccess',      N'Remote access'),
    (N'InformationAccess', N'Information access (BES cyber system information)'),
    (N'EscortedAccess',    N'Escorted access')
) AS s ([RightKindCode], [Name])
ON t.[RightKindCode] = s.[RightKindCode]
WHEN MATCHED AND t.[Name] <> s.[Name] THEN UPDATE SET [Name] = s.[Name], [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET THEN INSERT ([RightKindCode], [Name], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
    VALUES (s.[RightKindCode], s.[Name], @actor, @now, @actor, @now);
GO
