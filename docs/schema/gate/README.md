# Extensibility gate — toy

Proves the property SCHEMA-DESIGN §2.6 (decision 77) requires before any domain DDL: a new
template characteristic flagged `IsCatalogueFact` becomes rule-addressable with **no change to
any table, view, function or procedure** — only rows. Result: [`RESULT.md`](RESULT.md).

## Files

| File | Gate step | Content |
|---|---|---|
| `00-schema.sql` | 1 | `ref.*`, `personnel.Actor`, `config.Definition` / `DefinitionVersion` / `CharacteristicDefinition`, `asset.Asset` / `CharacteristicValue`, `compliance.RuleEvaluationRun`, current views, `compliance.vFactCatalogue`, the interpreter, write procedures |
| `10-seed.sql` | 2 | template v1 with `technology` (catalogue fact); formula `is_microprocessor` derived from it; rule R1 over the formula |
| `20-preview-r1.sql` | 3 | R1 preview → T1, T2, T4, T6 |
| `30-extend.sql` | 4 | **rows only**: template v2 adds `voltage_class_kv` (catalogue fact); values; rule R2 over both facts |
| `40-preview-r2.sql` | 5 | R2 preview → T1, T4 |
| `run_gate.py` | — | drops and recreates the database, runs the files, asserts the sets, snapshots every object before step 4 and after step 5 and requires the snapshots to be identical, writes `RESULT.md` |

Run: `python docs/schema/gate/run_gate.py [--server 10.10.70.25] [--database PnCPlatform_GATE]`.
The default database is `PnCPlatform_GATE` (the harness drops and recreates it; `PnCPlatform_DEV` now holds the DDL project). Password from `dev.local` (`PNC_DEV_PWD=`) or the environment variable of the same name. Needs
`pyodbc` and ODBC Driver 17. The login needs `dbcreator`.

## What "no change outside the rows" means here

Three independent checks:

1. `30-extend.sql` contains no `CREATE`, `ALTER` or `DROP` (regex over the file).
2. A snapshot of `sys.objects` + `sys.columns` + `sys.indexes` + SHA-256 of every
   `sys.sql_modules.definition`, taken before step 4 and after step 5, is byte-identical.
3. R2 names `asset.template.voltage_class_kv`, a fact that did not exist at step 1, and scopes
   correctly; R1 still scopes the same subjects after the template revision.

## Faithful to the design

- §0.3 base columns on every fact table: `RowSeq` clustered identity, `RowId` (fact version),
  `EntityId` + registry table, valid time on `ValidTime` tables, system versioning with hidden
  period columns and history tables, actor-referenced audit columns, soft delete, `MigrationRunId`.
- `PnC.TemporalClass` extended property on every table (decision 69).
- §2.1–2.2: definition / version with `Status`, effective period, approver, `PayloadText` (programs
  only, decision 78) and `PayloadHash` (SHA-256). A new effective version retires the prior one.
- §2.4: typed `CharacteristicValue` with exactly one non-null value column (CHECK), governed by a
  `CharacteristicDefinition` carrying type, unit, base, enumeration values and `IsCatalogueFact`.
- §12.3: `compliance.vFactCatalogue` is a view over definition rows; the interpreter reads only what
  it lists and refuses a program naming anything else (checked at authoring time and at run time).
- §12.4: a preview run writes the run row and nothing else.
- Segregation on approval: approver must differ from author (§2.2), enforced in the procedure.

## Deviations (toy simplifications — none affect what the gate tests)

| Design | Toy | Why |
|---|---|---|
| Views generated from `PnC.TemporalClass` (decision 69) | hand-written `v<Table>` current views | the generator is DDL-project work |
| `config.DefinitionAppliesTo` + resolver (§2.3) | `asset.Asset.TemplateDefinitionEntityId` stored | the resolver is not under test |
| `asset.AlternateKey` designation (§0.4) | `asset.Asset.Name` | |
| `AllowedValuesDefinitionRowId` → enumeration definition | inline `AllowedValuesJson` | |
| Actor resolved from the session (step 11) | `@actorId` parameter | |
| Formula language (vision §13.3) | JSON predicate tree: `{"fact","op","value"}`, `all` / `any` / `not`; numeric compare when both sides parse as decimal, else text | grammar is a separate design item; the gate addresses facts by catalogue name only, which any grammar must do |
| Rule literals carry units (§0.3) | literal assumed in the fact's definition unit | |
| `Draft → Approved → Effective` | `Draft → Effective` in one approval | |
| Gate result cited as a `record.*` `ParityTest` | `RESULT.md` in the repo | `record.*` does not exist yet; cite it when it does |

## One finding for the design

**Characteristic values across template versions.** Values entered under template v1's
`technology` reference v1's `CharacteristicDefinition.RowId`. When v2 becomes effective, those
rows are not re-entered. The toy resolves a fact by `(template definition entity, characteristic
key)` across versions so they remain addressable, and R1 scopes identically after the revision.
SCHEMA-DESIGN §2.4 does not say whether a template revision carries values forward, re-validates
them against the new definition, or requires re-entry. Recorded for step 2's open list; it does
not affect the gate's property.
