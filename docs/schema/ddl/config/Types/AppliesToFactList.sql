-- The subject's facts, one row per dimension, as the caller of config.ResolveDefinition
-- gathers them (a device's manufacturer, model, firmware; a scheme's type; …).
CREATE TYPE [config].[AppliesToFactList] AS TABLE (
    [DimensionCode] NVARCHAR(40)     NOT NULL,
    [ValueEntityId] UNIQUEIDENTIFIER NULL,
    [ValueCode]     NVARCHAR(100)    NULL
);
GO
