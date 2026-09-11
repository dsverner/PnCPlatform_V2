-- SCHEMA-DESIGN §1.1: action kinds.
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [ref].[ActionKind] AS t
USING (VALUES
    (N'Transition',     N'Workflow transition'),
    (N'AccessRefused',     N'Access refused at the API (PLATFORM-ARCHITECTURE §2.4, §4.5)'),
    (N'SignIn',     N'Session sign-in (§4.5)'),
    (N'SignOut',     N'Session sign-out or expiry (§4.5)'),
    (N'Approval',       N'Approval'),
    (N'Override',       N'Override (segregation, gate or check)'),
    (N'Grant',          N'Grant of a role or right'),
    (N'Revocation',     N'Revocation of a role or right'),
    (N'Administrative', N'Administrative act'),
    (N'Read',           N'Read of a logged object class (decision 65)'),
    (N'Release',        N'Platform release'),
    (N'AssetMerge',     N'Merge of assets (predecessor AssetReconciliationEvent, §8.11)'),
    (N'AssetSplit',     N'Split of an asset (predecessor AssetReconciliationEvent, §8.11)'),
    (N'FirmwareChanged', N'Firmware period opened on a device (§5.3; consumed by the settings re-validation rule)')
) AS s ([ActionKindCode], [Name])
ON t.[ActionKindCode] = s.[ActionKindCode]
WHEN MATCHED AND t.[Name] <> s.[Name] THEN UPDATE SET [Name] = s.[Name], [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET
    THEN INSERT ([ActionKindCode], [Name], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
         VALUES (s.[ActionKindCode], s.[Name], @actor, @now, @actor, @now);
GO
