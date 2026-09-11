-- SCHEMA-DESIGN §11.1 (152), §0.3 (72). Immutable; class AppendOnly.
-- The value every CreatedBy / ModifiedBy holds. Rows are created by personnel.ResolveActor and
-- never updated. PersonEntityId / ActingUserEntityId / DelegationEntityId reference tables of
-- step 11; the FKs are declared there (personnel.Person, security.User, security.Delegation)
-- (FKs added in step 11).
CREATE TABLE [personnel].[Actor] (
    [ActorId]             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [PK_Actor] PRIMARY KEY CLUSTERED,
    [PersonEntityId]      UNIQUEIDENTIFIER  NULL CONSTRAINT [FK_Actor_Person] REFERENCES [personnel].[PersonRegistry] ([EntityId]),   -- null only for ActorKind = System
    [ActingUserEntityId]  UNIQUEIDENTIFIER  NULL CONSTRAINT [FK_Actor_ActingUser] REFERENCES [security].[UserRegistry] ([EntityId]),   -- null for System
    [ActorKind]           NVARCHAR(20)      NOT NULL CONSTRAINT [CK_Actor_Kind] CHECK ([ActorKind] IN (N'Self', N'Delegated', N'Sponsored', N'System')),
    [DelegationEntityId]  UNIQUEIDENTIFIER  NULL CONSTRAINT [FK_Actor_Delegation] REFERENCES [security].[DelegationRegistry] ([EntityId]),
    [SystemName]          NVARCHAR(100)     NULL,          -- for System: the process or migration run
    [CreatedAt]           DATETIMEOFFSET(7) NOT NULL CONSTRAINT [DF_Actor_CreatedAt] DEFAULT SYSDATETIMEOFFSET(),
    CONSTRAINT [CK_Actor_SystemShape] CHECK (
        ([ActorKind] = N'System' AND [PersonEntityId] IS NULL AND [ActingUserEntityId] IS NULL AND [SystemName] IS NOT NULL)
     OR ([ActorKind] <> N'System' AND [PersonEntityId] IS NOT NULL)),
    CONSTRAINT [CK_Actor_DelegationShape] CHECK (
        ([ActorKind] = N'Delegated' AND [DelegationEntityId] IS NOT NULL)
     OR ([ActorKind] <> N'Delegated' AND [DelegationEntityId] IS NULL))
);
GO
-- one immutable row per distinct combination; ResolveActor reuses it
CREATE UNIQUE INDEX [UX_Actor_Combination]
    ON [personnel].[Actor] ([ActorKind], [PersonEntityId], [ActingUserEntityId], [DelegationEntityId], [SystemName]);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'personnel', @level1type = N'TABLE', @level1name = N'Actor';
GO
