-- Hand-written read model. SCHEMA-DESIGN §5; PLATFORM-ARCHITECTURE §2.3, §3.4.
--
-- Devices that are not linked to a catalogue model, grouped by the model token in their name.
--
-- Why this exists: `device.technology` is the second thing a PRC-005 rule scope tests — P1 is a
-- microprocessor relay and P2 an electromechanical one — and on 2026-09-09 it was Unknown for 8,920
-- of 11,475 devices. That is not a missing column. Every one of the 52 models in `ref.Model` carries
-- a technology; the devices simply have no `ModelId`, because the legacy register recorded a free-text
-- description rather than a model code.
--
-- So this is a model-catalogue exercise, not a backfill: 1,432 distinct tokens with nothing in the
-- catalogue to link most of them to. This view makes the size and the shape of that work visible, and
-- orders it by how many devices each token would settle, so the first hundred entries are worth far
-- more than the last hundred.
--
-- The token is the part of the migrated name before the em dash that separates the device description
-- from the equipment it protects — 'CO-9 2.5-10 A INST=20-80 A — UNIT 1 SS TRANSFORMERS'. It still
-- carries setting ranges, because the old register kept them in the same string; reducing a token to a
-- model is the judgement a person makes, and this view deliberately does not attempt it.
CREATE VIEW [device].[vUnmatchedModelToken] AS
WITH [Unlinked] AS (
    SELECT a.[Name],
           LTRIM(RTRIM(LEFT(a.[Name], CHARINDEX(NCHAR(8212), a.[Name] + NCHAR(8212)) - 1))) AS [Token]
    FROM [device].[vDevice] d
    JOIN [asset].[vAsset] a ON a.[EntityId] = d.[EntityId]
    WHERE a.[ModelId] IS NULL
)
SELECT [Token],
       COUNT(*)                    AS [Devices],
       MIN([Name])                 AS [ExampleName]
FROM [Unlinked]
WHERE [Token] <> N''
GROUP BY [Token];
GO
GRANT SELECT ON [device].[vUnmatchedModelToken] TO [app_execute];
GO
