-- SCHEMA-DESIGN §13.2 (172). Class AppendOnly. Zero-sequence mutual terms from one section's
-- constants row to another section (the "child" the design names).
CREATE TABLE [network].[LineSectionMutualConstants] (
    [LineSectionMutualConstantsId] BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_LineSectionMutualConstants] PRIMARY KEY CLUSTERED,
    [LineSectionConstantsId]    BIGINT            NOT NULL CONSTRAINT [FK_LineSectionMutualConstants_Parent] REFERENCES [network].[LineSectionConstants] ([LineSectionConstantsId]),
    [MutualsToSectionEntityId]  UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LineSectionMutualConstants_Section] REFERENCES [network].[LineSectionRegistry] ([EntityId]),
    [Z0mR]                      DECIMAL(18,8)     NULL,
    [Z0mX]                      DECIMAL(18,8)     NULL,
    CONSTRAINT [UQ_LineSectionMutualConstants] UNIQUE ([LineSectionConstantsId], [MutualsToSectionEntityId])
);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'network', @level1type = N'TABLE', @level1name = N'LineSectionMutualConstants';
GO
