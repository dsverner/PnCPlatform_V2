-- Hand-written read model. SCHEMA-DESIGN §3; PLATFORM-ARCHITECTURE §3.4.
--
-- The functional-location tree as a screen needs it: every column of location.vNode plus HasChildren,
-- so a tree can draw an expand control only where there is something to expand.
--
-- Without it a lazy tree must draw an arrow on every node and discover on click whether anything is
-- there. On the migrated data that is wrong for almost everything: 724 nodes of 33,763 have children,
-- so 97 per cent of the arrows would do nothing. Reported from the QA screens, 2026-09-08.
--
-- The EXISTS is served by IX_Node_Parent and measures 0.05s across the whole tree, which is why this
-- is a view rather than a stored count that would have to be maintained.
CREATE VIEW [location].[vNodeTree] AS
SELECT n.[RowSeq],
       n.[RowId],
       n.[EntityId],
       n.[ValidFrom],
       n.[ValidTo],
       n.[NodeTypeCode],
       n.[ParentEntityId],
       n.[Path],
       n.[Depth],
       n.[SiblingOrder],
       n.[Name],
       n.[SubtypeCode],
       n.[RegionSplitOfEntityId],
       n.[Notes],
       HasChildren = CASE WHEN EXISTS (SELECT 1 FROM [location].[vNode] c WHERE c.[ParentEntityId] = n.[EntityId])
                          THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END
FROM [location].[vNode] n;
GO
GRANT SELECT ON [location].[vNodeTree] TO [app_execute];
GO
