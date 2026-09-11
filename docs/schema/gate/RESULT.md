# Extensibility gate result — PASS

Run 2026-09-11T14:14:44-03:00 against `10.10.70.25` / `PnCPlatform_V2_GATE`  
Server: Microsoft SQL Server 2022 (RTM-CU26) (KB5093420) - 16.0.4265.3 (X64)  
Harness: `docs/schema/gate/run_gate.py`

SCHEMA-DESIGN §2.6, decision 77. Toy data; nothing here describes a real installation.

## Checks

- PASS catalogue after step 2 lists exactly the v1 characteristic and the formula
- PASS R1 preview scopes ['T1', 'T2', 'T4', 'T6']; got ['T1', 'T2', 'T4', 'T6']
- PASS R1 preview wrote exactly one RuleEvaluationRun row
- PASS interpreter refuses a rule naming a fact absent from the catalogue
- PASS 30-extend.sql contains no CREATE/ALTER/DROP
- PASS catalogue after step 4 lists the new characteristic with no other change
- PASS R2 preview scopes ['T1', 'T4']; got ['T1', 'T4']
- PASS object snapshot identical before step 4 and after step 5 (no table/view/function/procedure changed)
- PASS R1 re-run after step 4 still scopes the same subjects

## Fact catalogue

Before step 4:

| FactName | Source | DataType | Unit |
|---|---|---|---|
| `asset.formula.is_microprocessor` | Formula | Boolean |  |
| `asset.template.technology` | Characteristic | Enumeration |  |

After step 4:

| FactName | Source | DataType | Unit |
|---|---|---|---|
| `asset.formula.is_microprocessor` | Formula | Boolean |  |
| `asset.template.technology` | Characteristic | Enumeration |  |
| `asset.template.voltage_class_kv` | Characteristic | Decimal | kV |

## Fact values after step 4 (via `compliance.fFactValue`)

| Asset | `asset.formula.is_microprocessor` | `asset.template.technology` | `asset.template.voltage_class_kv` |
|---|---|---|---|
| T1 | true | Microprocessor | 138.0000000000 |
| T2 | true | Microprocessor | 69.0000000000 |
| T3 | false | Electromechanical | 138.0000000000 |
| T4 | true | Microprocessor | 230.0000000000 |
| T5 | false | Static | 345.0000000000 |
| T6 | true | Microprocessor | 69.0000000000 |

## Scoped subjects

- R1 (step 3): T1, T2, T4, T6
- R2 (step 5): T1, T4

## Object snapshot

- Objects compared: 98 before, 98 after
- Digest before step 4: `9710ad1948ddc01210f62309b627cba85d5082c7cab91c222c42329f50cdec9d`
- Digest after step 5:  `9710ad1948ddc01210f62309b627cba85d5082c7cab91c222c42329f50cdec9d`
- Identical: **yes**
