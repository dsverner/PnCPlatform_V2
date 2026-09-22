-- SCHEMA-DESIGN §11.3 (154): PermissionCode = <SubjectClass>.<Verb>. Verbs are the vision's six (§3.4);
-- subject classes are those the design's paragraph names (its list ends with "…", so the
-- Administrator extends it). No role → permission mapping is seeded (none stated).
DECLARE @actor UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
DECLARE @classes TABLE ([SubjectClass] NVARCHAR(40), [Name] NVARCHAR(100));
INSERT @classes VALUES (N'Node', N'node'), (N'Asset', N'asset'), (N'Device', N'device'), (N'Scheme', N'scheme'), (N'Connection', N'connection'),
    (N'ConfigurationFile', N'configuration file'), (N'Document', N'document'), (N'WorkRequest', N'work request'), (N'Record', N'record'),
    (N'Obligation', N'obligation'), (N'Definition', N'definition'), (N'Grant', N'grant'),
    -- #226: what a person shows or hides on a screen. ViewItem.Modify is held by every role, because it only ever
    -- writes the caller's own row; ViewItem.Administer (a role's starting shape) stays the Administrator's.
    (N'ViewItem', N'screen item');
DECLARE @verbs TABLE ([Verb] NVARCHAR(20));
INSERT @verbs VALUES (N'Read'), (N'Modify'), (N'Approve'), (N'Archive'), (N'Report'), (N'Administer');
MERGE [security].[Permission] AS t
USING (SELECT c.[SubjectClass] + N'.' + v.[Verb] AS [PermissionCode], c.[SubjectClass], v.[Verb], v.[Verb] + N' ' + c.[Name] AS [Name]
       FROM @classes c CROSS JOIN @verbs v) AS s
ON t.[PermissionCode] = s.[PermissionCode]
WHEN NOT MATCHED BY TARGET THEN INSERT ([PermissionCode], [SubjectClass], [Verb], [Name], [CreatedBy], [CreatedAt], [ModifiedBy], [ModifiedAt])
    VALUES (s.[PermissionCode], s.[SubjectClass], s.[Verb], s.[Name], @actor, @now, @actor, @now);
GO
