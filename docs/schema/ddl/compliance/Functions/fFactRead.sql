-- FORMULA-GRAMMAR.md §4.2, SCHEMA-DESIGN §12.3. One fact for one subject, with parameters, as the grammar's
-- typed value JSON: {"k":"num","v":"2","u":"A","b":"Secondary"} | {"k":"text","v":..} | {"k":"bool","v":true}
-- | {"k":"date","v":..} | {"k":"ref","id":..,"kind":..} | {"k":"set","v":[..]} | {"k":"unk","why":[..]}.
-- Parameterised and relation-valued reads (PROCEDURES.md #35) live here, one branch per fact, each reading
-- the current rows valid at @at; the plain column facts go through fFixedFactValue / fCharacteristicFactValue /
-- fSettingFactValue and are typed by the catalogue. A Formula-source fact is not read here (compliance.fEvalNode
-- evaluates it: functions cannot be mutually recursive). @params is a plain JSON object {"role":"Relay"}.
-- Never a guess: an absent value is unk; an empty relation is an empty set.
CREATE FUNCTION [compliance].[fFactRead]
    (@subjectEntityId UNIQUEIDENTIFIER, @factName NVARCHAR(200), @params NVARCHAR(MAX), @at DATETIMEOFFSET(7))
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @source NVARCHAR(20), @key NVARCHAR(200), @defEntity UNIQUEIDENTIFIER, @dataType NVARCHAR(20),
            @unit NVARCHAR(20), @base NVARCHAR(20), @refKind NVARCHAR(60);
    SELECT TOP (1) @source = [FactSource], @key = [FactKey], @defEntity = [DefinitionEntityId], @dataType = [DataType],
                   @unit = [UnitCode], @base = [Base], @refKind = [ReferenceKind]
    FROM [compliance].[vFactCatalogue] WHERE [FactName] = @factName;
    IF @source IS NULL RETURN CONCAT(N'{"k":"unk","why":["unknown fact ', STRING_ESCAPE(@factName, 'json'), N'"]}');

    DECLARE @v NVARCHAR(400), @out NVARCHAR(MAX), @id UNIQUEIDENTIFIER, @p NVARCHAR(200);
    DECLARE @unk NVARCHAR(MAX) = CONCAT(N'{"k":"unk","why":["', STRING_ESCAPE(@factName, 'json'), N'"]}');

    -- ------------------------------------------------------------------ scheme
    IF @factName = N'scheme.members'
    BEGIN
        SET @p = JSON_VALUE(@params, '$.role');
        SELECT @out = N'{"k":"set","v":[' + ISNULL(STRING_AGG(CONCAT(N'{"k":"ref","id":"', LOWER(CONVERT(NVARCHAR(36), m.[MemberEntityId])), N'","kind":"', m.[MemberKind], N'"}'), N','), N'') + N']}'
        FROM [scheme].[SchemeMember] m
        WHERE m.[SchemeEntityId] = @subjectEntityId AND m.[IsDeleted] = 0 AND (@p IS NULL OR m.[MemberRoleCode] = @p)
          AND m.[ValidFrom] <= @at AND (m.[ValidTo] IS NULL OR m.[ValidTo] > @at);
        RETURN @out;
    END
    IF @factName = N'function.logical_node'
    BEGIN
        SELECT TOP (1) @id = cf.[LogicalNodeEntityId] FROM [scheme].[CommissionedFunction] cf
        WHERE cf.[ProtectionFunctionNodeEntityId] = @subjectEntityId AND cf.[IsDeleted] = 0 AND cf.[ValidFrom] <= @at AND (cf.[ValidTo] IS NULL OR cf.[ValidTo] > @at)
        ORDER BY cf.[IsPrincipal] DESC, cf.[ValidFrom] DESC, cf.[RowSeq] DESC;
        RETURN CASE WHEN @id IS NULL THEN @unk ELSE CONCAT(N'{"k":"ref","id":"', LOWER(CONVERT(NVARCHAR(36), @id)), N'","kind":"LogicalNode"}') END;
    END

    -- ------------------------------------------------------------------ records
    IF @factName = N'record.last'
    BEGIN
        DECLARE @kind NVARCHAR(40) = JSON_VALUE(@params, '$.kind');
        DECLARE @accepted BIT = CASE JSON_VALUE(@params, '$.accepted') WHEN N'true' THEN 1 WHEN N'false' THEN 0 END;
        SELECT TOP (1) @out = CONCAT(N'{"k":"ref","id":"', LOWER(CONVERT(NVARCHAR(36), r.[EntityId])), N'","kind":"Record"}')
        FROM [record].[Record] r
        WHERE r.[SubjectEntityId] = @subjectEntityId AND r.[IsDeleted] = 0 AND r.[ValidTo] IS NULL
          AND (@kind IS NULL OR r.[RecordKindCode] = @kind) AND r.[OccurredAt] <= @at
          AND (@accepted IS NULL OR @accepted = 0 OR EXISTS (SELECT 1 FROM [record].[Acceptance] a
                                                             WHERE a.[RecordEntityId] = r.[EntityId] AND a.[IsDeleted] = 0 AND a.[ValidTo] IS NULL
                                                               AND a.[AcceptanceStatus] = N'Accepted' AND a.[ValidFrom] <= @at))
        ORDER BY r.[OccurredAt] DESC, r.[RowSeq] DESC;
        RETURN ISNULL(@out, N'{"k":"unk","why":["record.last: no such record"]}');
    END
    IF @factName = N'record.occurred_at'
    BEGIN
        SELECT TOP (1) @v = CONVERT(NVARCHAR(40), r.[OccurredAt], 127) FROM [record].[Record] r
        WHERE r.[EntityId] = @subjectEntityId AND r.[IsDeleted] = 0 AND r.[ValidTo] IS NULL ORDER BY r.[RowSeq] DESC;
        RETURN [compliance].[fTypedValue](N'DateTime', @v, NULL, NULL, NULL, @factName);
    END

    -- ------------------------------------------------------------------ device: advisories, connections, network
    IF @factName = N'device.advisories'
    BEGIN
        DECLARE @open BIT = CASE JSON_VALUE(@params, '$.open') WHEN N'true' THEN 1 WHEN N'false' THEN 0 END;
        DECLARE @model UNIQUEIDENTIFIER = (SELECT TOP (1) a.[ModelId] FROM [asset].[Asset] a WHERE a.[EntityId] = @subjectEntityId AND a.[IsDeleted] = 0 AND a.[ValidFrom] <= @at AND (a.[ValidTo] IS NULL OR a.[ValidTo] > @at) ORDER BY a.[ValidFrom] DESC, a.[RowSeq] DESC);
        IF @model IS NULL RETURN N'{"k":"unk","why":["device.advisories: the device has no model"]}';
        SELECT @out = N'{"k":"set","v":[' + ISNULL(STRING_AGG(CONCAT(N'{"k":"ref","id":"', LOWER(CONVERT(NVARCHAR(36), s.[AdvisoryEntityId])), N'","kind":"Advisory"}'), N','), N'') + N']}'
        FROM (SELECT DISTINCT sc.[AdvisoryEntityId] FROM [device].[AdvisoryScope] sc
              WHERE sc.[ModelId] = @model AND sc.[IsDeleted] = 0 AND sc.[ValidFrom] <= @at AND (sc.[ValidTo] IS NULL OR sc.[ValidTo] > @at)) s
        WHERE EXISTS (SELECT 1 FROM [device].[Advisory] adv WHERE adv.[EntityId] = s.[AdvisoryEntityId] AND adv.[IsDeleted] = 0 AND adv.[ValidFrom] <= @at AND (adv.[ValidTo] IS NULL OR adv.[ValidTo] > @at))
          AND (@open IS NULL OR @open = 0 OR NOT EXISTS (SELECT 1 FROM [device].[AdvisoryDisposition] d
                                                        WHERE d.[AdvisoryEntityId] = s.[AdvisoryEntityId] AND d.[DeviceEntityId] = @subjectEntityId AND d.[IsDeleted] = 0
                                                          AND d.[ValidFrom] <= @at AND (d.[ValidTo] IS NULL OR d.[ValidTo] > @at)
                                                          AND (d.[Applicability] = N'NotApplicable' OR (d.[CompletedAt] IS NOT NULL AND d.[CompletedAt] <= @at))));
        RETURN @out;
    END
    IF @factName = N'device.connections'
    BEGIN
        SET @p = JSON_VALUE(@params, '$.realisation');
        SELECT @out = N'{"k":"set","v":[' + ISNULL(STRING_AGG(CONCAT(N'{"k":"ref","id":"', LOWER(CONVERT(NVARCHAR(36), c.[EntityId])), N'","kind":"Connection"}'), N','), N'') + N']}'
        FROM [connection].[Connection] c
        WHERE c.[IsDeleted] = 0 AND c.[ValidFrom] <= @at AND (c.[ValidTo] IS NULL OR c.[ValidTo] > @at)
          AND (@p IS NULL OR @p = N'*' OR c.[RealisationCode] = @p)
          AND EXISTS (SELECT 1 FROM [connection].[Port] pt WHERE pt.[AssetEntityId] = @subjectEntityId AND pt.[IsDeleted] = 0 AND pt.[ValidFrom] <= @at AND (pt.[ValidTo] IS NULL OR pt.[ValidTo] > @at)
                        AND pt.[EntityId] IN (c.[FromEntityId], c.[ToEntityId]));
        RETURN @out;
    END
    IF @factName IN (N'network.port', N'network.vlan', N'network.services')
    BEGIN
        SET @p = JSON_VALUE(@params, '$.protocol');
        IF @factName = N'network.port'
            SELECT @out = N'{"k":"set","v":[' + ISNULL(STRING_AGG(CONCAT(N'{"k":"ref","id":"', LOWER(CONVERT(NVARCHAR(36), pt.[EntityId])), N'","kind":"Port"}'), N','), N'') + N']}'
            FROM [connection].[Port] pt JOIN [connection].[NetworkPort] np ON np.[EntityId] = pt.[EntityId] AND np.[IsDeleted] = 0 AND np.[ValidFrom] <= @at AND (np.[ValidTo] IS NULL OR np.[ValidTo] > @at)
            WHERE pt.[AssetEntityId] = @subjectEntityId AND pt.[IsDeleted] = 0 AND pt.[ValidFrom] <= @at AND (pt.[ValidTo] IS NULL OR pt.[ValidTo] > @at);
        ELSE IF @factName = N'network.vlan'
            SELECT @out = N'{"k":"set","v":[' + ISNULL(STRING_AGG(CONCAT(N'{"k":"num","v":"', v.[VlanId], N'"}'), N','), N'') + N']}'
            FROM (SELECT DISTINCT np.[VlanId] FROM [connection].[Port] pt JOIN [connection].[NetworkPort] np ON np.[EntityId] = pt.[EntityId] AND np.[IsDeleted] = 0 AND np.[ValidFrom] <= @at AND (np.[ValidTo] IS NULL OR np.[ValidTo] > @at)
                  WHERE pt.[AssetEntityId] = @subjectEntityId AND pt.[IsDeleted] = 0 AND pt.[ValidFrom] <= @at AND (pt.[ValidTo] IS NULL OR pt.[ValidTo] > @at) AND np.[VlanId] IS NOT NULL) v;
        ELSE
            SELECT @out = N'{"k":"set","v":[' + ISNULL(STRING_AGG(CONCAT(N'{"k":"ref","id":"', LOWER(CONVERT(NVARCHAR(36), ps.[EntityId])), N'","kind":"PortService"}'), N','), N'') + N']}'
            FROM [connection].[PortService] ps JOIN [connection].[Port] pt ON pt.[EntityId] = ps.[NetworkPortEntityId] AND pt.[IsDeleted] = 0 AND pt.[ValidFrom] <= @at AND (pt.[ValidTo] IS NULL OR pt.[ValidTo] > @at)
            WHERE pt.[AssetEntityId] = @subjectEntityId AND ps.[IsDeleted] = 0 AND ps.[ValidFrom] <= @at AND (ps.[ValidTo] IS NULL OR ps.[ValidTo] > @at)
              AND (@p IS NULL OR @p = N'*' OR ps.[Protocol] = @p);
        RETURN @out;
    END

    -- ------------------------------------------------------------------ channel and ownership
    IF @factName = N'channel.route'
    BEGIN
        SELECT TOP (1) @id = r.[EntityId] FROM [location].[Route] r
        WHERE r.[OwnerAssetEntityId] = @subjectEntityId AND r.[RouteKind] = N'Channel' AND r.[IsDeleted] = 0 AND r.[ValidFrom] <= @at AND (r.[ValidTo] IS NULL OR r.[ValidTo] > @at)
        ORDER BY r.[ValidFrom] DESC, r.[RowSeq] DESC;
        RETURN CASE WHEN @id IS NULL THEN @unk ELSE CONCAT(N'{"k":"ref","id":"', LOWER(CONVERT(NVARCHAR(36), @id)), N'","kind":"Route"}') END;
    END
    IF @factName = N'channel.links'
    BEGIN
        DECLARE @owner UNIQUEIDENTIFIER = TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(@params, '$.owner'));
        SET @p = JSON_VALUE(@params, '$.owner');
        SELECT @out = N'{"k":"set","v":[' + ISNULL(STRING_AGG(CONCAT(N'{"k":"ref","id":"', LOWER(CONVERT(NVARCHAR(36), x.[AssetId])), N'","kind":"Asset"}'), N','), N'') + N']}'
        FROM (SELECT DISTINCT st.[OccupiedAssetEntityId] AS [AssetId]
              FROM [location].[Route] r JOIN [location].[RouteStep] st ON st.[RouteEntityId] = r.[EntityId] AND st.[IsDeleted] = 0 AND st.[ValidFrom] <= @at AND (st.[ValidTo] IS NULL OR st.[ValidTo] > @at)
              WHERE r.[OwnerAssetEntityId] = @subjectEntityId AND r.[RouteKind] = N'Channel' AND r.[IsDeleted] = 0 AND r.[ValidFrom] <= @at AND (r.[ValidTo] IS NULL OR r.[ValidTo] > @at)
                AND st.[OccupiedAssetEntityId] IS NOT NULL) x
        WHERE @p IS NULL OR @p = N'*' OR EXISTS (SELECT 1 FROM [asset].[OwnershipLink] o WHERE o.[SubjectEntityId] = x.[AssetId] AND o.[OwnershipRole] = N'Owner' AND o.[EntityEntityId] = @owner
                                                    AND o.[IsDeleted] = 0 AND o.[ValidFrom] <= @at AND (o.[ValidTo] IS NULL OR o.[ValidTo] > @at));
        RETURN @out;
    END
    IF @factName = N'asset.owner_of_record'
    BEGIN
        SET @p = ISNULL(JSON_VALUE(@params, '$.role'), N'Owner');
        SELECT TOP (1) @id = o.[EntityEntityId] FROM [asset].[OwnershipLink] o
        WHERE o.[SubjectEntityId] = @subjectEntityId AND o.[OwnershipRole] = @p AND o.[IsDeleted] = 0 AND o.[ValidFrom] <= @at AND (o.[ValidTo] IS NULL OR o.[ValidTo] > @at)
        ORDER BY o.[IsResponsibleForReporting] DESC, o.[Share] DESC, o.[ValidFrom] DESC;
        RETURN CASE WHEN @id IS NULL THEN @unk ELSE CONCAT(N'{"k":"ref","id":"', LOWER(CONVERT(NVARCHAR(36), @id)), N'","kind":"Entity"}') END;
    END

    -- ------------------------------------------------------------------ documents and studies
    IF @factName = N'study.is_stale'
    BEGIN
        -- the study is a revision subclass: the subject is the document; read the study on its latest revision current at @at
        SELECT TOP (1) @v = CASE st.[IsStale] WHEN 1 THEN N'true' ELSE N'false' END
        FROM [document].[Revision] rv JOIN [document].[Study] st ON st.[RevisionRowId] = rv.[RowId] AND st.[IsDeleted] = 0
        WHERE rv.[DocumentEntityId] = @subjectEntityId AND rv.[IsDeleted] = 0 AND rv.[ValidFrom] <= @at AND (rv.[ValidTo] IS NULL OR rv.[ValidTo] > @at)
        ORDER BY CASE WHEN rv.[Status] IN (N'Approved', N'Issued') THEN 0 ELSE 1 END, rv.[ValidFrom] DESC, rv.[RowSeq] DESC;
        RETURN [compliance].[fTypedValue](N'Boolean', @v, NULL, NULL, NULL, @factName);
    END
    IF @factName = N'document.revision_current'
    BEGIN
        SELECT TOP (1) @id = rv.[EntityId] FROM [document].[Revision] rv
        WHERE rv.[DocumentEntityId] = @subjectEntityId AND rv.[IsDeleted] = 0 AND rv.[ValidFrom] <= @at AND (rv.[ValidTo] IS NULL OR rv.[ValidTo] > @at)
          AND rv.[Status] IN (N'Approved', N'Issued') AND (rv.[EffectiveFrom] IS NULL OR rv.[EffectiveFrom] <= @at) AND (rv.[EffectiveTo] IS NULL OR rv.[EffectiveTo] > @at)
        ORDER BY rv.[EffectiveFrom] DESC, rv.[ApprovedAt] DESC, rv.[RowSeq] DESC;
        RETURN CASE WHEN @id IS NULL THEN @unk ELSE CONCAT(N'{"k":"ref","id":"', LOWER(CONVERT(NVARCHAR(36), @id)), N'","kind":"Revision"}') END;
    END
    IF @factName = N'document.class'
    BEGIN
        SELECT TOP (1) @v = d.[DefinitionKey] FROM [document].[Document] doc JOIN [config].[Definition] d ON d.[EntityId] = doc.[DocumentClassDefinitionEntityId]
        WHERE doc.[EntityId] = @subjectEntityId AND doc.[IsDeleted] = 0 AND doc.[ValidFrom] <= @at AND (doc.[ValidTo] IS NULL OR doc.[ValidTo] > @at) ORDER BY doc.[ValidFrom] DESC, doc.[RowSeq] DESC;
        RETURN [compliance].[fTypedValue](N'Text', @v, NULL, NULL, NULL, @factName);
    END

    -- ------------------------------------------------------------------ persons and entities
    IF @factName = N'person.qualifications'
    BEGIN
        SET @p = JSON_VALUE(@params, '$.type');
        RETURN CONCAT(N'{"k":"bool","v":', CASE WHEN EXISTS (SELECT 1 FROM [personnel].[PersonQualification] pq
                                                              WHERE pq.[PersonEntityId] = @subjectEntityId AND pq.[QualificationTypeCode] = @p AND pq.[IsDeleted] = 0
                                                                AND pq.[ValidFrom] <= @at AND (pq.[ValidTo] IS NULL OR pq.[ValidTo] > @at)
                                                                AND pq.[GrantedAt] <= @at AND (pq.[RevokedAt] IS NULL OR pq.[RevokedAt] > @at) AND (pq.[ExpiresAt] IS NULL OR pq.[ExpiresAt] > @at))
                                                 THEN N'true' ELSE N'false' END, N'}');
    END
    IF @factName = N'person.authorisations'
    BEGIN
        SET @p = JSON_VALUE(@params, '$.kind');
        RETURN CONCAT(N'{"k":"bool","v":', CASE WHEN EXISTS (SELECT 1 FROM [personnel].[Authorisation] au
                                                              WHERE au.[PersonEntityId] = @subjectEntityId AND au.[RightKindCode] = @p AND au.[IsDeleted] = 0
                                                                AND au.[ValidFrom] <= @at AND (au.[ValidTo] IS NULL OR au.[ValidTo] > @at)
                                                                AND (au.[RevokedAt] IS NULL OR au.[RevokedAt] > @at))
                                                 THEN N'true' ELSE N'false' END, N'}');
    END
    IF @factName = N'person.training_current'
    BEGIN
        SET @p = JSON_VALUE(@params, '$.module');
        DECLARE @moduleEntity UNIQUEIDENTIFIER, @freq INT;
        SELECT @moduleEntity = tm.[EntityId], @freq = tm.[RequiredFrequencyDays] FROM [personnel].[TrainingModule] tm WHERE tm.[TrainingModuleCode] = @p;
        IF @moduleEntity IS NULL RETURN CONCAT(N'{"k":"unk","why":["person.training_current: no training module ', STRING_ESCAPE(ISNULL(@p, N''), 'json'), N'"]}');
        DECLARE @last DATETIMEOFFSET(7) = (SELECT MAX(r.[OccurredAt]) FROM [record].[Record] r
                                           WHERE r.[SubjectEntityId] = @subjectEntityId AND r.[RecordKindCode] = N'TrainingAttendance' AND r.[SecondSubjectEntityId] = @moduleEntity
                                             AND r.[IsDeleted] = 0 AND r.[ValidTo] IS NULL AND r.[OccurredAt] <= @at);
        RETURN CONCAT(N'{"k":"bool","v":', CASE WHEN @last IS NOT NULL AND (@freq IS NULL OR DATEADD(DAY, @freq, @last) >= @at) THEN N'true' ELSE N'false' END, N'}');
    END
    IF @factName = N'person.employer'
    BEGIN
        SELECT TOP (1) @id = p.[EmployerEntityEntityId] FROM [personnel].[Person] p
        WHERE p.[EntityId] = @subjectEntityId AND p.[IsDeleted] = 0 AND p.[ValidFrom] <= @at AND (p.[ValidTo] IS NULL OR p.[ValidTo] > @at) ORDER BY p.[ValidFrom] DESC, p.[RowSeq] DESC;
        RETURN CASE WHEN @id IS NULL THEN @unk ELSE CONCAT(N'{"k":"ref","id":"', LOWER(CONVERT(NVARCHAR(36), @id)), N'","kind":"Entity"}') END;
    END
    IF @factName = N'entity.agreements'
    BEGIN
        SET @p = JSON_VALUE(@params, '$.kind');
        SELECT @out = N'{"k":"set","v":[' + ISNULL(STRING_AGG(CONCAT(N'{"k":"ref","id":"', LOWER(CONVERT(NVARCHAR(36), ag.[EntityId])), N'","kind":"EntityAgreement"}'), N','), N'') + N']}'
        FROM [party].[EntityAgreement] ag
        WHERE ag.[EntityEntityId] = @subjectEntityId AND ag.[IsDeleted] = 0 AND ag.[ValidFrom] <= @at AND (ag.[ValidTo] IS NULL OR ag.[ValidTo] > @at)
          AND (@p IS NULL OR @p = N'*' OR ag.[AgreementKind] = @p)
          AND (ag.[StartsAt] IS NULL OR ag.[StartsAt] <= @at) AND (ag.[EndsAt] IS NULL OR ag.[EndsAt] > @at);
        RETURN @out;
    END
    IF @factName = N'entity.kind'
    BEGIN
        SELECT TOP (1) @v = e.[EntityKind] FROM [party].[Entity] e
        WHERE e.[EntityId] = @subjectEntityId AND e.[IsDeleted] = 0 AND e.[ValidFrom] <= @at AND (e.[ValidTo] IS NULL OR e.[ValidTo] > @at) ORDER BY e.[ValidFrom] DESC, e.[RowSeq] DESC;
        RETURN [compliance].[fTypedValue](N'Text', @v, NULL, NULL, NULL, @factName);
    END

    -- ------------------------------------------------------------------ the platform itself (PLATFORM-ARCHITECTURE §8.1)
    IF @factName IN (N'platform.release', N'platform.baseline')
    BEGIN
        -- the latest succeeded deployment to this database at @at; the environment is this database's
        DECLARE @relId BIGINT, @relVersion NVARCHAR(40);
        SELECT TOP (1) @relId = r.[ReleaseId], @relVersion = r.[Version]
        FROM [platform].[Deployment] d JOIN [platform].[Release] r ON r.[ReleaseId] = d.[ReleaseId]
        WHERE d.[DatabaseName] = DB_NAME() AND d.[Outcome] = N'Succeeded' AND d.[DeployedAt] <= @at
        ORDER BY d.[DeployedAt] DESC, d.[DeploymentId] DESC;
        IF @relId IS NULL RETURN N'{"k":"unk","why":["platform.release: no succeeded deployment recorded for this database"]}';
        IF @factName = N'platform.release' RETURN CONCAT(N'{"k":"text","v":"', STRING_ESCAPE(@relVersion, 'json'), N'"}');
        RETURN CONCAT(N'{"k":"ref","id":"', @relId, N'","kind":"Release"}');
    END

    -- ------------------------------------------------------------------ lightning correlation (PLATFORM-ARCHITECTURE §5.2)
    IF @factName IN (N'operation.lightning_nearby', N'operation.lightning_count')
    BEGIN
        DECLARE @km DECIMAL(10,3) = TRY_CONVERT(DECIMAL(10,3), JSON_VALUE(@params, '$.km'));
        DECLARE @minutes INT = TRY_CONVERT(INT, JSON_VALUE(@params, '$.minutes'));
        IF @km IS NULL OR @minutes IS NULL RETURN N'{"k":"unk","why":["operation.lightning_*: km and minutes are required"]}';
        DECLARE @opAt DATETIMEOFFSET(7), @opAsset UNIQUEIDENTIFIER;
        SELECT TOP (1) @opAt = o.[OccurredAt], @opAsset = o.[PrimaryAssetEntityId] FROM [scheme].[ProtectionOperation] o
        WHERE o.[EntityId] = @subjectEntityId AND o.[IsDeleted] = 0 ORDER BY o.[ValidFrom] DESC, o.[RowSeq] DESC;
        IF @opAt IS NULL RETURN N'{"k":"unk","why":["operation.lightning_*: no such protection operation"]}';
        -- the operation's places: the primary asset's placement node(s) and, for a routed asset, its route step nodes, as of the operation
        DECLARE @places TABLE ([Location] GEOGRAPHY);
        INSERT @places
        SELECT n.[Location] FROM [asset].[Placement] pl JOIN [location].[Node] n ON n.[EntityId] = pl.[NodeEntityId] AND n.[IsDeleted] = 0 AND n.[ValidFrom] <= @opAt AND (n.[ValidTo] IS NULL OR n.[ValidTo] > @opAt)
        WHERE pl.[AssetEntityId] = @opAsset AND pl.[IsDeleted] = 0 AND pl.[ValidFrom] <= @opAt AND (pl.[ValidTo] IS NULL OR pl.[ValidTo] > @opAt) AND n.[Location] IS NOT NULL
        UNION ALL      -- geography is not comparable; duplicates are harmless in an EXISTS
        SELECT n.[Location] FROM [location].[Route] rt JOIN [location].[RouteStep] st ON st.[RouteEntityId] = rt.[EntityId] AND st.[IsDeleted] = 0 AND st.[ValidFrom] <= @opAt AND (st.[ValidTo] IS NULL OR st.[ValidTo] > @opAt)
        JOIN [location].[Node] n ON n.[EntityId] = st.[NodeEntityId] AND n.[IsDeleted] = 0 AND n.[ValidFrom] <= @opAt AND (n.[ValidTo] IS NULL OR n.[ValidTo] > @opAt)
        WHERE rt.[OwnerAssetEntityId] = @opAsset AND rt.[IsDeleted] = 0 AND rt.[ValidFrom] <= @opAt AND (rt.[ValidTo] IS NULL OR rt.[ValidTo] > @opAt) AND n.[Location] IS NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM @places) RETURN N'{"k":"unk","why":["operation.lightning_*: the primary asset has no located place"]}';
        DECLARE @from DATETIMEOFFSET(7) = DATEADD(MINUTE, -@minutes, @opAt), @to DATETIMEOFFSET(7) = DATEADD(MINUTE, @minutes, @opAt);
        DECLARE @m DECIMAL(18,3) = @km * 1000;
        IF @factName = N'operation.lightning_count'
            RETURN CONCAT(N'{"k":"num","v":"', (SELECT COUNT(*) FROM [event].[LightningStrike] ls
                                                   WHERE ls.[OccurredAt] BETWEEN @from AND @to
                                                     AND EXISTS (SELECT 1 FROM @places p WHERE ls.[Location].STDistance(p.[Location]) <= @m)), N'"}');
        SELECT @out = N'{"k":"set","v":[' + ISNULL(STRING_AGG(CONCAT(N'{"k":"ref","id":"', ls.[StrikeId], N'","kind":"LightningStrike"}'), N',') WITHIN GROUP (ORDER BY ls.[OccurredAt]), N'') + N']}'
        FROM [event].[LightningStrike] ls
        WHERE ls.[OccurredAt] BETWEEN @from AND @to
          AND EXISTS (SELECT 1 FROM @places p WHERE ls.[Location].STDistance(p.[Location]) <= @m);
        RETURN @out;
    END

    -- ------------------------------------------------------------------ plain column facts
    IF @source = N'Fixed'
        SET @v = [compliance].[fFixedFactValue](@subjectEntityId, @factName, @at);
    ELSE IF @source = N'Characteristic'
        SET @v = [compliance].[fCharacteristicFactValue](@subjectEntityId, @defEntity, @key, @at);
    ELSE IF @source = N'Setting'
        SET @v = [compliance].[fSettingFactValue](@subjectEntityId, @defEntity, @key, @at);
    ELSE
        RETURN CONCAT(N'{"k":"unk","why":["', STRING_ESCAPE(@factName, 'json'), N': source ', @source, N' is not read here"]}');
    RETURN [compliance].[fTypedValue](@dataType, @v, @unit, @base, @refKind, @factName);
END;
GO
