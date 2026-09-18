-- #184 (2026-09-18): NPCC Directory 4 and Criteria A-10, seeded from the documents themselves.
--
-- The owner, 2026-09-18: "NPCC A10 has no impact on settings but a huge impact on the physical design of the protection
-- (Directory 4 compliance) which makes it imperative that the users are aware of what those are, which is more of a
-- documentation awareness case." And on where the documents are: https://www.npcc.org/standards/regional-criteria.
--
-- Sources, read in full for the sections quoted (session scratchpad copies, 2026-09-18):
--   Directory 4  "NPCC Regional Reliability Reference Directory # 4: Bulk Power System Protection Criteria", adopted
--                December 01, 2009 (1.4); the version posted at npcc.org is dated 12182025 and listed effective
--                December 18, 2025. Requirements are Section 5 (R5.1 - R5.20, pages 6-17) and Section 6 (R6.1 - R6.3,
--                page 17). 1.6 Applicability: "The requirements of NPCC Directory #4 apply only to those facilities
--                defined as NPCC bulk power system elements as identified through the performance based methodology of
--                NPCC Document A-10" (page 2) - which is why the obligation rule npcc_d4 is scoped on the protected bus's
--                NpccBulkPowerSystem classification.
--   A-10         "Regional Reliability Reference Criteria A-10: Classification of Bulk Power System Elements", adopted
--                April 28, 2007; revision history: v1 December 1, 2009, v2 March 27, 2020, v3 May 6, 2020 (TFCP errata,
--                page 12 section 4.1). npcc.org lists it effective May 8, 2020. Its 1.3 Objective: "provide the
--                methodology to identify the bulk power system elements ... for NPCC criteria applicability" (page 1).
--
-- Every Summary below is the document's own sentence, shortened only by dropping sub-clause detail; nothing is added.
-- The Summary of a criterion with sub-clauses names them so a reader knows to open the document. The requirement
-- numbers are the document's own (R5.2, R5.11, R6.1 ...). Idempotent the way Seed_compliance_Standards_NB.sql is.
IF OBJECT_ID(N'[compliance].[Standard_Upsert]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @npcc UNIQUEIDENTIFIER, @sv UNIQUEIDENTIFIER, @eid UNIQUEIDENTIFIER, @rid UNIQUEIDENTIFIER;

SELECT @npcc = [EntityId] FROM [party].[vEntity]
 WHERE [EntityKind] = N'Regulator' AND [Name] = N'Northeast Power Coordinating Council, Inc.';
IF @npcc IS NULL
    EXEC [party].[Entity_Add] @Name = N'Northeast Power Coordinating Council, Inc.', @ShortName = N'NPCC',
         @EntityKind = N'Regulator', @ActorId = @actor, @EntityId = @npcc OUTPUT;

---------------------------------------------------------------------------------------------------------------
-- A-10 - the classification methodology. One requirement: it is what declares a bus BPS, and the platform records
-- that outcome as the bus's NpccBulkPowerSystem classification (BPS / Not BPS, the owner 2026-09-18).
---------------------------------------------------------------------------------------------------------------
EXEC [compliance].[Standard_Upsert] @StandardCode = N'NPCC-A10', @IssuingEntityEntityId = @npcc, @Family = N'NPCC',
     @Subject = N'Classification of Bulk Power System Elements (Regional Reliability Reference Criteria A-10)', @ActorId = @actor;
IF NOT EXISTS (SELECT 1 FROM [compliance].[StandardVersion]
                WHERE [StandardCode] = N'NPCC-A10' AND [VersionLabel] = N'A-10 v3 (2020-05-06)' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[StandardVersion_Add] @StandardCode = N'NPCC-A10', @VersionLabel = N'A-10 v3 (2020-05-06)',
         @EffectiveFrom = N'2020-05-06T00:00:00-04:00',
         @TextReference = N'https://cdn.prod.website-files.com/67229043316834b1a60feba3/67229043316834b1a60ffff3_a-10-20200508.pdf',
         @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END
SELECT @sv = [RowId] FROM [compliance].[vStandardVersion] WHERE [StandardCode] = N'NPCC-A10' AND [VersionLabel] = N'A-10 v3 (2020-05-06)';
IF @sv IS NULL THROW 50184, N'Seed_compliance_Standards_NPCC: A-10 v3 not found after insert.', 1;
IF NOT EXISTS (SELECT 1 FROM [compliance].[Requirement] WHERE [StandardVersionRowId] = @sv AND [RequirementNumber] = N'A-10' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[Requirement_Add] @StandardVersionRowId = @sv, @RequirementNumber = N'A-10',
         @Title = N'Classification of Bulk Power System Elements',
         @Summary = N'1.3 Objective (page 1): an established set of performance requirements shall be used to identify bulk power system buses and elements; bus-based power system simulation analysis shall be used to demonstrate system performance; elements are identified from the identification of the bulk power system buses; elements shall not be included in the bulk power system based on voltage class alone; a periodic comprehensive re-assessment of bus status and element exclusions shall be performed at least once every five years. Only elements classified as bulk power system as a result of the testing described in this document are included on the NPCC Bulk Power System List, and NPCC criteria and compliance monitoring consider only those.',
         @EvidenceGuidance = N'The A-10 study for the bus, and the bus''s place on (or absence from) the NPCC Bulk Power System List. In this platform the outcome is recorded as the bus''s NpccBulkPowerSystem classification: BPS or Not BPS.',
         @SubjectKinds = N'["Asset"]', @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END

---------------------------------------------------------------------------------------------------------------
-- Directory 4 - the protection criteria that apply to a BPS element. Section 5 and Section 6, page-cited.
---------------------------------------------------------------------------------------------------------------
EXEC [compliance].[Standard_Upsert] @StandardCode = N'NPCC-D4', @IssuingEntityEntityId = @npcc, @Family = N'NPCC',
     @Subject = N'Bulk Power System Protection Criteria (Regional Reliability Reference Directory # 4; adopted December 01, 2009)', @ActorId = @actor;
IF NOT EXISTS (SELECT 1 FROM [compliance].[StandardVersion]
                WHERE [StandardCode] = N'NPCC-D4' AND [VersionLabel] = N'D4 (2025-12-18)' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[StandardVersion_Add] @StandardCode = N'NPCC-D4', @VersionLabel = N'D4 (2025-12-18)',
         @EffectiveFrom = N'2025-12-18T00:00:00-05:00',
         @TextReference = N'https://cdn.prod.website-files.com/67229043316834b1a60feba3/69441146039b33c773b46f7b_Directory%204%20BPS%20Protection%20Criteria%2012182025.pdf',
         @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END
SELECT @sv = [RowId] FROM [compliance].[vStandardVersion] WHERE [StandardCode] = N'NPCC-D4' AND [VersionLabel] = N'D4 (2025-12-18)';
IF @sv IS NULL THROW 50184, N'Seed_compliance_Standards_NPCC: Directory 4 (2025-12-18) not found after insert.', 1;

DECLARE @req TABLE ([No] NVARCHAR(40), [Title] NVARCHAR(200), [Summary] NVARCHAR(MAX), [Ord] INT IDENTITY(1,1));
INSERT @req ([No], [Title], [Summary]) VALUES
(N'R5.1',  N'General Criteria',
 N'Page 6: The intent of the criteria is to ensure dependable and secure operation of the protection systems for bulk power system. For those protective relays intended for removal of faults from the bulk power system, dependability is paramount, and the redundancy provisions of the criteria shall apply. For protective relays installed for reasons other than fault sensing such as overload, etc., security is paramount, and the redundancy provisions do not apply.'),
(N'R5.2',  N'Criteria for Dependability',
 N'Pages 6-7. R5.2.1: all elements of the bulk power system shall be protected by two protection groups, each independently capable of performing the specified protective function for that element, also during energization (R5.2.1.1: the failure of a merging unit shall not lead to the loss of more than one protection group per element). R5.2.2: the two protection groups shall not share the same component (R5.2.2.1: each protection group supplied from its own DC circuit, not used in any other protection group protecting the same element). R5.2.3: means to trip all necessary local and remote breakers if a breaker fails to clear a fault. R5.2.4: protection for the blind spot where free-standing CTs are on one side of the breaker only. R5.2.5: frame ground and breaker failure protections as two independent protections for that blind spot.'),
(N'R5.3',  N'Criteria for Security',
 N'Page 7: Protection systems shall be designed to isolate only the faulted element, except where additional elements are tripped intentionally to preserve system integrity, or where isolating additional elements has no impact outside the local area.'),
(N'R5.4',  N'Criteria for Dependability and Security',
 N'Pages 7-8. R5.4.1: the thermal capability of all protection system components shall be adequate to withstand rated maximum short time and continuous loading of the protected elements. R5.4.2: position or state of control devices that can disable protections shall be monitored and annunciated. R5.4.3: where a LAN is part of the protection system, relay hardware, network paths, network hardware and merging units shall be continuously monitored and annunciated. R5.4.4: short circuit models shall take into account minimum and maximum fault levels and mutual effects of parallel lines. R5.4.5: components with redundant power supplies powered from the same DC battery system. R5.4.6: contact outputs used for tripping properly rated to make and carry the DC tripping current. R5.4.7: components with self-monitoring capability shall be annunciated.'),
(N'R5.5',  N'Operating Time Criteria',
 N'Page 8: Bulk power system protection shall take corrective action within times determined by studies in accordance with A-10 Classification of Bulk Power System Elements and Directory #1, Design and Operation of the Bulk Power System.'),
(N'R5.6',  N'Current Transformer Criteria',
 N'Pages 8-9: CTs associated with protection systems shall have adequate steady-state and transient characteristics. R5.6.1: each secondary winding designed to remain within acceptable limits for the connected burdens under all anticipated currents including fault currents. R5.6.2: thermal and mechanical capability at the operating tap adequate under maximum fault and normal or emergency loading. R5.6.3: independent protection groups supplied from separate CT secondary windings. R5.6.4: interconnected CT secondary wiring grounded at only one point. R5.6.5: CTs connected so that adjacent protection zones overlap.'),
(N'R5.7',  N'Voltage Transformer and Potential Devices Criteria',
 N'Page 9. R5.7.1: adequate volt-ampere capacity to supply the connected burden while maintaining rated accuracy. R5.7.2: the two protection groups protecting an element shall be supplied from separate voltage sources; separate secondary windings on one transformer are permitted provided R5.7.2.1 (loss of one or more phase voltages does not prevent all tripping), R5.7.2.2 (each winding has capacity to permit fuse protection) and R5.7.2.3 (each secondary winding circuit adequately fuse protected). R5.7.3: VT secondary wiring not grounded at more than one point.'),
(N'R5.8',  N'Battery and Direct Current (DC) Supply Criteria',
 N'Pages 9-10. R5.8.1: no single battery or DC power supply failure shall prevent both independent protection groups from performing; each battery with its own charger; physical separation between the two station batteries. R5.8.2: each station battery with capacity to operate the station on loss of its charger for the time needed to transfer load or re-establish supply. R5.8.3: a transfer arrangement to connect the total load to either battery without a single event disabling both DC supplies. R5.8.4: chargers and all DC circuits protected against short circuits, coordinated. R5.8.5: each DC supply continuously monitored and independently annunciated (abnormal voltage, DC grounds, loss of ac to chargers). R5.8.6: protection group DC sources continuously monitored and independently annunciated for loss of voltage.'),
(N'R5.9',  N'Station Service AC Supply Criteria',
 N'Page 10: On bulk power system facilities there shall be two sources of station service ac supply, each capable of carrying at least all the critical loads associated with protection systems.'),
(N'R5.10', N'Circuit Breakers Criteria',
 N'Page 10. R5.10.1: no single trip coil failure shall prevent both independent protection groups from performing; a breaker with two trip coils shall operate if both are energized simultaneously, verified by tests. R5.10.2: each trip coil monitored in a fail-safe manner for continuity and DC voltage and annunciated (R5.10.2.1: the monitoring design shall not introduce a single point of failure in the trip circuits, meeting 5.2.2.1).'),
(N'R5.11', N'Teleprotection Criteria',
 N'Pages 11-12. R5.11.1: communication facilities required for teleprotection designed to a level of performance consistent with the protection system, meeting R5.11.1.1 (the two teleprotection groups shall not share the same component), R5.11.1.2 (where each protection group needs a channel to meet 5.5: equipment on non-adjacent panels; media outside the substation designed against a single event, three feet minimum separation; a single radio tower permitted with directional diversity; where route diversity cannot be achieved, scheme selection shall meet 5.5), R5.11.1.3 (equipment monitored for loss), R5.11.1.4 (channels continuously monitored and alarmed; ON/OFF channels that cannot be continuously monitored get daily automated testing), R5.11.1.5 (means to test signal adequacy where automated testing is not provided), R5.11.1.6 (powered by substation batteries or sources independent of the power system), R5.11.1.7 (multiple DCB scheme design shall not allow over tripping of more than one element for a single component failure other than battery failure).'),
(N'R5.12', N'Environment',
 N'Pages 12-13. R5.12.1: each separate protection group and teleprotection protecting the same element on different non-adjacent vertical mounting assemblies or enclosures (except as in 5.12.7). R5.12.2: the same for protection group LAN devices. R5.12.3: wiring for separate groups not in the same cable nor terminated in the same panel. R5.12.4: fiber optics for separate groups shall not result in a common mode failure. R5.12.5: cabling for separate groups physically separated (different raceways, trays, trenches) up to the breaker or equipment control cabinet; R5.12.5.1: in a common raceway, separated by a non-flammable barrier. R5.12.6: left blank. R5.12.7: outdoor electronic devices of separate groups physically separated. R5.12.8: an electronic device outside the control house shall not be subject to environmental conditions above the IEEE or IEC limits; outdoor enclosures rated for the most extreme local condition. R5.12.9: DC distribution panels supplying system protection groups separated physically and non-adjacent.'),
(N'R5.13', N'Grounding Criteria',
 N'Page 13: An entity shall have, as part of its substation design procedures or specifications, a mandatory method of designing the substation ground grid which R5.13.1 can be traced to a recognized calculation methodology, R5.13.2 considers cable shielding, and R5.13.3 considers equipment grounding and its impact on the operation of the frame ground protection.'),
(N'R5.14', N'Transmission Line Protection Criteria',
 N'Page 13. R5.14.1: protection system settings shall not constitute a loading limitation as per NERC continent-wide PRC standards; where NERC approved exceptions are used the limits thus imposed shall be adhered to as system operating constraints. R5.14.2: a pilot protection shall be so designed that its failure or misoperation will not affect the operation of any other pilot protection on that same element.'),
(N'R5.15', N'Breaker Failure Protection Criteria',
 N'Pages 13-14: Means shall be provided to trip all necessary local and remote breakers in the event that a breaker fails to clear a fault. R5.15.1: for non-redundant breaker failure protection, initiation by each protection group which trips the breaker, with the optional exception of a breaker failure protection for an adjacent breaker. R5.15.2: for redundant breaker failure protection, each initiated only by its respective protection group. R5.15.3: system 1 breaker failure protection operates only system 1 trip coils of the backup breakers, system 2 only system 2 (R5.15.3.1: a non-redundant channel may transmit breaker failure transfer trip). R5.15.4: fault current detectors shall be used to determine that a breaker has failed to interrupt. R5.15.5: a series breaker can be an acceptable means of fault clearing for a failed breaker.'),
(N'R5.16', N'Design to Facilitate Testing and Maintenance',
 N'Pages 14-15. R5.16.1: the design of protection systems, in circuitry and physical arrangement, shall facilitate periodic testing and maintenance. R5.16.2: with a LAN, the design shall provide the ability to isolate the operation of protective relaying while maintaining a network path to view relay response under test. R5.16.3: a dedicated and secure means to connect to the LAN for testing, troubleshooting and operation. R5.16.4: test facilities and procedures shall not compromise the independence of the redundant design. R5.16.5: a segmented testing approach shall ensure related tests properly overlap. R5.16.6: network monitoring tools deployed to facilitate troubleshooting and corrective maintenance.'),
(N'R5.17', N'Design to Facilitate Analysis of Protection System Performance',
 N'Page 15. R5.17.1: each protection group shall be functionally tested to verify the dependability and security aspects of the design, when initially placed in service and when modifications are made.'),
(N'R5.18', N'Commissioning Testing',
 N'Page 15. R5.18.1: each protection group shall be functionally tested to verify the dependability and security aspects of the design, when initially placed in service and when modifications are made.'),
(N'R5.19', N'HVdc System Protection Criteria',
 N'Pages 15-16. R5.19.1 LCC-type: R5.19.1.1 the ac portion of a HVdc converter station up to the valve-side terminals of the converter transformers shall be protected in accordance with these criteria; R5.19.1.2 multiple commutation failures, unordered power reversals and faults in the converter bridges and the dc portion severe enough to disturb the bulk power system shall be detected by more than one independent control or protection group. R5.19.2 VSC-type: R5.19.2.1 the ac portion up to the converter arms terminals protected in accordance with these criteria; R5.19.2.2 abnormal ac conditions and faults in the converter arms and dc portion severe enough to disturb the bulk power system detected by more than one independent control or protection group.'),
(N'R5.20', N'Criteria for protection systems utilizing IEC 61850 protocol',
 N'Pages 16-17. R5.20.1: loss of one protection group''s sampled value data stream shall not compromise the redundant group''s stream, unless studies demonstrate the total clearing time is acceptable. R5.20.2: with process bus for both groups, a single device failure shall not lead to loss of time synchronization for both. R5.20.3: protection data shall take priority over other data on the same LAN, and protection message response time shall meet critical clearing time under all network loading. R5.20.4: actual LAN propagation times under stressed conditions included in clearing time calculations. R5.20.5: failure of a single network device shall not disable both protection groups. R5.20.6: network topology such that a single broken path does not disable both groups. R5.20.7: analog to digital conversion, processing and communication latency shall at a minimum meet current utility protection performance.'),
(N'R6.1',  N'Submittal to TFSP',
 N'Page 17: An entity, proposing to install a new protection system or a modification to an existing protection system, shall submit documentation to TFSP in accordance with Appendix B of this Directory.'),
(N'R6.2',  N'Letter of acceptance',
 N'Page 17: An entity, proposing to install a new protection system or a modification to an existing protection system, shall obtain a letter of acceptance by TFSP of the compliance statement accompanying the submittal in R1 prior to or within twelve months of placing the protection system in service.'),
(N'R6.3',  N'Evidence on request',
 N'Page 17: The entity shall provide within 30 days, upon request from the Regional Entity (Criteria Compliance Enforcement Program), documented evidence of the submittal and acceptance by TFSP, of any new or modified protection system.');

DECLARE @no NVARCHAR(40), @title NVARCHAR(200), @summary NVARCHAR(MAX);
DECLARE rq CURSOR LOCAL FAST_FORWARD FOR SELECT [No], [Title], [Summary] FROM @req ORDER BY [Ord];
OPEN rq; FETCH NEXT FROM rq INTO @no, @title, @summary;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM [compliance].[Requirement] WHERE [StandardVersionRowId] = @sv AND [RequirementNumber] = @no AND [ValidTo] IS NULL AND [IsDeleted] = 0)
    BEGIN SET @eid = NULL; SET @rid = NULL;
        EXEC [compliance].[Requirement_Add] @StandardVersionRowId = @sv, @RequirementNumber = @no, @Title = @title, @Summary = @summary,
             @EvidenceGuidance = N'Directory 4 is a design criterion, not a settings criterion: the evidence is the protection system design and its TFSP submittal and acceptance (R6.1 - R6.3), kept outside this platform. The platform''s part is awareness: every relay protecting a bus the A-10 study declares BPS shows these criteria.',
             @SubjectKinds = N'["Device"]', @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
    END
    FETCH NEXT FROM rq INTO @no, @title, @summary;
END
CLOSE rq; DEALLOCATE rq;
GO
