-- SCHEMA-DESIGN §10.6 (148) list. Extensible.
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
MERGE [ref].[FindingCategory] AS t
USING (VALUES
    (N'AsFoundDrift',         N'As-found drift'),
    (N'OutOfTolerance',       N'Out of tolerance'),
    (N'DrawingDiscrepancy',   N'Drawing discrepancy'),
    (N'WiringDiscrepancy',    N'Wiring discrepancy'),
    (N'SettingsDiscrepancy',  N'Settings discrepancy'),
    (N'ConsistencyMismatch',  N'Consistency mismatch'),
    (N'AuditFinding',         N'Audit finding'),
    (N'Observation',          N'Observation'),
    (N'MigrationReconciliation', N'Migration reconciliation')   -- W7 (#142): a legacy chain the letters and the numbers disagree on (#59)
) AS s ([FindingCategoryCode], [Name])
ON t.[FindingCategoryCode] = s.[FindingCategoryCode]
WHEN MATCHED AND t.[Name] <> s.[Name] THEN UPDATE SET [Name] = s.[Name], [ModifiedBy] = @actor, [ModifiedAt] = @now
WHEN NOT MATCHED BY TARGET THEN INSERT ([FindingCategoryCode], [Name], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
    VALUES (s.[FindingCategoryCode], s.[Name], @actor, @now, @actor, @now);
GO
