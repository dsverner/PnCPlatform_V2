-- The System actor used by seeds and by migration runs (CONVENTIONS.md). Fixed id.
IF NOT EXISTS (SELECT 1 FROM [personnel].[Actor] WHERE [ActorId] = '00000000-0000-0000-0000-000000000001')
    INSERT [personnel].[Actor] ([ActorId], [ActorKind], [SystemName])
    VALUES ('00000000-0000-0000-0000-000000000001', N'System', N'Platform.Seed');
GO
