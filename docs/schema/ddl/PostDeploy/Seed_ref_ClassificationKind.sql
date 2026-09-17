-- SCHEMA-DESIGN §4.7 (95): the classification kinds the design names, and what each is recorded
-- against. Allowed values per kind are not stated; AllowedValuesDefinitionRowId stays null for the
-- Administrator to attach.
-- #171 (2026-09-16): SubjectKinds is the JSON array of subjects a kind applies to — N'Station' (a
-- location.Node station), N'Asset' (a primary asset or a bus), N'Device'. compliance.vFactCatalogue
-- generates the classification facts from it, so only the kinds that apply to a subject become facts
-- of that subject. The CIP impact rating is the station's and the BES Cyber Asset flag is the device's
-- (the owner, 2026-09-16: applicability comes from the primary asset and the station, the device
-- inherits it from what it protects plus its own cyber nature).
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [ref].[ClassificationKind] AS t
USING (VALUES
    (N'BesStatus',            N'BES status',            NULL, N'["Asset","Station"]'),
    (N'CipImpactRating',      N'CIP impact rating',     NULL, N'["Station"]'),
    (N'NpccBulkPowerSystem',  N'NPCC bulk power system (declared by the A-10 study)', NULL, N'["Asset"]'),
    (N'NpccA10',              N'NPCC A-10 list (retired 2026-09-16: the A-10 study declares the BPS bus — NpccBulkPowerSystem)', NULL, NULL),
    (N'Prc023',               N'PRC-023 list (impactful lines)', NULL, N'["Asset"]'),
    (N'BesCyberAsset',        N'BES Cyber Asset',       N'Recorded per device by a person in this phase; the CIP-002 procedure will derive it later. Values: BCA / Not BCA.', N'["Device"]'),
    (N'ExternalRoutableConnectivity', N'External routable connectivity', N'Recorded per device. Values: ERC / No ERC.', N'["Device"]')
) AS s ([ClassificationKindCode], [Name], [Description], [SubjectKinds])
ON t.[ClassificationKindCode] = s.[ClassificationKindCode]
WHEN MATCHED AND (t.[Name] <> s.[Name]
                  OR ISNULL(t.[Description], N'') <> ISNULL(s.[Description], N'')
                  OR ISNULL(t.[SubjectKinds], N'') <> ISNULL(s.[SubjectKinds], N''))
    THEN UPDATE SET [Name] = s.[Name], [Description] = s.[Description], [SubjectKinds] = s.[SubjectKinds], [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET
    THEN INSERT ([ClassificationKindCode], [Name], [Description], [SubjectKinds], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
         VALUES (s.[ClassificationKindCode], s.[Name], s.[Description], s.[SubjectKinds], @actor, @now, @actor, @now);
GO
-- #170 (owner, 2026-09-16): the A-10 study is what declares an NPCC BPS bus — one kind, NpccBulkPowerSystem; NpccA10 is retired
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
UPDATE [ref].[ClassificationKind] SET [IsActive] = 0, [ModifiedBy] = @actor, [ModifiedAt] = SYSDATETIMEOFFSET() WHERE [ClassificationKindCode] = N'NpccA10' AND [IsActive] = 1;
GO
