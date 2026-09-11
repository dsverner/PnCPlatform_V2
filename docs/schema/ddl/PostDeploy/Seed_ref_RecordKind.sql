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
    (N'LayerMatchCandidate',         N'Proposed physical endpoint for a layer node, accepted by a person before it is applied (§13.1, 189)')
) AS s ([RecordKindCode], [Name])
ON t.[RecordKindCode] = s.[RecordKindCode]
WHEN MATCHED AND t.[Name] <> s.[Name] THEN UPDATE SET [Name] = s.[Name], [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET THEN INSERT ([RecordKindCode], [Name], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
    VALUES (s.[RecordKindCode], s.[Name], @actor, @now, @actor, @now);
GO
