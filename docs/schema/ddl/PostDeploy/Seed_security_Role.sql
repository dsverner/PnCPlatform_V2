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
    (N'Assignee',                    N'Assigned to a Work Request (assignment role, §9.7)', N'Assignment'),
    -- V2 W2 (decision #66; docs/design/IDENTITY.md §3): one engineer role scoped per person, one technician role,
    -- the approver as a separate grant. The predecessor's account-type roles above are deactivated below.
    (N'PCEngineer',                  N'P&C Engineer (scoped per person by division)', NULL),
    (N'PCTechnician',                N'P&C Technician',                       NULL),
    (N'PCApprover',                  N'P&C Approver (a separate grant)',      NULL)
) AS s ([RoleCode], [Name], [RoleKind])
ON t.[RoleCode] = s.[RoleCode]
WHEN MATCHED AND (t.[Name] <> s.[Name] OR ISNULL(t.[RoleKind], N'') <> ISNULL(s.[RoleKind], N''))
    THEN UPDATE SET [Name] = s.[Name], [RoleKind] = s.[RoleKind], [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET THEN INSERT ([RoleCode], [Name], [RoleKind], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
    VALUES (s.[RoleCode], s.[Name], s.[RoleKind], @actor, @now, @actor, @now);
GO
-- V2 W2 (decision #66): only Administrator, ReadOnly, PCEngineer, PCTechnician, PCApprover are account types;
-- Assignee and PlacementOverride are schema mechanics and stay. The predecessor's fourteen are deactivated —
-- soft, idempotent, reversible by a row. The MERGE above never reactivates them.
IF OBJECT_ID(N'[security].[Role_Deactivate]') IS NOT NULL
BEGIN
    DECLARE @sys UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001', @rc NVARCHAR(40);
    DECLARE rc CURSOR LOCAL FAST_FORWARD FOR
        SELECT [RoleCode] FROM [security].[Role] WHERE [IsActive] = 1 AND [RoleCode] IN
            (N'Manager', N'ComplianceOfficer', N'TransmissionPncEngineer', N'DistributionPncEngineer', N'HydroGenerationEngineer',
             N'BelleduneGenerationEngineer', N'ColesonGenerationEngineer', N'PncTechnician', N'Approver', N'SystemOperator',
             N'TelecomEngineer', N'TelecomTechnician', N'AssetHealth', N'ManagementViewer', N'Reviewer');
    OPEN rc; FETCH NEXT FROM rc INTO @rc;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC [security].[Role_Deactivate] @RoleCode = @rc, @ActorId = @sys;
        FETCH NEXT FROM rc INTO @rc;
    END
    CLOSE rc; DEALLOCATE rc;
END
GO
