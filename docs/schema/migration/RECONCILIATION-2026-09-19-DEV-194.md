# Reconciliation — rule #194 applied to the DEV copy — 2026-09-19

The eight legacy classification columns (CLASS, USE, RESPONSIBILITY, Bulk_Power_Element, Protection_Group, ELEMENT, LINE_TYPE,
NUMBER OF RELAYS) are dropped at cutover (owner, 2026-09-19: untrusted). The importer no longer writes them into a migrated
record's summary (`legacy_import.py`, rule counted per row). The DEV copy, imported before the rule, was brought to the same
state by stripping those `KEY=value` segments from the summaries, attributed to the system actor:

| Rule | Rows |
|---|---:|
| legacy classification columns: dropped — untrusted (#194) — segments stripped from record.Record.Summary on DEV | 11,561 |
| summaries still carrying `CLASS=` afterwards | 0 |

The CT/PT ratio segments stay (real data; the template's inputs use them). The real cutover re-imports and never needs this step.
