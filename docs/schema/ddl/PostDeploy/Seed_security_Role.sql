-- SCHEMA-DESIGN §11.3 (154): vision §3.2 roles plus the predecessor's, as named. RoleKind is stated only
-- for Administrator (Positional, §11.4); every other kind is left null for the owner to classify (STEPS.md).
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [security].[Role] AS t
USING (VALUES
    (N'Administrator',               N'Administrator',                        N'Positional'),
    (N'Manager',                     N'Manager / P&C Supervisor',             NULL),
    (N'ReadOnly',                    N'Read-only',                            NULL),
    (N'ComplianceOfficer',           N'Compliance Officer',                   NULL),
    (N'TransmissionPncEngineer',     N'Transmission P&C Engineer',            NULL),
    (N'DistributionPncEngineer',     N'Distribution P&C Engineer',            NULL),
    (N'HydroGenerationEngineer',     N'Hydro Generation Engineer',            NULL),
    (N'BelleduneGenerationEngineer', N'Belledune Generation Engineer',        NULL),
    (N'ColesonGenerationEngineer',   N'Coleson Generation Engineer',          NULL),
    (N'PncTechnician',               N'P&C Technician',                       NULL),
    (N'Approver',                    N'Approver',                             NULL),
    (N'SystemOperator',              N'System Operator (predecessor)',        NULL),
    (N'TelecomEngineer',             N'Telecom Engineer (predecessor)',       NULL),
    (N'TelecomTechnician',           N'Telecom Technician (predecessor)',     NULL),
    (N'AssetHealth',                 N'Asset Health (predecessor)',           NULL),
    (N'ManagementViewer',            N'Management Viewer (predecessor)',      NULL),
    (N'Reviewer',                    N'Reviewer (predecessor)',               NULL),
    (N'PlacementOverride',           N'Placement override (device category vs position subtype, §5.7)', NULL),
    (N'Assignee',                    N'Assigned to a Work Request (assignment role, §9.7)', N'Assignment')
) AS s ([RoleCode], [Name], [RoleKind])
ON t.[RoleCode] = s.[RoleCode]
WHEN MATCHED AND (t.[Name] <> s.[Name] OR ISNULL(t.[RoleKind], N'') <> ISNULL(s.[RoleKind], N''))
    THEN UPDATE SET [Name] = s.[Name], [RoleKind] = s.[RoleKind], [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET THEN INSERT ([RoleCode], [Name], [RoleKind], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
    VALUES (s.[RoleCode], s.[Name], s.[RoleKind], @actor, @now, @actor, @now);
GO
