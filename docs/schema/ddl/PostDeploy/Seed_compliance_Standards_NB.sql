-- #171 (2026-09-16): the reliability standards in force in New Brunswick that the compliance rules of decision
-- #171 reference, with the requirements the owner listed on 2026-09-16 — CIP-004 R2, R4; CIP-005 R1; CIP-006 R1;
-- CIP-007 R1, R2, R3, R4, R5; CIP-010 R1, R2, R3; CIP-011 R1; PRC-023 R1, R3, R4, R5.
--
-- SOURCES, all read 2026-09-16:
--   NB Energy and Utilities Board, "Reliability Standards"  https://nbeub.ca/reliability-standards
--       Every version label (the NB appendix designation), every effective date and every NB appendix URL below
--       is read from that page's table. Its columns end "NB Appendix | Approved Date | Effective Date"; the
--       Effective Date column is the one used here. Dates are MM/DD/YY (confirmed: PRC-023-6 reads 10/01/24 and
--       is known to be in effect from 2024-10-01).
--   The NERC PDF that the NB EUB row links, one per standard, cited above each block. Requirement and Measure
--       text is quoted from that PDF, never from the NB appendix and never from memory.
--   NERC's own name  https://www.nerc.com/AboutNERC/Pages/default.aspx
--   NPCC's own name  https://www.npcc.org/
--
-- THE REQUIREMENT TEXTS ARE QUOTATIONS. @Summary is the requirement's own opening sentence and
-- @EvidenceGuidance is the Measure's first sentence, copied verbatim from the NERC PDF cited above the block.
-- Where the published standard carries an oddity it is carried through rather than corrected, and flagged in a
-- comment: CIP-010-4 R3 and M3 cite "CIP-010-3"; CIP-007-6 M5 says "Table 5"; CIP-011-3 M1 reads "CIP- 011-3".
-- CIP-006-6 sets its own code with non-breaking hyphens; it is written here with ordinary hyphens.
-- Anything that could not be read from a cited source is left NULL under an "-- UNVERIFIED:" line.
--
-- EffectiveFrom: the NB EUB publishes a date, not an instant. One convention is applied to all of them —
-- midnight Atlantic Standard Time (-04:00) on the published date. The date is the EUB's; the time of day is
-- this file's convention, not a reading of the source.
--
-- Idempotent: each version and each requirement is guarded, so a re-run adds nothing. Batch layout, @actor
-- declaration and the bootstrap guard follow Seed_ref_VoltageClass.sql and Seed_config_Workflow_Standard.sql.
IF OBJECT_ID(N'[compliance].[Standard_Upsert]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @nerc UNIQUEIDENTIFIER, @npcc UNIQUEIDENTIFIER;
DECLARE @sv UNIQUEIDENTIFIER, @eid UNIQUEIDENTIFIER, @rid UNIQUEIDENTIFIER;

---------------------------------------------------------------------------------------------------------------
-- The issuing body. compliance.Standard.IssuingEntityEntityId is an FK to party.EntityRegistry, so the standards
-- body is an ordinary party.Entity row, added the way Seed_ref_Model_SEL421.sql adds its manufacturer.
---------------------------------------------------------------------------------------------------------------
SELECT @nerc = [EntityId] FROM [party].[vEntity]
 WHERE [EntityKind] = N'StandardsBody' AND [Name] = N'North American Electric Reliability Corporation';
IF @nerc IS NULL
    EXEC [party].[Entity_Add] @Name = N'North American Electric Reliability Corporation', @ShortName = N'NERC',
         @EntityKind = N'StandardsBody', @ActorId = @actor, @EntityId = @nerc OUTPUT;

-- NPCC is seeded because PRC-023-6 R5 sends its annual list of circuits to "its Regional Entity". The name is
-- read from https://www.npcc.org/. EntityKind is this platform's classification — party.Entity's CK_Entity_Kind
-- has no 'RegionalEntity' member and 'Regulator' is the nearest; that choice is the platform's, not NPCC's.
-- UNVERIFIED: that NPCC is New Brunswick's Regional Entity for PRC-023-6 R5 is asserted in decision #171's
-- brief and is NOT read from any source cited in this file. No standard row points at NPCC here.
SELECT @npcc = [EntityId] FROM [party].[vEntity]
 WHERE [EntityKind] = N'Regulator' AND [Name] = N'Northeast Power Coordinating Council, Inc.';
IF @npcc IS NULL
    EXEC [party].[Entity_Add] @Name = N'Northeast Power Coordinating Council, Inc.', @ShortName = N'NPCC',
         @EntityKind = N'Regulator', @ActorId = @actor, @EntityId = @npcc OUTPUT;

---------------------------------------------------------------------------------------------------------------
-- CIP-004 — NB version CIP-004-7-NB-0, effective 2024-07-01 (NB EUB list)
-- Requirement text quoted from https://www.nerc.com/pa/Stand/Reliability%20Standards/CIP-004-7.pdf (p. 6, p. 11)
---------------------------------------------------------------------------------------------------------------
EXEC [compliance].[Standard_Upsert] @StandardCode = N'CIP-004', @IssuingEntityEntityId = @nerc, @Family = N'CIP',
     @Subject = N'Cyber Security — Personnel & Training', @ActorId = @actor;

IF NOT EXISTS (SELECT 1 FROM [compliance].[StandardVersion]
                WHERE [StandardCode] = N'CIP-004' AND [VersionLabel] = N'CIP-004-7-NB-0' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[StandardVersion_Add] @StandardCode = N'CIP-004', @VersionLabel = N'CIP-004-7-NB-0',
         @EffectiveFrom = N'2024-07-01T00:00:00-04:00',
         @TextReference = N'https://nbeub.ca/uploads/reliability_standards/NB%20Appendix%20CIP-004-7-NB-0.pdf',
         @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END
SELECT @sv = [RowId] FROM [compliance].[vStandardVersion] WHERE [StandardCode] = N'CIP-004' AND [VersionLabel] = N'CIP-004-7-NB-0';
IF @sv IS NULL THROW 50171, N'Seed_compliance_Standards_NB: CIP-004-7-NB-0 not found after insert.', 1;

IF NOT EXISTS (SELECT 1 FROM [compliance].[Requirement]
                WHERE [StandardVersionRowId] = @sv AND [RequirementNumber] = N'R2' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[Requirement_Add] @StandardVersionRowId = @sv, @RequirementNumber = N'R2',
         @Title = N'Cyber Security Training Program',
         @Summary = N'Each Responsible Entity shall implement one or more cyber security training program(s) appropriate to individual roles, functions, or responsibilities that collectively includes each of the applicable requirement parts in CIP-004-7 Table R2 – Cyber Security Training Program.',
         @EvidenceGuidance = N'Evidence must include the training program that includes each of the applicable requirement parts in CIP-004-7 Table R2 – Cyber Security Training Program and additional evidence to demonstrate implementation of the program(s).',
         @SubjectKinds = N'["Device"]', @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END

IF NOT EXISTS (SELECT 1 FROM [compliance].[Requirement]
                WHERE [StandardVersionRowId] = @sv AND [RequirementNumber] = N'R4' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[Requirement_Add] @StandardVersionRowId = @sv, @RequirementNumber = N'R4',
         @Title = N'Access Management Program',
         @Summary = N'Each Responsible Entity shall implement one or more documented access management program(s) that collectively include each of the applicable requirement parts in CIP-004-7 Table R4 – Access Management Program.',
         @EvidenceGuidance = N'Evidence must include the documented processes that collectively include each of the applicable requirement parts in CIP-004-7 Table R4 – Access Management Program and additional evidence to demonstrate that the access management program was implemented as described in the Measures column of the table.',
         @SubjectKinds = N'["Device"]', @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END

---------------------------------------------------------------------------------------------------------------
-- CIP-005 — NB version CIP-005-7-NB-0, effective 2023-04-01 (NB EUB list)
-- Requirement text quoted from https://www.nerc.com/pa/Stand/Reliability%20Standards/CIP-005-7.pdf (p. 6)
---------------------------------------------------------------------------------------------------------------
EXEC [compliance].[Standard_Upsert] @StandardCode = N'CIP-005', @IssuingEntityEntityId = @nerc, @Family = N'CIP',
     @Subject = N'Cyber Security — Electronic Security Perimeter(s)', @ActorId = @actor;

IF NOT EXISTS (SELECT 1 FROM [compliance].[StandardVersion]
                WHERE [StandardCode] = N'CIP-005' AND [VersionLabel] = N'CIP-005-7-NB-0' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[StandardVersion_Add] @StandardCode = N'CIP-005', @VersionLabel = N'CIP-005-7-NB-0',
         @EffectiveFrom = N'2023-04-01T00:00:00-04:00',
         @TextReference = N'https://nbeub.ca/uploads/reliability_standards/NB%20Appendix%20CIP-005-7-NB-0.pdf',
         @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END
SELECT @sv = [RowId] FROM [compliance].[vStandardVersion] WHERE [StandardCode] = N'CIP-005' AND [VersionLabel] = N'CIP-005-7-NB-0';
IF @sv IS NULL THROW 50171, N'Seed_compliance_Standards_NB: CIP-005-7-NB-0 not found after insert.', 1;

IF NOT EXISTS (SELECT 1 FROM [compliance].[Requirement]
                WHERE [StandardVersionRowId] = @sv AND [RequirementNumber] = N'R1' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[Requirement_Add] @StandardVersionRowId = @sv, @RequirementNumber = N'R1',
         @Title = N'Electronic Security Perimeter',
         @Summary = N'Each Responsible Entity shall implement one or more documented processes that collectively include each of the applicable requirement parts in CIP-005-7 Table R1 – Electronic Security Perimeter.',
         @EvidenceGuidance = N'Evidence must include each of the applicable documented processes that collectively include each of the applicable requirement parts in CIP-005-7 Table R1 – Electronic Security Perimeter and additional evidence to demonstrate implementation as described in the Measures column of the table.',
         @SubjectKinds = N'["Device"]', @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END

---------------------------------------------------------------------------------------------------------------
-- CIP-006 — NB version CIP-006-6-NB-0, effective 2017-01-01 (NB EUB list)
-- Requirement text quoted from https://www.nerc.com/pa/Stand/Reliability%20Standards/CIP-006-6.pdf (p. 6)
---------------------------------------------------------------------------------------------------------------
EXEC [compliance].[Standard_Upsert] @StandardCode = N'CIP-006', @IssuingEntityEntityId = @nerc, @Family = N'CIP',
     @Subject = N'Cyber Security — Physical Security of BES Cyber Systems', @ActorId = @actor;

IF NOT EXISTS (SELECT 1 FROM [compliance].[StandardVersion]
                WHERE [StandardCode] = N'CIP-006' AND [VersionLabel] = N'CIP-006-6-NB-0' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[StandardVersion_Add] @StandardCode = N'CIP-006', @VersionLabel = N'CIP-006-6-NB-0',
         @EffectiveFrom = N'2017-01-01T00:00:00-04:00',
         @TextReference = N'https://nbeub.ca/uploads/reliability_standards/NB%20Appendix%20CIP-006-6-NB-0.pdf',
         @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END
SELECT @sv = [RowId] FROM [compliance].[vStandardVersion] WHERE [StandardCode] = N'CIP-006' AND [VersionLabel] = N'CIP-006-6-NB-0';
IF @sv IS NULL THROW 50171, N'Seed_compliance_Standards_NB: CIP-006-6-NB-0 not found after insert.', 1;

IF NOT EXISTS (SELECT 1 FROM [compliance].[Requirement]
                WHERE [StandardVersionRowId] = @sv AND [RequirementNumber] = N'R1' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[Requirement_Add] @StandardVersionRowId = @sv, @RequirementNumber = N'R1',
         @Title = N'Physical Security Plan',
         @Summary = N'Each Responsible Entity shall implement one or more documented physical security plan(s) that collectively include all of the applicable requirement parts in CIP-006-6 Table R1 – Physical Security Plan.',
         @EvidenceGuidance = N'Evidence must include each of the documented physical security plans that collectively include all of the applicable requirement parts in CIP-006-6 Table R1 – Physical Security Plan and additional evidence to demonstrate implementation of the plan or plans as described in the Measures column of the table.',
         @SubjectKinds = N'["Device"]', @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END

---------------------------------------------------------------------------------------------------------------
-- CIP-007 — NB version CIP-007-6-NB-0, effective 2017-01-01 (NB EUB list)
-- Requirement text quoted from https://www.nerc.com/pa/Stand/Reliability%20Standards/CIP-007-6.pdf
--   (R1 p. 6, R2 p. 9, R3 p. 13, R4 p. 15, R5 p. 18)
-- @Subject is the standard's own cover title ("1. Title:", p. 1), which reads "System Security Management";
-- the PDF's running header and the NB EUB table both wording differ slightly from each other, and the cover wins.
---------------------------------------------------------------------------------------------------------------
EXEC [compliance].[Standard_Upsert] @StandardCode = N'CIP-007', @IssuingEntityEntityId = @nerc, @Family = N'CIP',
     @Subject = N'Cyber Security — System Security Management', @ActorId = @actor;

IF NOT EXISTS (SELECT 1 FROM [compliance].[StandardVersion]
                WHERE [StandardCode] = N'CIP-007' AND [VersionLabel] = N'CIP-007-6-NB-0' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[StandardVersion_Add] @StandardCode = N'CIP-007', @VersionLabel = N'CIP-007-6-NB-0',
         @EffectiveFrom = N'2017-01-01T00:00:00-04:00',
         @TextReference = N'https://nbeub.ca/uploads/reliability_standards/NB%20Appendix%20CIP-007-6-NB-0.pdf',
         @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END
SELECT @sv = [RowId] FROM [compliance].[vStandardVersion] WHERE [StandardCode] = N'CIP-007' AND [VersionLabel] = N'CIP-007-6-NB-0';
IF @sv IS NULL THROW 50171, N'Seed_compliance_Standards_NB: CIP-007-6-NB-0 not found after insert.', 1;

IF NOT EXISTS (SELECT 1 FROM [compliance].[Requirement]
                WHERE [StandardVersionRowId] = @sv AND [RequirementNumber] = N'R1' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[Requirement_Add] @StandardVersionRowId = @sv, @RequirementNumber = N'R1',
         @Title = N'Ports and Services',
         @Summary = N'Each Responsible Entity shall implement one or more documented process(es) that collectively include each of the applicable requirement parts in CIP-007-6 Table R1 – Ports and Services.',
         @EvidenceGuidance = N'Evidence must include the documented processes that collectively include each of the applicable requirement parts in CIP-007-6 Table R1 – Ports and Services and additional evidence to demonstrate implementation as described in the Measures column of the table.',
         @SubjectKinds = N'["Device"]', @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END

IF NOT EXISTS (SELECT 1 FROM [compliance].[Requirement]
                WHERE [StandardVersionRowId] = @sv AND [RequirementNumber] = N'R2' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[Requirement_Add] @StandardVersionRowId = @sv, @RequirementNumber = N'R2',
         @Title = N'Security Patch Management',
         @Summary = N'Each Responsible Entity shall implement one or more documented process(es) that collectively include each of the applicable requirement parts in CIP-007-6 Table R2 – Security Patch Management.',
         @EvidenceGuidance = N'Evidence must include each of the applicable documented processes that collectively include each of the applicable requirement parts in CIP-007-6 Table R2 – Security Patch Management and additional evidence to demonstrate implementation as described in the Measures column of the table.',
         @SubjectKinds = N'["Device"]', @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END

IF NOT EXISTS (SELECT 1 FROM [compliance].[Requirement]
                WHERE [StandardVersionRowId] = @sv AND [RequirementNumber] = N'R3' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[Requirement_Add] @StandardVersionRowId = @sv, @RequirementNumber = N'R3',
         @Title = N'Malicious Code Prevention',
         @Summary = N'Each Responsible Entity shall implement one or more documented process(es) that collectively include each of the applicable requirement parts in CIP-007-6 Table R3 – Malicious Code Prevention.',
         @EvidenceGuidance = N'Evidence must include each of the documented processes that collectively include each of the applicable requirement parts in CIP-007-6 Table R3 – Malicious Code Prevention and additional evidence to demonstrate implementation as described in the Measures column of the table.',
         @SubjectKinds = N'["Device"]', @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END

IF NOT EXISTS (SELECT 1 FROM [compliance].[Requirement]
                WHERE [StandardVersionRowId] = @sv AND [RequirementNumber] = N'R4' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[Requirement_Add] @StandardVersionRowId = @sv, @RequirementNumber = N'R4',
         @Title = N'Security Event Monitoring',
         @Summary = N'Each Responsible Entity shall implement one or more documented process(es) that collectively include each of the applicable requirement parts in CIP-007-6 Table R4 – Security Event Monitoring.',
         @EvidenceGuidance = N'Evidence must include each of the documented processes that collectively include each of the applicable requirement parts in CIP-007-6 Table R4 – Security Event Monitoring and additional evidence to demonstrate implementation as described in the Measures column of the table.',
         @SubjectKinds = N'["Device"]', @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END

-- M5 reads "Table 5", not "Table R5", in the published standard. Quoted as published.
IF NOT EXISTS (SELECT 1 FROM [compliance].[Requirement]
                WHERE [StandardVersionRowId] = @sv AND [RequirementNumber] = N'R5' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[Requirement_Add] @StandardVersionRowId = @sv, @RequirementNumber = N'R5',
         @Title = N'System Access Controls',
         @Summary = N'Each Responsible Entity shall implement one or more documented process(es) that collectively include each of the applicable requirement parts in CIP-007-6 Table R5 – System Access Controls.',
         @EvidenceGuidance = N'Evidence must include each of the applicable documented processes that collectively include each of the applicable requirement parts in CIP-007-6 Table 5 – System Access Controls and additional evidence to demonstrate implementation as described in the Measures column of the table.',
         @SubjectKinds = N'["Device"]', @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END

---------------------------------------------------------------------------------------------------------------
-- CIP-010 — NB version CIP-010-4-NB-0, effective 2023-04-01 (NB EUB list)
-- Requirement text quoted from https://www.nerc.com/pa/Stand/Reliability%20Standards/CIP-010-4.pdf
--   (R1 p. 6, R2 p. 10, R3 p. 11)
---------------------------------------------------------------------------------------------------------------
EXEC [compliance].[Standard_Upsert] @StandardCode = N'CIP-010', @IssuingEntityEntityId = @nerc, @Family = N'CIP',
     @Subject = N'Cyber Security — Configuration Change Management and Vulnerability Assessments', @ActorId = @actor;

IF NOT EXISTS (SELECT 1 FROM [compliance].[StandardVersion]
                WHERE [StandardCode] = N'CIP-010' AND [VersionLabel] = N'CIP-010-4-NB-0' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[StandardVersion_Add] @StandardCode = N'CIP-010', @VersionLabel = N'CIP-010-4-NB-0',
         @EffectiveFrom = N'2023-04-01T00:00:00-04:00',
         @TextReference = N'https://nbeub.ca/uploads/reliability_standards/NB%20Appendix%20CIP-010-4-NB-0.pdf',
         @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END
SELECT @sv = [RowId] FROM [compliance].[vStandardVersion] WHERE [StandardCode] = N'CIP-010' AND [VersionLabel] = N'CIP-010-4-NB-0';
IF @sv IS NULL THROW 50171, N'Seed_compliance_Standards_NB: CIP-010-4-NB-0 not found after insert.', 1;

IF NOT EXISTS (SELECT 1 FROM [compliance].[Requirement]
                WHERE [StandardVersionRowId] = @sv AND [RequirementNumber] = N'R1' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[Requirement_Add] @StandardVersionRowId = @sv, @RequirementNumber = N'R1',
         @Title = N'Configuration Change Management',
         @Summary = N'Each Responsible Entity shall implement one or more documented process(es) that collectively include each of the applicable requirement parts in CIP-010-4 Table R1 – Configuration Change Management.',
         @EvidenceGuidance = N'Evidence must include each of the applicable documented processes that collectively include each of the applicable requirement parts in CIP-010-4 Table R1 – Configuration Change Management and additional evidence to demonstrate implementation as described in the Measures column of the table.',
         @SubjectKinds = N'["Device"]', @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END

IF NOT EXISTS (SELECT 1 FROM [compliance].[Requirement]
                WHERE [StandardVersionRowId] = @sv AND [RequirementNumber] = N'R2' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[Requirement_Add] @StandardVersionRowId = @sv, @RequirementNumber = N'R2',
         @Title = N'Configuration Monitoring',
         @Summary = N'Each Responsible Entity shall implement one or more documented process(es) that collectively include each of the applicable requirement parts in CIP-010-4 Table R2 – Configuration Monitoring.',
         @EvidenceGuidance = N'Evidence must include each of the applicable documented processes that collectively include each of the applicable requirement parts in CIP-010-4 Table R2 – Configuration Monitoring and additional evidence to demonstrate implementation as described in the Measures column of the table.',
         @SubjectKinds = N'["Device"]', @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END

-- R3 and M3 of the published CIP-010-4 cite "CIP-010-3 Table R3" (R3 also without a space before the dash),
-- although the table itself is headed "CIP-010-4 Table R3 – Vulnerability Assessments". Quoted as published.
IF NOT EXISTS (SELECT 1 FROM [compliance].[Requirement]
                WHERE [StandardVersionRowId] = @sv AND [RequirementNumber] = N'R3' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[Requirement_Add] @StandardVersionRowId = @sv, @RequirementNumber = N'R3',
         @Title = N'Vulnerability Assessments',
         @Summary = N'Each Responsible Entity shall implement one or more documented process(es) that collectively include each of the applicable requirement parts in CIP-010-3 Table R3– Vulnerability Assessments.',
         @EvidenceGuidance = N'Evidence must include each of the applicable documented processes that collectively include each of the applicable requirement parts in CIP-010-3 Table R3 – Vulnerability Assessments and additional evidence to demonstrate implementation as described in the Measures column of the table.',
         @SubjectKinds = N'["Device"]', @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END

---------------------------------------------------------------------------------------------------------------
-- CIP-011 — NB version CIP-011-3-NB-0, effective 2024-07-01 (NB EUB list)
-- Requirement text quoted from https://www.nerc.com/pa/Stand/Reliability%20Standards/CIP-011-3.pdf (p. 6)
---------------------------------------------------------------------------------------------------------------
EXEC [compliance].[Standard_Upsert] @StandardCode = N'CIP-011', @IssuingEntityEntityId = @nerc, @Family = N'CIP',
     @Subject = N'Cyber Security — Information Protection', @ActorId = @actor;

IF NOT EXISTS (SELECT 1 FROM [compliance].[StandardVersion]
                WHERE [StandardCode] = N'CIP-011' AND [VersionLabel] = N'CIP-011-3-NB-0' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[StandardVersion_Add] @StandardCode = N'CIP-011', @VersionLabel = N'CIP-011-3-NB-0',
         @EffectiveFrom = N'2024-07-01T00:00:00-04:00',
         @TextReference = N'https://nbeub.ca/uploads/reliability_standards/NB%20Appendix%20CIP-011-3-NB-0.pdf',
         @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END
SELECT @sv = [RowId] FROM [compliance].[vStandardVersion] WHERE [StandardCode] = N'CIP-011' AND [VersionLabel] = N'CIP-011-3-NB-0';
IF @sv IS NULL THROW 50171, N'Seed_compliance_Standards_NB: CIP-011-3-NB-0 not found after insert.', 1;

-- M1 reads "CIP- 011-3" in the published standard. Quoted as published.
IF NOT EXISTS (SELECT 1 FROM [compliance].[Requirement]
                WHERE [StandardVersionRowId] = @sv AND [RequirementNumber] = N'R1' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[Requirement_Add] @StandardVersionRowId = @sv, @RequirementNumber = N'R1',
         @Title = N'Information Protection Program',
         @Summary = N'Each Responsible Entity shall implement one or more documented information protection program(s) for BES Cyber System Information (BCSI) pertaining to “Applicable Systems” identified in CIP-011-3 Table R1 – Information Protection Program that collectively includes each of the applicable requirement parts in CIP-011-3 Table R1 – Information Protection Program.',
         @EvidenceGuidance = N'Evidence for the information protection program must include the applicable requirement parts in CIP- 011-3 Table R1 – Information Protection Program and additional evidence to demonstrate implementation as described in the Measures column of the table.',
         @SubjectKinds = N'["Device"]', @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END

---------------------------------------------------------------------------------------------------------------
-- PRC-023 — NB version PRC-023-6-NB-0, effective 2024-10-01 (NB EUB list; the NB appendix PRC-023-6-NB-0 makes
-- no change to R1's criteria, and R5's annual list goes to NPCC).
-- Requirement text quoted from https://www.nerc.com/pa/Stand/Reliability%20Standards/PRC-023-6.pdf
--   (R1 and criteria pp. 3-5, M1 p. 5, R3/M3/R4/M4/R5 p. 5, M5 p. 6)
-- PRC-023-6 gives its requirements no headings, so @Title is NULL for all four.
-- UNVERIFIED: PRC-023-6 states no per-requirement title; none is invented here.
---------------------------------------------------------------------------------------------------------------
EXEC [compliance].[Standard_Upsert] @StandardCode = N'PRC-023', @IssuingEntityEntityId = @nerc, @Family = N'PRC',
     @Subject = N'Transmission Relay Loadability', @ActorId = @actor;

IF NOT EXISTS (SELECT 1 FROM [compliance].[StandardVersion]
                WHERE [StandardCode] = N'PRC-023' AND [VersionLabel] = N'PRC-023-6-NB-0' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[StandardVersion_Add] @StandardCode = N'PRC-023', @VersionLabel = N'PRC-023-6-NB-0',
         @EffectiveFrom = N'2024-10-01T00:00:00-04:00',
         @TextReference = N'https://nbeub.ca/uploads/reliability_standards/NB%20Appendix%20PRC-023-6-NB-0.pdf',
         @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END
SELECT @sv = [RowId] FROM [compliance].[vStandardVersion] WHERE [StandardCode] = N'PRC-023' AND [VersionLabel] = N'PRC-023-6-NB-0';
IF @sv IS NULL THROW 50171, N'Seed_compliance_Standards_NB: PRC-023-6-NB-0 not found after insert.', 1;

-- R1's opening sentence, then criteria 1, 2, 12 and 13 verbatim — the four the group's settings work is judged
-- against (#171). Criteria 3-11 are in the standard and are not repeated here.
IF NOT EXISTS (SELECT 1 FROM [compliance].[Requirement]
                WHERE [StandardVersionRowId] = @sv AND [RequirementNumber] = N'R1' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[Requirement_Add] @StandardVersionRowId = @sv, @RequirementNumber = N'R1',
         @Title = NULL,
         @Summary = N'Each Transmission Owner, Generator Owner, and Distribution Provider shall use any one of the following criteria (Requirement R1, criteria 1 through 13) for any specific circuit terminal to prevent its phase protective relay settings from limiting transmission system loadability while maintaining reliable protection of the BES for all fault conditions.

Criterion 1. Set transmission line relays so they do not operate at or below 150% of the highest seasonal Facility Rating of a circuit, for the available defined loading duration nearest 4 hours (expressed in amperes).

Criterion 2. Set transmission line relays so they do not operate at or below 115% of the highest seasonal 15-minute Facility Rating of a circuit (expressed in amperes).

Criterion 12. When the desired transmission line capability is limited by the requirement to adequately protect the transmission line, set the transmission line distance relays to a maximum of 125% of the apparent impedance (at the impedance angle of the transmission line) subject to the following constraints:
a. Set the maximum torque angle (MTA) to 90 degrees or the highest supported by the manufacturer.
b. Evaluate the relay loadability in amperes at the relay trip point at 0.85 per unit voltage and a power factor angle of 30 degrees.
c. Include a relay setting component of 87% of the current calculated in Requirement R1, criterion 12 in the Facility Rating determination for the circuit.

Criterion 13. Where other situations present practical limitations on circuit capability, set the phase protection relays so they do not operate at or below 115% of such limitations.',
         @EvidenceGuidance = N'Each Transmission Owner, Generator Owner, and Distribution Provider shall have evidence such as spreadsheets or summaries of calculations to show that each of its transmission relays is set according to one of the criteria in Requirement R1, criterion 1 through 13 and shall have evidence such as coordination curves or summaries of calculations that show that relays set per criterion 10 do not expose the transformer to fault levels and durations beyond those indicated in the standard.',
         @SubjectKinds = N'["Device"]', @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END

IF NOT EXISTS (SELECT 1 FROM [compliance].[Requirement]
                WHERE [StandardVersionRowId] = @sv AND [RequirementNumber] = N'R3' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[Requirement_Add] @StandardVersionRowId = @sv, @RequirementNumber = N'R3',
         @Title = NULL,
         @Summary = N'Each Transmission Owner, Generator Owner, and Distribution Provider that uses a circuit capability with the practical limitations described in Requirement R1, criterion 7, 8, 9, 12, or 13 shall use the calculated circuit capability as the Facility Rating of the circuit and shall obtain the agreement of the Planning Coordinator, Transmission Operator, and Reliability Coordinator with the calculated circuit capability.',
         @EvidenceGuidance = N'Each Transmission Owner, Generator Owner, and Distribution Provider with transmission relays set according to Requirement R1, criterion 7, 8, 9, 12, or 13 shall have evidence such as Facility Rating spreadsheets or Facility Rating database to show that it used the calculated circuit capability as the Facility Rating of the circuit and evidence such as dated correspondence that the resulting Facility Rating was agreed to by its associated Planning Coordinator, Transmission Operator, and Reliability Coordinator.',
         @SubjectKinds = N'["Device"]', @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END

IF NOT EXISTS (SELECT 1 FROM [compliance].[Requirement]
                WHERE [StandardVersionRowId] = @sv AND [RequirementNumber] = N'R4' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[Requirement_Add] @StandardVersionRowId = @sv, @RequirementNumber = N'R4',
         @Title = NULL,
         @Summary = N'Each Transmission Owner, Generator Owner, and Distribution Provider that chooses to use Requirement R1 criterion 2 as the basis for verifying transmission line relay loadability shall provide its Planning Coordinator, Transmission Operator, and Reliability Coordinator with an updated list of circuits associated with those transmission line relays at least once each calendar year, with no more than 15 months between reports.',
         @EvidenceGuidance = N'Each Transmission Owner, Generator Owner, or Distribution Provider that sets transmission line relays according to Requirement R1, criterion 2 shall have evidence such as dated correspondence to show that it provided its Planning Coordinator, Transmission Operator, and Reliability Coordinator with an updated list of circuits associated with those transmission line relays within the required timeframe.',
         @SubjectKinds = N'["Device"]', @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END

IF NOT EXISTS (SELECT 1 FROM [compliance].[Requirement]
                WHERE [StandardVersionRowId] = @sv AND [RequirementNumber] = N'R5' AND [ValidTo] IS NULL AND [IsDeleted] = 0)
BEGIN SET @eid = NULL; SET @rid = NULL;
    EXEC [compliance].[Requirement_Add] @StandardVersionRowId = @sv, @RequirementNumber = N'R5',
         @Title = NULL,
         @Summary = N'Each Transmission Owner, Generator Owner, and Distribution Provider that sets transmission line relays according to Requirement R1 criterion 12 shall provide an updated list of the circuits associated with those relays to its Regional Entity at least once each calendar year, with no more than 15 months between reports, to allow the ERO to compile a list of all circuits that have protective relay settings that limit circuit capability.',
         @EvidenceGuidance = N'Each Transmission Owner, Generator Owner, or Distribution Provider that sets transmission line relays according to Requirement R1, criterion 12 shall have evidence such as dated correspondence that it provided an updated list of the circuits associated with those relays to its Regional Entity within the required timeframe.',
         @SubjectKinds = N'["Device"]', @ActorId = @actor, @EntityId = @eid OUTPUT, @RowId = @rid OUTPUT;
END
GO
