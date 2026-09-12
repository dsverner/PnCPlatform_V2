-- SCHEMA-DESIGN §10.1 (143) list, plus VulnerabilityAssessment (§12.10) and TrainingAttendance (§11.6). Extensible.
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [ref].[RecordKind] AS t
USING (VALUES
    (N'TestSheet',                   N'Test sheet'),
    (N'PlatformDeployment',          N'Platform deployment / relocation checklist (PLATFORM-ARCHITECTURE §1.4, §9)'),
    (N'Readback',                    N'Readback'),
    (N'CommissioningPackage',        N'Commissioning package'),
    (N'Finding',                     N'Finding'),
    (N'Attestation',                 N'Attestation'),
    (N'NotificationAcknowledgement', N'Notification acknowledgement'),
    (N'SettingsVerification',        N'Settings verification'),
    (N'IndependenceVerification',    N'Independence verification'),
    (N'OperationReview',             N'Operation review'),
    (N'ChannelMeasurement',          N'Channel measurement'),
    (N'Calibration',                 N'Calibration'),
    (N'ParityTest',                  N'Parity test'),
    (N'ConsistencyCheck',            N'Consistency check'),
    (N'OnTheJobTraining',            N'On-the-job training'),
    (N'ConditionObservation',        N'Condition observation'),
    (N'VulnerabilityAssessment',     N'Vulnerability assessment (§12.10)'),
    (N'TrainingAttendance',          N'Training attendance (§11.6)'),
    (N'LayerReconciliation',         N'Layer reconciliation session: an external model aligned with the physical model (§13.1, 189)'),
    (N'LayerMatchCandidate',         N'Proposed physical endpoint for a layer node, accepted by a person before it is applied (§13.1, 189)'),
    -- PROCEDURE-ENGINE §3 (#42): every step produces a record; the kinds the SETTINGS_CHANGE example names, seeded with it (W3)
    (N'RequestConfirmation',         N'Request confirmation (settings change step 1; produces the settings-issue package, #52)'),
    (N'ScopeDecision',               N'Scope and design decision (step 2)'),
    (N'Study',                       N'Study or calculation (step 3)'),
    (N'ConfigurationFileRevision',   N'Configuration-file revision committed into the settings book (step 4, §5.1)'),
    (N'Rationale',                   N'Rationale document (step 5)'),
    (N'EngineeringCheck',            N'Independent engineering check (step 6)'),
    (N'Approval',                    N'Formal approval of a settings-issue package (step 7)'),
    (N'SettingsIssue',               N'Issue to the field (step 8)'),
    (N'FieldApplication',            N'Settings applied to the relay (step 9)'),
    (N'ReturnToService',             N'Return to service declared, witnessed (step 12)'),
    (N'Baseline',                    N'Record filed as the in-service baseline (step 13)'),
    (N'DrawingUpdate',               N'Drawings and documentation updated (step 14; the DRAWING_REVISION procedure, W4 placeholder / W5)')
) AS s ([RecordKindCode], [Name])
ON t.[RecordKindCode] = s.[RecordKindCode]
WHEN MATCHED AND t.[Name] <> s.[Name] THEN UPDATE SET [Name] = s.[Name], [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET THEN INSERT ([RecordKindCode], [Name], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
    VALUES (s.[RecordKindCode], s.[Name], @actor, @now, @actor, @now);
GO
