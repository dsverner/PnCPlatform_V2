-- SCHEMA-DESIGN §13.1 (188), §13.2 (172). Class AppendOnly. The engine's roll-up of LineSectionConstants along
-- a layer branch's derived path, per constants run: length and total sequence impedances, reproducible from
-- the run and InputHash. Status / FailureReason as the run reports them (TLM BranchCalculationResults shape).
CREATE TABLE [network].[LayerBranchConstants] (
    [LayerBranchConstantsId] BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_LayerBranchConstants] PRIMARY KEY CLUSTERED,
    [RunId]                 UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LayerBranchConstants_Run] REFERENCES [network].[ConstantsRun] ([RunId]),
    [LayerBranchEntityId]   UNIQUEIDENTIFIER  NOT NULL CONSTRAINT [FK_LayerBranchConstants_Branch] REFERENCES [network].[LayerBranchRegistry] ([EntityId]),
    [LengthKm]              DECIMAL(18,4)     NULL,
    [Z1RTotal]              DECIMAL(18,8)     NULL,
    [Z1XTotal]              DECIMAL(18,8)     NULL,
    [Z0RTotal]              DECIMAL(18,8)     NULL,
    [Z0XTotal]              DECIMAL(18,8)     NULL,
    [InputHash]             BINARY(32)        NOT NULL,
    [Status]                NVARCHAR(20)      NULL,
    [FailureReason]         NVARCHAR(1000)    NULL,
    CONSTRAINT [UQ_LayerBranchConstants_RunBranch] UNIQUE ([RunId], [LayerBranchEntityId])
);
GO
EXEC sys.sp_addextendedproperty @name = N'PnC.TemporalClass', @value = N'AppendOnly',
    @level0type = N'SCHEMA', @level0name = N'network', @level1type = N'TABLE', @level1name = N'LayerBranchConstants';
GO
