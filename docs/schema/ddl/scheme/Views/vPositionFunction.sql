-- #181 (2026-09-17): the elements in service at a device position, named honestly.
--
-- scheme.CommissionedFunction is "one row per enabled element", and since #181 the node it names is the DEVICE
-- POSITION rather than a protection-function node under it (the owner: "the device FLOC should stop at
-- TN-4134-BDG1-PNL12-21A"; and, asked what to do with the old nodes, "repoint them"). The column keeps its old name
-- because renaming a column on a system-versioned table has no precedent in this repository and the 3 103 rows in it
-- are the migrated estate; this view is where a screen reads it, so nothing above the database has to know.
--
-- It joins ref.AnsiFunction for the name a person reads -- "21 Distance relay", not a bare number. Thirteen codes carry
-- a real C37.2 name (Seed_ref_AnsiFunction_Core); for any other the name IS the code, which the join reports as it
-- stands rather than hiding.
--
-- Both sides are read in the current-row form the filtered indexes use (#169), so a position's elements are one seek
-- of UX_CommissionedFunction and one of the AnsiFunction primary key.
CREATE VIEW [scheme].[vPositionFunction]
AS
SELECT cf.[EntityId],
       cf.[RowId],
       cf.[ProtectionFunctionNodeEntityId] AS [PositionNodeEntityId],
       cf.[AnsiCode],
       a.[Name]                            AS [AnsiName],
       a.[Category]                        AS [AnsiCategory],
       a.[IsDeviceNumber],   -- #182: 1 = a C37.2 device number; 0 = the manufacturer's own abbreviation, read the name
       cf.[IsPrincipal],
       cf.[LogicalNodeEntityId],
       cf.[EnabledFromConfigurationFileRevisionRowId],
       lr.[LoadResponsive],        -- #197: PRC-023-6 Attachment A, read through ref.fAnsiLoadResponsive (a legacy string such as 50/51N is judged by its numbers)
       lr.[LoadResponsiveBasis],
       lr.[BaseCodes],
       lr.[NeedsCurrent],          -- #206: the analog inputs the element needs (ref.AnsiFunction.AnalogInputs over the same base codes); NULL when no part is ruled
       lr.[NeedsVoltage],
       lr.[NeedsSyncVoltage],
       lr.[AnalogInputsBasis],
       cf.[ValidFrom],
       cf.[ValidFromQuality],
       cf.[CreatedBy],
       cf.[CreatedAt],
       cf.[ModifiedBy],
       cf.[ModifiedAt]
FROM [scheme].[CommissionedFunction] cf
LEFT JOIN [ref].[AnsiFunction] a ON a.[AnsiCode] = cf.[AnsiCode]
CROSS APPLY [ref].[fAnsiLoadResponsive](cf.[AnsiCode]) lr
WHERE cf.[ValidTo] IS NULL AND cf.[IsDeleted] = 0;
GO
GRANT SELECT ON [scheme].[vPositionFunction] TO [app_execute];
GO
