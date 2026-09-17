-- SCHEMA-DESIGN §4.7 (95): the classification kinds the design names, and what each is recorded
-- against. Allowed values per kind are not stated; AllowedValuesDefinitionRowId stays null for the
-- Administrator to attach.
-- #171 (2026-09-16): SubjectKinds is the JSON array of subjects a kind applies to — N'Station' (a
-- location.Node station), N'Asset' (a primary asset or a bus), N'Device'. compliance.vFactCatalogue
-- generates the classification facts from it, so only the kinds that apply to a subject become facts
-- of that subject. The CIP impact rating is the station's and the BES Cyber Asset flag is the device's
-- (the owner, 2026-09-16: applicability comes from the primary asset and the station, the device
-- inherits it from what it protects plus its own cyber nature).
-- #173 (2026-09-17): AppliesToAssetTypes narrows a kind to particular asset types — NULL is every asset type the kind's
-- SubjectKinds already allow. PRC-023-6 §4.2.1 subjects circuits (lines, and transformers by their low-voltage terminal),
-- and the NPCC A-10 study declares a bus, so a bus page offers BES status and NPCC only (the owner, 2026-09-17: a bus is
-- not PRC-023 applicable and has no rating). DerivedByDefinitionKey names the Program.ClassificationDerivation that works
-- the kind out — BesCyberAsset is derived from the device's technology and what it protects, so nobody records it by hand.
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [ref].[ClassificationKind] AS t
USING (VALUES
    (N'BesStatus',            N'BES status',            NULL, N'["Asset","Station"]', NULL, NULL),
    (N'CipImpactRating',      N'CIP impact rating',     NULL, N'["Station"]', NULL, NULL),
    (N'NpccBulkPowerSystem',  N'NPCC bulk power system (declared by the A-10 study)', NULL, N'["Asset"]', N'["Bus"]', NULL),
    (N'NpccA10',              N'NPCC A-10 list (retired 2026-09-16: the A-10 study declares the BPS bus — NpccBulkPowerSystem)', NULL, NULL, NULL, NULL),
    (N'Prc023',               N'PRC-023 list (impactful lines)', NULL, N'["Asset"]', N'["Line","Transformer"]', NULL),
    (N'BesCyberAsset',        N'BES Cyber Asset',       N'Derived (#173): the device is a BES Cyber Asset when it is microprocessor based and the primary asset it protects is BES. Values: BCA / Not BCA.', N'["Device"]', NULL, N'bes_cyber_asset'),
    (N'ExternalRoutableConnectivity', N'External routable connectivity', N'Recorded per device until a network-analysis module can answer it (the owner, 2026-09-17). Values: ERC / No ERC.', N'["Device"]', NULL, NULL)
) AS s ([ClassificationKindCode], [Name], [Description], [SubjectKinds], [AppliesToAssetTypes], [DerivedByDefinitionKey])
ON t.[ClassificationKindCode] = s.[ClassificationKindCode]
WHEN MATCHED AND (t.[Name] <> s.[Name]
                  OR ISNULL(t.[Description], N'') <> ISNULL(s.[Description], N'')
                  OR ISNULL(t.[SubjectKinds], N'') <> ISNULL(s.[SubjectKinds], N'')
                  OR ISNULL(t.[AppliesToAssetTypes], N'') <> ISNULL(s.[AppliesToAssetTypes], N'')
                  OR ISNULL(t.[DerivedByDefinitionKey], N'') <> ISNULL(s.[DerivedByDefinitionKey], N''))
    THEN UPDATE SET [Name] = s.[Name], [Description] = s.[Description], [SubjectKinds] = s.[SubjectKinds],
                    [AppliesToAssetTypes] = s.[AppliesToAssetTypes], [DerivedByDefinitionKey] = s.[DerivedByDefinitionKey],
                    [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET
    THEN INSERT ([ClassificationKindCode], [Name], [Description], [SubjectKinds], [AppliesToAssetTypes], [DerivedByDefinitionKey], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
         VALUES (s.[ClassificationKindCode], s.[Name], s.[Description], s.[SubjectKinds], s.[AppliesToAssetTypes], s.[DerivedByDefinitionKey], @actor, @now, @actor, @now);
GO
-- #170 (owner, 2026-09-16): the A-10 study is what declares an NPCC BPS bus — one kind, NpccBulkPowerSystem; NpccA10 is retired
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
UPDATE [ref].[ClassificationKind] SET [IsActive] = 0, [ModifiedBy] = @actor, [ModifiedAt] = SYSDATETIMEOFFSET() WHERE [ClassificationKindCode] = N'NpccA10' AND [IsActive] = 1;
GO
