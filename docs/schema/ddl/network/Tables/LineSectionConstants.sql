-- SCHEMA-DESIGN §13.2 (172). Class AppendOnly. The constants of one line section from one run:
-- Z1, Z0 (R/X) and B1, B0, per unit length and total. Mutual terms to other sections are the child
-- table network.LineSectionMutualConstants.
CREATE TABLE [network].[LineSectionConstants] (
    [LineSectionConstantsId]    BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_LineSectionConstants] PRIMARY KEY CLUSTERED,
    [RunId]                     UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LineSectionConstants_Run] REFERENCES [network].[ConstantsRun] ([RunId]),
    [LineSectionEntityId]       UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LineSectionConstants_Section] REFERENCES [network].[LineSectionRegistry] ([EntityId]),
    [Z1RPerKm]                  DECIMAL(18,8)     NULL,
    [Z1XPerKm]                  DECIMAL(18,8)     NULL,
    [Z0RPerKm]                  DECIMAL(18,8)     NULL,
    [Z0XPerKm]                  DECIMAL(18,8)     NULL,
    [B1PerKm]                   DECIMAL(18,8)     NULL,
    [B0PerKm]                   DECIMAL(18,8)     NULL,
    [Z1RTotal]                  DECIMAL(18,8)     NULL,
    [Z1XTotal]                  DECIMAL(18,8)     NULL,
    [Z0RTotal]                  DECIMAL(18,8)     NULL,
    [Z0XTotal]                  DECIMAL(18,8)     NULL,
    [B1Total]                   DECIMAL(18,8)     NULL,
    [B0Total]                   DECIMAL(18,8)     NULL,
    [InputHash]                 BINARY(32)        NOT NULL,
    CONSTRAINT [UQ_LineSectionConstants_RunSection] UNIQUE ([RunId], [LineSectionEntityId])
);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'network', @level1type = N'TABLE', @level1name = N'LineSectionConstants';
GO
