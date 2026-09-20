-- #214 (2026-09-20): the devices whose compliance depends on what the pending evaluation requests name — what the worker
-- evaluates. One place holds the inverse of the reads (fFixedFactValue / fFactRead / fDeviceProtects):
--   Device  the device itself
--   Asset   the asset itself when it is a device (its own classification, placement, model); and every candidate device whose
--           protects walk names it as the protected element or as the bus at the protected end (BES status, PRC-023 listing,
--           NPCC declaration, ratings, terminal voltage)
--   Node    every candidate device installed at the node or anywhere under it (a building's or station's CIP impact rating
--           is read up the tree by location.fNearestClassified; a position's commissioned functions)
--   Scheme  every candidate device whose protects walk lands on the scheme, and its Asset members (membership, protects link)
--   All     every candidate device (a rule, formula or derivation approved)
-- A procedure, not an inline function: the first cut (compliance.fAffectedDevices, an inline TVF applied per request) re-ran
-- the candidate scan and the protects walk for every request and every branch, and timed out under the smoke's load (13
-- "Execution Timeout Expired" in the worker, requests pending for five minutes). Here the candidates and their protects walk
-- are materialised once per turn, and not at all when only devices are named. @RequestIds is a JSON array of request ids.
CREATE PROCEDURE [compliance].[ExpandEvaluationRequests]
    @RequestIds NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @req TABLE ([SubjectKind] NVARCHAR(20) NOT NULL, [SubjectEntityId] UNIQUEIDENTIFIER NULL);
    INSERT @req SELECT r.[SubjectKind], r.[SubjectEntityId]
      FROM [compliance].[EvaluationRequest] r
      JOIN OPENJSON(@RequestIds) j ON TRY_CONVERT(UNIQUEIDENTIFIER, j.[value]) = r.[RequestId];
    IF EXISTS (SELECT 1 FROM @req WHERE [SubjectKind] = N'All')
    BEGIN
        SELECT [DeviceEntityId] FROM [compliance].[vRuleCandidateDevice];
        RETURN;
    END
    DECLARE @out TABLE ([DeviceEntityId] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY WITH (IGNORE_DUP_KEY = ON));
    INSERT @out SELECT DISTINCT q.[SubjectEntityId] FROM @req q WHERE q.[SubjectKind] = N'Device' AND q.[SubjectEntityId] IS NOT NULL;
    INSERT @out SELECT DISTINCT d.[EntityId] FROM @req q JOIN [device].[vDevice] d ON d.[EntityId] = q.[SubjectEntityId] WHERE q.[SubjectKind] = N'Asset';
    IF EXISTS (SELECT 1 FROM @req WHERE [SubjectKind] IN (N'Asset', N'Node', N'Scheme'))
    BEGIN
        -- the candidates and their protects walk, once
        DECLARE @cand TABLE ([DeviceEntityId] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY, [SchemeEntityId] UNIQUEIDENTIFIER NULL,
                             [PrimaryAssetEntityId] UNIQUEIDENTIFIER NULL, [BusAssetEntityId] UNIQUEIDENTIFIER NULL);
        INSERT @cand SELECT c.[DeviceEntityId], p.[SchemeEntityId], p.[PrimaryAssetEntityId], p.[BusAssetEntityId]
          FROM [compliance].[vRuleCandidateDevice] c
          OUTER APPLY [compliance].[fDeviceProtects](c.[DeviceEntityId], SYSDATETIMEOFFSET()) p;
        INSERT @out SELECT DISTINCT k.[DeviceEntityId] FROM @cand k JOIN @req q ON q.[SubjectKind] = N'Asset' AND (k.[PrimaryAssetEntityId] = q.[SubjectEntityId] OR k.[BusAssetEntityId] = q.[SubjectEntityId]);
        INSERT @out SELECT DISTINCT k.[DeviceEntityId] FROM @cand k JOIN @req q ON q.[SubjectKind] = N'Scheme' AND k.[SchemeEntityId] = q.[SubjectEntityId];
        INSERT @out SELECT DISTINCT sm.[MemberEntityId]
          FROM @req q
          JOIN [scheme].[SchemeMember] sm ON sm.[SchemeEntityId] = q.[SubjectEntityId] AND sm.[MemberKind] = N'Asset' AND sm.[ValidTo] IS NULL AND sm.[IsDeleted] = 0
          JOIN [device].[vDevice] d ON d.[EntityId] = sm.[MemberEntityId]
         WHERE q.[SubjectKind] = N'Scheme';
        INSERT @out SELECT DISTINCT k.[DeviceEntityId]
          FROM @cand k
          JOIN [asset].[Placement] pl ON pl.[AssetEntityId] = k.[DeviceEntityId] AND pl.[PlacementKind] = N'Installed' AND pl.[ValidTo] IS NULL AND pl.[IsDeleted] = 0
          JOIN [location].[Node] n ON n.[EntityId] = pl.[NodeEntityId] AND n.[ValidTo] IS NULL AND n.[IsDeleted] = 0
          JOIN @req q ON q.[SubjectKind] = N'Node' AND (n.[EntityId] = q.[SubjectEntityId] OR n.[Path] LIKE N'%' + CONVERT(NVARCHAR(36), q.[SubjectEntityId]) + N'/%');
    END
    SELECT [DeviceEntityId] FROM @out;
END;
GO
GRANT EXECUTE ON [compliance].[ExpandEvaluationRequests] TO [app_execute];
GO
