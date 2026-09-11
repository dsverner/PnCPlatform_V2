# Formula language — reference implementation and conformance suite

Specification: `../FORMULA-GRAMMAR.md`. Grammar 1, 2026-09-05.

| File | What |
|---|---|
| `formula.py` | tokenizer, parser (text → canonical AST), printer, type/unit checker, three-valued evaluator, `upgrade()` from grammar 0, `parse_cadence()`. Stdlib only. |
| `test_formula.py` | the conformance suite on the reference: `python -m unittest docs/schema/grammar/test_formula.py` |
| `cases/catalogue.json` | the fixture fact catalogue (name → type, unit, base, parameters, allowed values) |
| `cases/fixture.json` | fact values per subject, an as-of history, host-bound names, the run instant |
| `cases/expressions.json` | text, expected canonical AST, expected type or authoring error, expected value |
| `cases/cadence.json` | cadence text, AST, due instant |
| `cases/grammar0.json` | grammar-0 payloads and their grammar-1 form |

**The C# port** is `src/PnC.Formula` (PLATFORM-ARCHITECTURE decision 206, built 2026-09-06); `dotnet run --project
src/PnC.Formula.Conformance` runs these cases through it (133 passed, including the regular-expression cases
the database interpreter cannot carry). The case files are the single source for every interpreter: this one is the oracle;
A case marked `"sql": "unsupported"` (regular expressions — `matches`, `decode`) records that the
retired T-SQL interpreter could not execute it. The marker is history now, kept so the cases read the
same as when they were written; the C# implementation runs all of them.

Regenerating the expected ASTs after a deliberate grammar change: edit the case texts, re-run the
generator in the session scratchpad or write the AST by hand, and review the diff — an expected
AST is a reviewed artefact, not a cache.

## The database interpreter, and why it is gone

There were two implementations of this grammar: `src/PnC.Formula` in the application and
`compliance.fEvalNode` in the database, and `db_conformance.py` ran these same cases through the second
so the two could be proved to agree. On 2026-09-10 the database interpreter was dropped
(`.planning/CALCULATION-ENGINE-DESIGN.md` §6): a calculation has to be able to open a relay's settings
file, and a T-SQL function cannot. With one implementation there is nothing to keep in step, so
`db_conformance.py` went with it. The suites that remain are `test_formula.py` on the Python reference
and `src/PnC.Formula.Conformance` on the implementation that actually runs.
