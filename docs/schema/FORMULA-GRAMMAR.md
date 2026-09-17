# PnCPlatform — the formula expression language

Design item from vision §7.7 / §13.3 ("formula expression language specification") and
SCHEMA-DESIGN §2.10. Written 2026-09-05. Reference implementation and conformance cases in
`docs/schema/grammar/`; database interpreter in `docs/schema/ddl/compliance/Functions/fEvalNode.sql`.

Status: **grammar 1**. Grammar 0 is the extensibility gate's JSON predicate tree
(`docs/schema/gate`, `compliance.fEvaluate` as built 2026-09-04); it remains readable and maps
one-to-one into grammar 1 (§9).

---

## 0. Contract

The schema (SCHEMA-DESIGN §2.7) fixes three constraints; this document adds the fourth:

1. An expression references only facts in `compliance.vFactCatalogue` (§12.3). An unknown name is
   an authoring error, never a run-time one.
2. Every numeric term carries a **dimension, a unit and a base** (`Primary`, `Secondary`,
   `PerUnit`, or none). Arithmetic is checked for dimension at authoring; a literal compared or
   combined with a dimensioned term must state its unit.
3. Evaluation is **deterministic and side-effect free**: no clock, no random, no I/O; the only
   instant is the run's `@at`. The stored canonical form is what `PayloadHash` hashes, so a hash
   plus the fact versions read (`compliance.ObligationInstanceFact`) reproduces a result.
4. A run **never throws on data**. A missing fact, a failed conversion, a division by zero yield
   `Unknown`, which propagates and is recorded. A conclusion is `true`, `false` or `Unknown`;
   an `Unknown` scope result is *not in scope, indeterminate*, and is reported as such.

Why the fourth: the PSA line-constants predecessor let a zero bundle separation fall through to a
zero GMR and computed with it for months (its "Bundle-GMD-systematic" category, 169 sections);
`fEvaluate` grammar 0 treated a missing value as `false`. A formula that produces a conclusion
about protection adequacy (vision §5.8) must say when it could not conclude.

## 1. Two forms, one meaning

- **Text form** — what a person writes and reads in the application:
  `device.settings.50P1P > 1.5 A@Secondary and device.technology = 'Microprocessor'`
- **Canonical form** — a JSON abstract syntax tree (`{"g":1, ...}`, §8) that `PayloadText`,
  `ValidationExpression`, `LimitExpression` and `ConversionExpression` store and that both
  interpreters execute.

The parser is total on well-formed text and the printer is its inverse (`print(parse(t))` is a
normalised `t`; `parse(print(a)) = a`), so a version diff is readable as text while the hash is
over the canonical form. Whitespace, comments (`-- to end of line`) and parenthesisation that the
precedence rules make redundant do not change the canonical form.

## 2. Lexical elements

| Token | Form | Notes |
|---|---|---|
| number | `12`, `1.5`, `.25`, `1e-3` | decimal; stored as a decimal string, never a float |
| unit suffix | number followed by a unit code: `100 A`, `1.5A`, `13.8 kV`, `50 %`, `1.2 pu`, `0.5 Ω`, `-40 °C` | unit codes are `ref.Unit.UnitCode` verbatim, including `Ω`, `°C`, `%`, `ohm/mi`; a code containing `/` or `·` is written as is |
| base suffix | `@Primary`, `@Secondary`, `@PerUnit` after a unit: `2.5 A@Secondary` | numeric only |
| duration | number + `y` `mo` `w` `d` `h`: `6 y`, `18 mo`, `30 d`, `4 h` | a Duration is not a Number; a Number of dimension Time (`150 ms`, `5 min`, `30 s`) is accepted wherever a Duration is expected and converts exactly through seconds |
| text | `'single quoted'`, doubled quote to escape `''` | |
| boolean | `true`, `false` | |
| datetime | `2026-09-05`, `2026-09-05T14:30`, `2026-09-05T14:30:00-03:00` | ISO 8601; a date without offset is the platform's configured offset at authoring, stored with the offset |
| name | `device.settings.50P1P`, `scheme.members`, `station.classification.BesStatus`, `device.settings.Z3%` | dotted; a segment may start with a digit after the first dot (setting codes like `50P1P`); may end in `%` directly attached, which belongs to the name (setting codes like `Z1%`, `Z2%`, `Z3%`); case-sensitive |
| parameters | `name[key='text', key2=12]` | after a fact name; keys are bare names, values literals |
| variable | `x`, `value`, `$` | bound by `any`/`all`/`select` or by the host (§7) |
| keywords | `and or not in like matches is unknown at every from within of once calendar_year calendar_quarter calendar_month` | case-insensitive |
| operators | `= <> < <= > >= + - * / ^ ( ) , { } [ ] -> .` | |
| comment | `-- …` to end of line | dropped from the canonical form |

## 3. Types

| Type | Written | Canonical `t` | Notes |
|---|---|---|---|
| Boolean | `true` | `bool` | three-valued at evaluation: `true`, `false`, `Unknown` |
| Number | `1.5 A@Secondary` | `num` with `u` (unit code), `b` (base) | dimension comes from the unit through `ref.Unit.Dimension`; no unit = dimensionless |
| Text | `'A'` | `text` | ordinal comparison, case-sensitive; `like` and `matches` for patterns |
| Enumeration | `'Microprocessor'` | `text` | an enumeration fact compares to a text literal; the checker verifies the literal is an allowed value when the definition lists them |
| DateTime | `2026-09-05T00:00-03:00` | `date` | always with offset; ordered |
| Duration | `6 y` | `dur` with `u` in `y mo w d h` | calendar-aware for `y` and `mo` (add by calendar), exact for the rest; a Time-dimension Number serves as an exact duration |
| Reference | (facts only) | `ref` with `kind` | an entity id and its subject kind; equality only; the subject for a path step |
| Set | `{1 A, 2 A}` or a set-valued fact | `set` of one element type | order-free, duplicates kept; empty set is a value, not Unknown |
| Unknown | `unknown` (literal, rare) | — | the absence of a value; see §5 |

There is **no implicit coercion**. Text is never compared as a number, a number never as text.
Grammar 0's "numeric when both sides parse" rule is withdrawn (§9).

## 4. Expressions

### 4.1 Precedence (low to high)

```
or
and
not
= <> < <= > >= in like matches is
+ -
* /
unary -
^ (right-associative)
postfix: [params] .step at(...)
```

### 4.2 Facts and paths

```
fact        := name params? step* asof?
params      := '[' param (',' param)* ']'          param := name '=' literal
step        := '.' name params?                    -- a relation step; yields a Set
asof        := 'at' '(' expr ')'                   -- a DateTime expression; default is the run's @at
```

- `device.settings.50P1P` — a fact of the run's subject.
- `scheme.members[role='Relay']` — a parameterised fact; parameters are named, typed and
  listed per fact in the catalogue (`Parameters`); an unlisted parameter is an authoring error.
- `scheme.members[role='Relay'].device.settings.50P1P` — a **path**: the set-valued fact gives
  subjects; the following full fact name is read for each; the result is a Set. A path through a
  single-valued Reference fact (`record.last[…].record.occurred_at`) yields a single value.
- `device.settings.50P1P at (@at - 1 y)` — the fact as it stood one year before the run's instant.
  `@at` is the only clock; `now()` does not exist.
- `device.settings.Z3%` — a name may **end in `%`** when the `%` is attached with no space, because
  catalogue fact names do (the SEL-221F zone reaches are `Z1%`, `Z2%`, `Z3%`). The `%` stays inside
  the last segment of the name. After a *number* `%` is still the unit (`150 %` is a Ratio), and a
  `%` with a space before it is still the unit; only a name it touches absorbs it.

### 4.3 Comparison

`=`, `<>` on any type with itself; `< <= > >=` on Number (same dimension; converted to the left
operand's unit), DateTime, Duration, Text (ordinal). `in` tests membership of a Set. `like` is
SQL `LIKE` (`%`, `_`); `matches` is a regular expression in the .NET/PCRE common subset (no
look-behind, no backreferences — both interpreters must agree). `x is unknown` is the only test
that is never Unknown.

### 4.4 Arithmetic and units

| Operation | Rule |
|---|---|
| `a + b`, `a - b` | same dimension; result in `a`'s unit; base must be equal or one side base-less |
| `a * b`, `a / b` | dimensions combine (`A * Ω → V`, `V / A → Ω`, `VA / V → A`, `x / x → dimensionless`); the checker derives the result dimension from the table in §4.5 and refuses a product it cannot name; units of the result are the base units of that dimension |
| `a ^ n` | `n` a dimensionless literal integer; dimension only for `n` ∈ {−1, 1, 2} of Length or Ratio; otherwise `a` must be dimensionless |
| unary `-` | any Number |
| `number * duration`, `duration / number` | Duration |
| `date + duration`, `date - duration`, `date - date → duration` | calendar arithmetic for `y`/`mo` |

Division by zero, overflow and conversion failure yield Unknown.

### 4.5 Dimensions

`ref.Unit.Dimension` values: Voltage, Current, Power, ReactivePower, ApparentPower, Energy,
Charge, Impedance, Time, Frequency, Length, Temperature, Ratio, Angle, Other. Named products the
checker knows:

```
Voltage * Current = ApparentPower      Voltage / Current = Impedance
Current * Impedance = Voltage          Power / Voltage = Current
ApparentPower / Voltage = Current      Energy / Time = Power
Impedance / Length = Other (per-length impedance; unit as written, e.g. ohm/mi)
Length * Frequency = Other             X / X = Ratio (dimensionless)
Ratio * X = X                          X * Ratio = X          X / Ratio = X
```

`Ratio` is dimensionless; `pu` and `%` convert through `ratio`. `Other` never combines. Two
`Other` units are the same dimension only if the same unit code.

Because `Ratio` is dimensionless it **scales** rather than combines: `Ratio * X`, `X * Ratio` and
`X / Ratio` all keep `X`'s dimension, and the result is in that dimension's base unit like every
other product. `Ratio / Ratio` stays dimensionless (it is the `X / X` rule), and `Ratio / X` has no
named dimension. The value rule is the one the evaluator already applies to every product: **both
operands go to their base unit first**, so the Ratio operand is converted to `ratio` before
multiplying — `150 % * 10 Ω` is `15 Ω`, `1.5 ratio * 10 Ω` is `15 Ω`, `10 Ω / 50 %` is `20 Ω`, and
`13.8 kV * 150 %` is `20700 V` (base unit `V`, not `kV`). A dimensioned term multiplied by a
*dimensionless* number is the separate, older rule and keeps its own unit.

Bases: a `PerUnit` term combines with a `PerUnit` term; `Primary` with `Primary`; `Secondary`
with `Secondary`; a base-less term combines with any. `base(x, 'Primary', ratio)` converts a
Secondary current or voltage through the ratio the author names (a published characteristic such
as `device.template.ct_ratio`; Unknown when absent, never a guess); `to(x, 'kA')` converts within
a dimension through `ref.Unit.ToBaseFactor`.

### 4.6 Literals in context

A bare number is dimensionless. Comparing or combining it with a dimensioned term is an authoring
error (`missing_unit`), not an implicit adoption of the fact's unit — the STEPS.md step 12
allowance "a literal is assumed in the fact's definition unit" ends with this grammar. A duration
literal is only valid where a Duration is expected.

### 4.7 Sets and quantifiers

```
'{' expr (',' expr)* '}'                       -- a set literal
exists(set)   count(set)   sum(set)   avg(set)   min(set)   max(set)
any(set, x -> boolean)     all(set, x -> boolean)     select(set, x -> expr)   where(set, x -> boolean)
```

`any` over an empty set is `false`, `all` is `true`; an Unknown element makes `any` Unknown
unless another element is `true`, and `all` Unknown unless another is `false` (Kleene).
`sum`/`avg`/`min`/`max` over an empty set are Unknown; an Unknown element makes them Unknown.

### 4.8 Functions (closed list)

| Function | Signature | Unit rule |
|---|---|---|
| `abs(x)` | Number → Number | keeps |
| `round(x, n)`, `floor(x)`, `ceil(x)` | Number → Number | keeps; `n` dimensionless integer; `round` is half away from zero (T-SQL `ROUND`, C# `MidpointRounding.AwayFromZero`) |
| `hypot(a, b)` | Numbers of one dimension → Number | `a`'s unit; `b` is converted to it first; √(a² + b²) |
| `cos(x)`, `sin(x)` | Number (Angle, or dimensionless) → Number | dimensionless result; a dimensionless argument is taken as degrees; any other dimension is `dimension_mismatch` |
| `atan2(y, x)` | Numbers of one dimension → Number | result an Angle in `deg`, in (−180, 180]; `x` is converted to `y`'s unit first; both zero → Unknown |
| `min(a, b, …)`, `max(a, b, …)` | Numbers of one dimension, or Dates, or Durations | first operand's unit |
| `clamp(x, lo, hi)` | Numbers of one dimension | `x`'s unit |
| `coalesce(a, b, …)` | one type | first non-Unknown |
| `if(cond, a, b)` | Boolean, T, T → T | `cond` Unknown → Unknown |
| `to(x, 'unit')` | Number → Number | converts within the dimension |
| `base(x, 'Primary'\|'Secondary', ratio)` | Number, Text, Number → Number | multiplies (to Primary) or divides (to Secondary) by the dimensionless `ratio` the author names |
| `days_between(a, b)` | Date, Date → Number (dimensionless, days) | |
| `add(date, duration)` | Date → Date | same as `+` |
| `year(d)`, `month(d)`, `day(d)` | Date → Number | dimensionless |
| `len(t)`, `lower(t)`, `upper(t)`, `trim(t)`, `substr(t, start, len)` | Text | |
| `startswith(t, p)`, `endswith(t, p)`, `contains(t, p)` | Text, Text → Boolean | |
| `decode(pattern, t, group)` | regex with capture → Text | Unknown when no match |
| `map(x, {k: v, …}, default?)` | any → any | table lookup; no match → `default` or Unknown |
| `number(t)`, `text(x)` | explicit conversion | `number` fails → Unknown; the only text↔number path |

`hypot`, `cos`, `sin` and `atan2` are the reach geometry a PRC-023 loadability formula needs (#171,
2026-09-16). They are computed in IEEE-754 double and returned as a decimal, which carries fifteen
significant digits of that double — so `cos(60 deg)` is exactly `0.5`. An angle whose sine or cosine
is mathematically zero comes back as a value near `1e-16`, not `0`: compare such a result with a
tolerance, never with `= 0`. Every other function in this table is exact decimal arithmetic.
As with all functions, an Unknown argument makes the call Unknown.

Everything else is a `Program.Formula` that publishes a fact. There are no user-defined functions.

## 5. Unknown

- A fact the subject lacks, a parameter with no match, a failed conversion, a zero divisor and an
  `unknown` literal are Unknown.
- Arithmetic and comparison with an Unknown operand are Unknown.
- `and`/`or`/`not` follow Kleene: `false and U = false`, `true or U = true`, `not U = U`.
- `coalesce`, `is unknown` and `if` (when `cond` is known) are the ways out.
- A **rule** whose scope predicate is Unknown for a subject does not scope it and records the
  subject as *indeterminate* with the fact names that were Unknown; the preview lists them so an
  administrator sees missing data rather than silent exclusion.
- A **validation** (`ValidationExpression`, `LimitExpression`) that is Unknown **refuses the
  write** with the fact names that were Unknown: a value that cannot be validated is not accepted.
- A **formula** whose result is Unknown publishes Unknown; a rule reading it treats it as above.

## 6. Cadence

A sub-language used by `Program.ObligationRule.cadence`, read by `compliance.vObligationDue`
(PROCEDURES #22) and `compliance.Exception.ClockDueAt` (#23):

```
cadence := 'every' duration ('from' anchor)?                 -- interval: due = anchor + duration
         | 'every' ('calendar_year' | 'calendar_quarter' | 'calendar_month') ('offset' duration)?
         | 'within' duration 'of' 'event'                   -- clock from the triggering instant
         | 'once'                                           -- due at the rule's effective date
anchor  := fact                                              -- a DateTime-valued fact, e.g. record.last[kind='Maintenance', accepted=true].occurred_at
         | 'effective'                                       -- the rule version's EffectiveFrom
```

Due for an open instance is the anchor instant plus the duration; when the anchor is Unknown
(no satisfying record ever) the due is the rule's `EffectiveFrom` plus the duration, and the
instance carries `AnchorUnknown` so the report says why. A `calendar_*` cadence is due at the
period end plus the offset. `within … of event` yields a due only when the instance was opened
by an event (an exception clock).

## 7. Host shapes — where expressions live

Each host embeds AST nodes under fixed keys; the host validates the expression's result type.

| Host | Shape | Bound names | Result |
|---|---|---|---|
| `Program.ObligationRule` | `{"g":1,"requirement":"<Requirement EntityId>" \| {"standard","version","number","sub"},"subjectKinds":[…],"scope":expr,"cadence":cadence,"evidence":{"recordKinds":[…],"minAcceptance":"Accepted"\|null},"workType":key?,"leadTime":dur?,"responsibleRole":code?}` — the requirement must resolve at authoring; `evidence` names the satisfying record; `workType` + `leadTime` let the run raise work (PROCEDURES #22) | — (subject implicit) | scope: Boolean; cadence: DateTime (the due instant) |
| `Program.Formula` | `{"g":1,"inputs":[fact names],"expression":expr,"publishes":{"fact":"asset.formula.<key>","type":"num","unit":"A","base":"Secondary","precision":3}}` | — | the declared type; the checker proves the expression yields it. `inputs` is redundant with the expression and must equal its fact set (a declaration the reviewer reads — lifted from pnc-platform's rule) |
| `Program.ClassificationDerivation` | `{"g":1,"kind":"BesStatus","subjectKinds":[…],"cases":[{"when":expr,"value":"BES"}],"else":value}` | — | first `when` that is `true`; all Unknown → Unknown, not `else` |
| `Program.QualificationRequirement` | `{"g":1,"requires":expr}` over `person.*` facts | — | Boolean |
| `Program.NotificationType` | `{"g":1,"trigger":{"on":"RecordAccepted","when":expr},"escalation":[{"after":dur,"role":code}],"template":key}` | `event.*` facts of the trigger | Boolean |
| `Program.SegregationRule` | unchanged (`{"rules":[…]}`, no expressions) | | |
| `CharacteristicDefinition.ValidationExpression` | expr | `value` (the value being written, in the definition's unit and base), plus the host's facts | Boolean; Unknown refuses |
| `TestPlanReading.LimitExpression` | expr | `value`, `base` (the `Base` column), `nominal` | Boolean |
| `TransformMapping.ConversionExpression` | expr | `$` (the source token as Text), `$name` (another mapping's parsed value by TargetKey) | the target's type |
| Layer matching (`Transform.Import` rows, PROCEDURES #40) | `{"g":1,"candidates":expr yielding a Set of Reference,"score":expr over c,"acceptAt":num}` | `node`, `c` (the candidate) | score: Number dimensionless |

The **Program.Workflow**, **WorkType**, **SchemeType**, **TestPlan**, **ReportDefinition**,
**BackupPolicy**, **CleansingRules** payloads keep their own structured JSON; where they hold a
condition (a workflow transition guard, a report filter, a cleansing predicate) it is an AST
node under `"when"`.

## 8. Canonical form (grammar 1)

Every node is a JSON object. `"g":1` appears once at the root of a stored payload.

| Node | Shape |
|---|---|
| literal | `{"lit":"1.5","t":"num","u":"A","b":"Secondary"}` · `{"lit":"x","t":"text"}` · `{"lit":true,"t":"bool"}` · `{"lit":"2026-09-05T00:00:00-03:00","t":"date"}` · `{"lit":"6","t":"dur","u":"y"}` · `{"lit":null}` (unknown) |
| fact | `{"fact":"scheme.members","p":{"role":{"lit":"Relay","t":"text"}}}` · with path: `{"fact":"device.settings.50P1P","from":<fact node>}` · as-of: `"at":<expr>` |
| variable | `{"var":"value"}` (`$` is `{"var":"$"}`) |
| logical | `{"op":"and","a":[…]}` · `{"op":"or","a":[…]}` · `{"op":"not","x":…}` — `and`/`or` are flattened n-ary |
| binary | `{"op":"=","l":…,"r":…}` for `= <> < <= > >= in like matches + - * / ^` |
| unary minus | `{"op":"neg","x":…}` |
| is unknown | `{"op":"isunknown","x":…}` |
| set | `{"set":[…]}` |
| call | `{"fn":"round","a":[…]}` |
| quantifier | `{"fn":"any","a":[<set>],"var":"x","body":…}` (also `all`, `select`, `where`) |
| cadence | `{"cadence":"interval","every":<dur lit>,"from":<fact>|"effective"}` · `{"cadence":"calendar","period":"year","offset":<dur lit>?}` · `{"cadence":"event","within":<dur lit>}` · `{"cadence":"once"}` |

Numbers are decimal strings; key order is fixed as listed; no whitespace outside strings. The
hash is SHA-256 over this UTF-8 text (`config.AddDefinitionVersion` already hashes `PayloadText`;
the parser guarantees canonical text so equal meaning gives an equal hash).

## 9. Grammar 0 compatibility

The gate's tree is accepted wherever grammar 1 is, by `upgrade()`:

| Grammar 0 | Grammar 1 |
|---|---|
| `{"fact":F,"op":"=","value":V}` | `{"op":"=","l":{"fact":F},"r":<literal from V: bool→bool, number→num without unit, string→text>}` |
| `"op":"in"` with array | `{"op":"in","l":…,"r":{"set":[…]}}` |
| `{"all":[…]}` / `{"any":[…]}` / `{"not":X}` | `and` / `or` / `not` |
| `predicate` key on a rule | `scope` |

Two semantic differences are deliberate and are flagged by the upgrade: a missing fact was
`false`, it is now Unknown; a numeric literal without a unit compared to a dimensioned fact was
allowed, it is now `missing_unit` at authoring. Stored grammar-0 payloads keep evaluating (the
interpreter upgrades on read); a *new* version must be grammar 1.

## 10. Errors

Authoring (parser/checker; the application shows them, `compliance.ValidateProgramFacts`
re-checks the subset it can):

`syntax`, `unknown_fact`, `unknown_parameter`, `parameter_type`, `type_mismatch`,
`dimension_mismatch`, `missing_unit`, `unknown_unit`, `base_mismatch`, `unknown_function`,
`arity`, `unbound_variable`, `not_deterministic` (reserved: nothing in grammar 1 can raise it),
`result_type` (host expects Boolean/Number/…), `inputs_mismatch` (Formula `inputs` ≠ facts used),
`enumeration_value`, `grammar_version`.

Run: none. Only Unknown, with the fact names that were Unknown carried in the result.

## 11. Worked examples

Each is a conformance case in `docs/schema/grammar/cases/`.

**E1 — the gate's derived fact** (`Program.Formula` `is_microprocessor`)
```
asset.template.technology = 'Microprocessor'
```
publishes `asset.formula.is_microprocessor` Boolean. Rule R1 scope: `asset.formula.is_microprocessor = true`.

**E2 — a maintenance cadence rule** (PRC-005 shape; interval from the last accepted record)
```
scope:   scheme.members[role='Relay'] is not empty
         and any(scheme.members[role='Relay'], m -> m.device.technology = 'Microprocessor')
cadence: every 12 y from record.last[kind='Maintenance', accepted=true].record.occurred_at
```
The 12-year interval is the *example's* value, not a claim about PRC-005's table; the standard's
intervals are entered by the Compliance Officer as data.

**E3 — a loadability check in the PRC-023 shape**
```
base(device.settings.50P1P, 'Primary', device.template.ct_ratio) > LOADABILITY_FACTOR * line.rating.emergency
```
where `line.rating.emergency` is a published characteristic in `A` and `LOADABILITY_FACTOR` is a
dimensionless literal the rule author enters from the standard's text. HYPOTHESIS — I have not
verified the criterion values of PRC-023-1 R1; they are not stated here and must come from the
standard held by the owner. The *shape* — a secondary setting converted to primary through the
CT ratio, compared with a factor of a rating — is what the grammar must express, and this line
does.

**E4 — TLM's ASPEN reconciliation rules as import mapping expressions**
```
node.area_filter:        $ matches '^17[0-9]{4}$'
node.kv_from_line_prefix: map(substr($name.line_number, 1, 1), {'0': 69 kV, '1': 138 kV, '2': 230 kV, '3': 345 kV})
node.tap_decode_69kv:    decode('^T([0-9]{3})L([0-9]{3})$', $, 2)
```

**E5 — a layer match score** (PROCEDURES #40)
```
candidates: line.structures where(s -> s.distance_to(node.location) < 500 m)
score:      if(c.station.name = node.name, 100, 0)
            + if(c.line.voltage_class = node.kv, 40, 0)
            - to(c.distance, 'm') / 100 m
acceptAt:   120
```
`s.distance_to` and `c.distance` are published facts of the layer reconciliation engine, not yet
in the catalogue: the case is parse-and-check only until #40 is built.

**E6 — a validation expression** on a characteristic `ct_ratio` (Ratio, dimensionless):
```
value >= 1 and value <= 10000 and floor(value) = value
```

**E7 — a test-plan limit** on reading `pickup_a` (A, Secondary):
```
value >= nominal * 0.95 and value <= nominal * 1.05
```

## 12. Interpreters and conformance

- `docs/schema/grammar/formula.py` — the reference: tokenizer, parser, printer, checker,
  evaluator, `upgrade()`. Python because the migration toolkit is Python; it is the oracle.
- `compliance.fEvalNode` (T-SQL) — the interpreter of record for rule runs on the database, so the
  rehearsals and smoke exercise it without an application. Returns a typed result
  (`Kind`, `BoolValue`, `NumValue`, `UnitCode`, `Base`, `TextValue`, `DateValue`, `Unknowns`).
- The C# application port (parser + checker + evaluator) must pass the same
  `cases/*.json`; the case files are the single source for all three.
- `docs/schema/ddl/tools/smoke.py` wave "grammar" loads the fixtures through procedures and
  evaluates each case through `fEvalNode`, comparing with the case's expected value.

## 13. Decisions (SCHEMA-DESIGN Appendix A)

Moved to [`docs/decisions/DECISION-LOG.md`](../decisions/DECISION-LOG.md) on 2026-09-10.

All 6 entries this section held (191–196) were **second copies** of rows already in
SCHEMA-DESIGN's log, and two had drifted: this document's 193 said an Unknown *validation* refuses the
write, while SCHEMA-DESIGN's also covered an Unknown *guard* — the rule `work.Transition` actually
enforces. A reader who found this copy would not have known guards were covered. The fuller text is in
the log; the divergence is recorded on the row.


## 14. Assumptions recorded (owner questions of the plan, 2026-09-05)

Answered by proceeding with the recommendation; reversible by a note here:

1. Text form authored, AST stored.
2. Three-valued Unknown, recorded; not fail-fast.
3. Strict units on literals against dimensioned terms.
4. Database evaluator of record now; application port later, same cases.
5. PRC-023 criterion values are the owner's to supply from the standard text; E3 carries the shape only.
