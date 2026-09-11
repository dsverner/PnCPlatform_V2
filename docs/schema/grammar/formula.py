"""
PnCPlatform formula expression language — reference implementation (FORMULA-GRAMMAR.md, grammar 1).

    parse(text)            -> AST (dict, canonical key order)        raises FormulaError(code)
    print_ast(ast)         -> normalised text
    canonical(ast)         -> the JSON text that is stored and hashed
    check(ast, catalogue, env={}) -> Type                             raises FormulaError(code)
    evaluate(ast, reader, subject, at, env={}) -> value or UNKNOWN    never raises on data
    upgrade(payload)       -> grammar-0 tree rewritten as grammar 1
    parse_cadence(text)    -> cadence node

Values at evaluation: bool | UNKNOWN | Quantity | str | datetime | Duration | Ref | list (a Set).
Deterministic, side-effect free: the only instant is the `at` argument. Stdlib only.
"""
from __future__ import annotations
import json, re, calendar
from dataclasses import dataclass, field
from decimal import Decimal, InvalidOperation
from datetime import datetime, timedelta, timezone

GRAMMAR = 1


class FormulaError(Exception):
    def __init__(self, code, message, pos=None):
        super().__init__(f"{code}: {message}" + (f" (at {pos})" if pos is not None else ""))
        self.code, self.message, self.pos = code, message, pos


# ----------------------------------------------------------------------------------------- units
# (dimension, base unit code, to-base factor). Mirrors ref.Unit; load_units(rows) replaces it from the database.
UNITS = {
    "V": ("Voltage", None, None), "kV": ("Voltage", "V", Decimal(1000)),
    "A": ("Current", None, None), "kA": ("Current", "A", Decimal(1000)),
    "VA": ("ApparentPower", None, None), "MVA": ("ApparentPower", "VA", Decimal(1000000)),
    "W": ("Power", None, None), "MW": ("Power", "W", Decimal(1000000)),
    "Ah": ("Charge", None, None),
    "Ω": ("Impedance", None, None),
    "ratio": ("Ratio", None, None), "%": ("Ratio", "ratio", Decimal("0.01")), "pu": ("Ratio", "ratio", Decimal(1)),
    "s": ("Time", None, None), "ms": ("Time", "s", Decimal("0.001")), "min": ("Time", "s", Decimal(60)),
    "cycles": ("Time", None, None),
    "Hz": ("Frequency", None, None),
    "m": ("Length", None, None), "ft": ("Length", "m", Decimal("0.3048")), "in": ("Length", "m", Decimal("0.0254")),
    "km": ("Length", "m", Decimal(1000)), "mi": ("Length", "m", Decimal("1609.344")),      # km, mi, min seeded 2026-09-05 for the grammar
    "°C": ("Temperature", None, None),
    "ohm/mi": ("Other", None, None),
}
DURATION_UNITS = ("y", "mo", "w", "d", "h")           # calendar/day durations; Time-dimension numbers also serve as durations
BASES = ("Primary", "Secondary", "PerUnit")
PRODUCTS = {("Voltage", "Current"): "ApparentPower", ("Current", "Impedance"): "Voltage", ("Energy", "Time"): None}
QUOTIENTS = {("Voltage", "Current"): "Impedance", ("Power", "Voltage"): "Current", ("ApparentPower", "Voltage"): "Current",
             ("Voltage", "Impedance"): "Current", ("Energy", "Time"): "Power", ("ApparentPower", "Current"): "Voltage"}


def load_units(rows):
    """rows: iterable of (UnitCode, Dimension, BaseUnitCode, ToBaseFactor) from ref.Unit."""
    UNITS.clear()
    for code, dim, base, factor in rows:
        UNITS[code] = (dim, base, None if factor is None else Decimal(str(factor)))


def unit_dimension(u):
    if u is None:
        return None
    if u not in UNITS:
        raise FormulaError("unknown_unit", f"unit '{u}' is not in ref.Unit")
    return UNITS[u][0]


def to_base(value, u):
    dim, base, factor = UNITS[u]
    return (value * factor, base) if base else (value, u)


def convert(value, u_from, u_to):
    """Convert within a dimension; None when not convertible."""
    if u_from == u_to:
        return value
    if unit_dimension(u_from) != unit_dimension(u_to) or unit_dimension(u_from) == "Other":
        return None
    v, b1 = to_base(value, u_from)
    _, b2 = to_base(Decimal(1), u_to)
    if b1 != b2:
        return None
    f = UNITS[u_to][2]
    return v / f if f else v


# ---------------------------------------------------------------------------------------- values
class _Unknown:
    def __repr__(self):
        return "UNKNOWN"

    def __bool__(self):
        raise TypeError("UNKNOWN has no truth value")


UNKNOWN = _Unknown()


@dataclass(frozen=True)
class Quantity:
    value: Decimal
    unit: str | None = None
    base: str | None = None

    def __repr__(self):
        return f"{self.value}{' ' + self.unit if self.unit else ''}{'@' + self.base if self.base else ''}"


@dataclass(frozen=True)
class Duration:
    n: Decimal
    unit: str     # y mo w d h | any Time unit

    def seconds(self):
        f = {"w": 604800, "d": 86400, "h": 3600}
        if self.unit in f:
            return self.n * f[self.unit]
        if self.unit in ("y", "mo"):
            return None          # calendar; not a fixed number of seconds
        v, _ = to_base(self.n, self.unit)
        return v


@dataclass(frozen=True)
class Ref:
    id: str
    kind: str


# -------------------------------------------------------------------------------------- tokenizer
KEYWORDS = {"and", "or", "not", "in", "like", "matches", "is", "unknown", "at", "true", "false",
            "every", "from", "within", "of", "once", "offset", "effective", "event",
            "calendar_year", "calendar_quarter", "calendar_month"}
_TOKEN = re.compile(r"""
    (?P<ws>\s+|--[^\n]*)
  | (?P<date>\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2})?)?)
  | (?P<num>(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?)
  | (?P<text>'(?:[^']|'')*')
  | (?P<atvar>@[A-Za-z_][A-Za-z0-9_]*)
  | (?P<dollar>\$[A-Za-z_][A-Za-z0-9_]*|\$)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)*)
  | (?P<unit>[Ω°%][A-Za-z]*)
  | (?P<op>->|<=|>=|<>|[-+*/^=<>(),{}\[\]:.])
""", re.X)
_UNIT_AFTER_NUM = re.compile(r"\s*([A-Za-z°Ω%][A-Za-z°Ω%]*(?:/[A-Za-z]+)?)(@(Primary|Secondary|PerUnit))?")


@dataclass
class Tok:
    kind: str
    value: str
    pos: int


def tokenize(text):
    out, i, n = [], 0, len(text)
    while i < n:
        m = _TOKEN.match(text, i)
        if not m:
            raise FormulaError("syntax", f"unexpected character {text[i]!r}", i)
        kind = m.lastgroup
        val = m.group(kind)
        if kind == "ws":
            i = m.end()
            continue
        if kind == "num":
            # a unit (with optional @base) may follow a number directly or after spaces
            um = _UNIT_AFTER_NUM.match(text, m.end())
            if um and um.group(1) in UNITS or (um and um.group(1) in DURATION_UNITS):
                u = um.group(1)
                # 'in' is a unit and a keyword: as a unit only when directly attached (no space) or followed by a non-expression token
                if u == "in" and text[m.end():um.start(1)] != "":
                    out.append(Tok("num", val, i)); i = m.end(); continue
                # a duration/time unit followed by a name char is a name (e.g. "6 days") -> syntax error later
                out.append(Tok("qty", (val, u, um.group(3)), i)); i = um.end(); continue
            out.append(Tok("num", val, i)); i = m.end(); continue
        if kind == "name" and val.lower() in KEYWORDS:
            out.append(Tok("kw", val.lower(), i)); i = m.end(); continue
        out.append(Tok(kind, val, i)); i = m.end()
    out.append(Tok("eof", "", n))
    return out


# ----------------------------------------------------------------------------------------- parser
COMPARE = ("=", "<>", "<", "<=", ">", ">=")
QUANT = ("any", "all", "select", "where")


class Parser:
    def __init__(self, text):
        self.t = tokenize(text)
        self.i = 0
        self.scope = []          # lambda-bound variables; a dotted name starting with one is a path from that variable

    def peek(self, k=0):
        return self.t[self.i + k]

    def take(self, kind=None, value=None):
        tok = self.peek()
        if (kind and tok.kind != kind) or (value is not None and tok.value != value):
            raise FormulaError("syntax", f"expected {value or kind}, found {tok.value or tok.kind!r}", tok.pos)
        self.i += 1
        return tok

    def at(self, kind, value=None):
        tok = self.peek()
        return tok.kind == kind and (value is None or tok.value == value)

    def parse_expression(self):
        e = self.p_or()
        if not self.at("eof"):
            raise FormulaError("syntax", f"unexpected {self.peek().value!r}", self.peek().pos)
        return e

    def p_or(self):
        parts = [self.p_and()]
        while self.at("kw", "or"):
            self.take(); parts.append(self.p_and())
        return parts[0] if len(parts) == 1 else {"op": "or", "a": parts}

    def p_and(self):
        parts = [self.p_not()]
        while self.at("kw", "and"):
            self.take(); parts.append(self.p_not())
        return parts[0] if len(parts) == 1 else {"op": "and", "a": parts}

    def p_not(self):
        if self.at("kw", "not"):
            self.take()
            return {"op": "not", "x": self.p_not()}
        return self.p_compare()

    def p_compare(self):
        l = self.p_add()
        tok = self.peek()
        if tok.kind == "op" and tok.value in COMPARE:
            self.take(); return {"op": tok.value, "l": l, "r": self.p_add()}
        if tok.kind == "kw" and tok.value in ("in", "like", "matches"):
            self.take(); return {"op": tok.value, "l": l, "r": self.p_add()}
        if tok.kind == "kw" and tok.value == "is":
            self.take()
            neg = False
            if self.at("kw", "not"):
                self.take(); neg = True
            if self.at("kw", "unknown"):
                self.take(); node = {"op": "isunknown", "x": l}
            elif self.at("name", "empty"):
                self.take(); node = {"op": "=", "l": {"fn": "count", "a": [l]}, "r": _num("0")}
            else:
                raise FormulaError("syntax", "expected 'unknown' or 'empty' after 'is'", self.peek().pos)
            return {"op": "not", "x": node} if neg else node
        return l

    def p_add(self):
        l = self.p_mul()
        while self.at("op", "+") or self.at("op", "-"):
            o = self.take().value
            l = {"op": o, "l": l, "r": self.p_mul()}
        return l

    def p_mul(self):
        l = self.p_unary()
        while self.at("op", "*") or self.at("op", "/"):
            o = self.take().value
            l = {"op": o, "l": l, "r": self.p_unary()}
        return l

    def p_unary(self):
        if self.at("op", "-") and False:
            self.take()
            x = self.p_unary()
            if "lit" in x and x.get("t") in ("num", "dur"):        # a negative literal; -2 ^ 2 is neg(2 ^ 2) since p_pow ran first
                return dict(x, lit="-" + x["lit"]) if not x["lit"].startswith("-") else dict(x, lit=x["lit"][1:])
            return {"op": "neg", "x": x}
        return self.p_pow()

    def p_pow(self):
        if self.at("op", "-"):
            self.take()
            x = self.p_pow()
            if "lit" in x and x.get("t") in ("num", "dur"):        # a negative literal; -2 ^ 2 is neg(2 ^ 2)
                return dict(x, lit="-" + x["lit"]) if not x["lit"].startswith("-") else dict(x, lit=x["lit"][1:])
            return {"op": "neg", "x": x}
        b = self.p_postfix()
        if self.at("op", "^"):
            self.take()
            return {"op": "^", "l": b, "r": self.p_unary()}      # right-associative
        return b

    def p_postfix(self):
        e = self.p_primary()
        while True:
            if self.at("op", ".") and "fact" in e or self.at("op", ".") and "var" in e:
                self.take()
                name = self.take("name").value
                node = {"fact": name}
                if self.at("op", "["):
                    node["p"] = self.p_params()
                node["from"] = e
                e = node
            elif self.at("kw", "at") and ("fact" in e):
                self.take(); self.take("op", "(")
                e["at"] = self.p_or()
                self.take("op", ")")
            else:
                return e

    def p_params(self):
        self.take("op", "[")
        p = {}
        while True:
            k = self.take("name").value
            self.take("op", "=")
            v = self.p_primary()
            if "lit" not in v:
                raise FormulaError("syntax", "a parameter value must be a literal", self.peek().pos)
            p[k] = v
            if self.at("op", ","):
                self.take(); continue
            self.take("op", "]")
            return p

    def p_primary(self):
        tok = self.peek()
        if tok.kind == "op" and tok.value == "(":
            self.take(); e = self.p_or(); self.take("op", ")"); return e
        if tok.kind == "num":
            self.take(); return _num(tok.value)
        if tok.kind == "qty":
            self.take()
            val, u, base = tok.value
            if u in DURATION_UNITS:
                if base:
                    raise FormulaError("syntax", "a duration has no base", tok.pos)
                return {"lit": _norm_num(val), "t": "dur", "u": u}
            n = {"lit": _norm_num(val), "t": "num", "u": u}
            if base:
                n["b"] = base
            return n
        if tok.kind == "text":
            self.take(); return {"lit": tok.value[1:-1].replace("''", "'"), "t": "text"}
        if tok.kind == "date":
            self.take(); return {"lit": _norm_date(tok.value, tok.pos), "t": "date"}
        if tok.kind == "kw" and tok.value in ("true", "false"):
            self.take(); return {"lit": tok.value == "true", "t": "bool"}
        if tok.kind == "kw" and tok.value == "unknown":
            self.take(); return {"lit": None}
        if tok.kind == "atvar":
            self.take(); return {"var": tok.value}
        if tok.kind == "dollar":
            self.take(); return {"var": tok.value}
        if tok.kind == "op" and tok.value == "{":
            return self.p_set_or_map()
        if tok.kind == "name":
            self.take()
            if self.at("op", "("):
                return self.p_call(tok.value, tok.pos)
            if self.at("op", "["):
                return {"fact": tok.value, "p": self.p_params()}
            head, _, rest = tok.value.partition(".")
            if rest and head in self.scope:
                return {"fact": rest, "from": {"var": head}}
            if "." not in tok.value:                       # a bare name is a variable (lambda-bound or host-bound); facts are dotted
                return {"var": tok.value}
            return {"fact": tok.value}
        raise FormulaError("syntax", f"unexpected {tok.value or tok.kind!r}", tok.pos)

    def p_set_or_map(self):
        self.take("op", "{")
        if self.at("op", "}"):
            self.take(); return {"set": []}
        first = self.p_or()
        if self.at("op", ":"):
            self.take()
            pairs = [[first, self.p_or()]]
            while self.at("op", ","):
                self.take()
                k = self.p_or(); self.take("op", ":"); pairs.append([k, self.p_or()])
            self.take("op", "}")
            return {"map": pairs}
        items = [first]
        while self.at("op", ","):
            self.take(); items.append(self.p_or())
        self.take("op", "}")
        return {"set": items}

    def p_call(self, name, pos):
        self.take("op", "(")
        if name in QUANT:
            s = self.p_or()
            self.take("op", ",")
            var = self.take("name").value
            self.take("op", "->")
            self.scope.append(var)
            body = self.p_or()
            self.scope.pop()
            self.take("op", ")")
            return {"fn": name, "a": [s], "var": var, "body": body}
        args = []
        if not self.at("op", ")"):
            args.append(self.p_or())
            while self.at("op", ","):
                self.take(); args.append(self.p_or())
        self.take("op", ")")
        return {"fn": name, "a": args}

    # cadence
    def parse_cadence(self):
        node = self.p_cadence()
        if not self.at("eof"):
            raise FormulaError("syntax", f"unexpected {self.peek().value!r}", self.peek().pos)
        return node

    def p_cadence(self):
        if self.at("kw", "once"):
            self.take(); return {"cadence": "once"}
        if self.at("kw", "within"):
            self.take()
            d = self.p_primary()
            if d.get("t") != "dur":
                raise FormulaError("syntax", "expected a duration after 'within'", self.peek().pos)
            self.take("kw", "of"); self.take("kw", "event")
            return {"cadence": "event", "within": d}
        self.take("kw", "every")
        tok = self.peek()
        if tok.kind == "kw" and tok.value.startswith("calendar_"):
            self.take()
            node = {"cadence": "calendar", "period": tok.value[len("calendar_"):]}
            if self.at("kw", "offset"):
                self.take(); node["offset"] = self.p_primary()
            return node
        d = self.p_primary()
        if d.get("t") != "dur":
            raise FormulaError("syntax", "expected a duration after 'every'", tok.pos)
        node = {"cadence": "interval", "every": d}
        if self.at("kw", "from"):
            self.take()
            if self.at("kw", "effective"):
                self.take(); node["from"] = "effective"
            else:
                node["from"] = self.p_postfix()
        return node


def _norm_num(s):
    try:
        d = Decimal(s)
    except InvalidOperation:
        raise FormulaError("syntax", f"bad number {s!r}")
    return _dec_str(d)


def _dec_str(d):
    s = format(d.normalize(), "f") if d == d.to_integral() or True else str(d)
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s if s not in ("", "-0") else "0"


def _num(s, u=None, b=None):
    n = {"lit": _norm_num(s), "t": "num"}
    if u:
        n["u"] = u
    if b:
        n["b"] = b
    return n


def _norm_date(s, pos=None):
    try:
        d = parse_datetime(s)
    except ValueError:
        raise FormulaError("syntax", f"bad datetime {s!r}", pos)
    return format_datetime(d)


DEFAULT_OFFSET = timezone(timedelta(hours=-3))       # authoring offset when a literal has none (the platform's configured offset)


def parse_datetime(s):
    if len(s) == 10:
        return datetime.fromisoformat(s).replace(tzinfo=DEFAULT_OFFSET)
    d = datetime.fromisoformat(s.replace("Z", "+00:00"))
    return d if d.tzinfo else d.replace(tzinfo=DEFAULT_OFFSET)


def format_datetime(d):
    s = d.isoformat()
    return s if "T" in s else s + "T00:00:00"


def parse(text):
    return Parser(text).parse_expression()


def parse_cadence(text):
    return Parser(text).parse_cadence()


# --------------------------------------------------------------------------------- canonical form
KEY_ORDER = ["g", "lit", "t", "u", "b", "fact", "p", "from", "at", "var", "op", "a", "x", "l", "r", "set", "map", "fn", "body",
             "cadence", "every", "period", "offset", "within"]


def _order(node):
    if isinstance(node, dict):
        keys = sorted(node.keys(), key=lambda k: (KEY_ORDER.index(k) if k in KEY_ORDER else 99, k))
        return {k: _order(node[k]) for k in keys}
    if isinstance(node, list):
        return [_order(x) for x in node]
    return node


def canonical(node, root=True):
    n = _order(node)
    if root and isinstance(n, dict) and "g" not in n:
        n = {"g": GRAMMAR, **n}
        n = _order(n)
    return json.dumps(n, separators=(",", ":"), ensure_ascii=False)


# ---------------------------------------------------------------------------------------- printer
PREC = {"or": 1, "and": 2, "not": 3, "=": 4, "<>": 4, "<": 4, "<=": 4, ">": 4, ">=": 4, "in": 4, "like": 4, "matches": 4,
        "isunknown": 4, "+": 5, "-": 5, "*": 6, "/": 6, "neg": 7, "^": 8}


def print_ast(n, parent=0):
    if "lit" in n:
        return _print_lit(n)
    if "fn" in n:
        if "var" in n and "body" in n:
            return f"{n['fn']}({print_ast(n['a'][0])}, {n['var']} -> {print_ast(n['body'])})"
        return f"{n['fn']}(" + ", ".join(print_ast(a) for a in n["a"]) + ")"
    if "var" in n:
        return n["var"]
    if "fact" in n:
        s = n["fact"]
        if "p" in n:
            s += "[" + ", ".join(f"{k}={_print_lit(v)}" for k, v in n["p"].items()) + "]"
        if "from" in n:
            s = print_ast(n["from"], 9) + "." + s
        if "at" in n:
            s += " at (" + print_ast(n["at"]) + ")"
        return s
    if "set" in n:
        return "{" + ", ".join(print_ast(x) for x in n["set"]) + "}"
    if "map" in n:
        return "{" + ", ".join(print_ast(k) + ": " + print_ast(v) for k, v in n["map"]) + "}"
    if "cadence" in n:
        return _print_cadence(n)
    op = n["op"]
    p = PREC[op]
    if op in ("and", "or"):
        s = f" {op} ".join(print_ast(a, p + 1) for a in n["a"])
    elif op == "not":
        s = "not " + print_ast(n["x"], p)
    elif op == "neg":
        s = "-" + print_ast(n["x"], p)
    elif op == "isunknown":
        s = print_ast(n["x"], p + 1) + " is unknown"
    elif op == "^":
        l = print_ast(n["l"], p + 1)
        if l.startswith("-"):
            l = "(" + l + ")"                        # a negative literal base: (-2) ^ 2 is not -(2 ^ 2)
        s = l + " ^ " + print_ast(n["r"], p)
    else:
        s = print_ast(n["l"], p) + f" {op} " + print_ast(n["r"], p + 1)
    return "(" + s + ")" if p < parent else s


def _print_lit(n):
    if n.get("lit") is None and "t" not in n:
        return "unknown"
    t = n["t"]
    if t == "num":
        return n["lit"] + (" " + n["u"] if "u" in n else "") + ("@" + n["b"] if "b" in n else "")
    if t == "dur":
        return n["lit"] + " " + n["u"]
    if t == "text":
        return "'" + n["lit"].replace("'", "''") + "'"
    if t == "bool":
        return "true" if n["lit"] else "false"
    if t == "date":
        return n["lit"]
    raise FormulaError("syntax", f"unknown literal type {t}")


def _print_cadence(n):
    k = n["cadence"]
    if k == "once":
        return "once"
    if k == "event":
        return "within " + _print_lit(n["within"]) + " of event"
    if k == "calendar":
        return "every calendar_" + n["period"] + (" offset " + _print_lit(n["offset"]) if "offset" in n else "")
    s = "every " + _print_lit(n["every"])
    if "from" in n:
        s += " from " + ("effective" if n["from"] == "effective" else print_ast(n["from"]))
    return s


# ---------------------------------------------------------------------------------------- checker
@dataclass(frozen=True)
class Type:
    kind: str                       # bool num text date dur ref set unknown
    dim: str | None = None          # for num: dimension (None = dimensionless)
    unit: str | None = None
    base: str | None = None
    elem: "Type | None" = None      # for set
    ref_kind: str | None = None

    def __str__(self):
        if self.kind == "num":
            return "num" + (f"[{self.unit or self.dim}]" if (self.unit or self.dim) else "") + (f"@{self.base}" if self.base else "")
        if self.kind == "set":
            return f"set<{self.elem}>"
        return self.kind


T_BOOL, T_TEXT, T_DATE, T_DUR, T_UNKNOWN = Type("bool"), Type("text"), Type("date"), Type("dur"), Type("unknown")


@dataclass
class FactInfo:
    name: str
    type: Type                              # element type; set-valued facts use kind 'set'
    params: dict = field(default_factory=dict)   # name -> Type
    subject_kind: str | None = None
    allowed: list | None = None             # enumeration values when the definition lists them
    ref_kind: str | None = None             # for ref / set<ref>: the kind of subject the value names


class Catalogue:
    """The fact catalogue the checker consults. Subclass or fill `facts` (name -> FactInfo)."""

    def __init__(self, facts=()):
        self.facts = {f.name: f for f in facts}

    def lookup(self, name, subject_kind=None):
        return self.facts.get(name)


def num_type(unit=None, base=None, dim=None):
    return Type("num", dim if dim else (unit_dimension(unit) if unit else None), unit, base)


def check(node, catalogue, env=None, subject_kind=None):
    return Checker(catalogue).check(node, dict(env or {}), subject_kind)


class Checker:
    def __init__(self, catalogue):
        self.cat = catalogue
        self.facts_used = set()

    def check(self, n, env, sk=None):
        if "lit" in n:
            return self.t_lit(n)
        if "fn" in n:
            return self.t_call(n, env, sk)
        if "var" in n:
            if n["var"] == "@at":
                return T_DATE
            if n["var"] not in env:
                raise FormulaError("unbound_variable", f"'{n['var']}' is not bound here")
            return env[n["var"]]
        if "fact" in n:
            return self.t_fact(n, env, sk)
        if "set" in n:
            ts = [self.check(x, env, sk) for x in n["set"]]
            if not ts:
                return Type("set", elem=T_UNKNOWN)
            known = [t for t in ts if t.kind != "unknown"]
            for t in known[1:]:
                self.same(known[0], t, "set elements")
            return Type("set", elem=known[0] if known else T_UNKNOWN)
        if "map" in n:
            raise FormulaError("syntax", "a map literal is only valid as the second argument of map()")
        if "cadence" in n:
            return self.t_cadence(n, env, sk)
        op = n["op"]
        if op in ("and", "or"):
            for a in n["a"]:
                self.expect(self.check(a, env, sk), "bool", op)
            return T_BOOL
        if op == "not":
            self.expect(self.check(n["x"], env, sk), "bool", op); return T_BOOL
        if op == "isunknown":
            self.check(n["x"], env, sk); return T_BOOL
        if op == "neg":
            t = self.check(n["x"], env, sk)
            if t.kind not in ("num", "dur"):
                raise FormulaError("type_mismatch", f"unary - needs a number, got {t}")
            return t
        l, r = self.check(n["l"], env, sk), self.check(n["r"], env, sk)
        if op in COMPARE:
            self.same(l, r, op, allow_unknown=True)
            if op not in ("=", "<>") and l.kind not in ("num", "date", "dur", "text", "unknown"):
                raise FormulaError("type_mismatch", f"'{op}' is not ordered over {l}")
            self.enum_check(n, l, r)
            return T_BOOL
        if op == "in":
            if r.kind != "set":
                raise FormulaError("type_mismatch", "'in' needs a set on the right")
            self.same(l, r.elem, "in", allow_unknown=True); return T_BOOL
        if op in ("like", "matches"):
            self.expect(l, "text", op); self.expect(r, "text", op); return T_BOOL
        if op in ("+", "-"):
            return self.t_addsub(op, l, r)
        if op in ("*", "/"):
            return self.t_muldiv(op, l, r, n)
        if op == "^":
            if l.kind != "num" or r.kind != "num" or r.dim is not None:
                raise FormulaError("type_mismatch", "'^' needs a number and a dimensionless exponent")
            if l.dim is None:
                return l
            e = n["r"].get("lit")
            if e in ("2", "-1", "1") and l.dim in ("Length", "Ratio"):
                return Type("num", "Other" if e == "2" else l.dim, (l.unit + "²") if e == "2" else l.unit, l.base) if e != "1" else l
            raise FormulaError("dimension_mismatch", "a dimensioned base needs an exponent of 1, 2 or -1 on Length or Ratio")
        raise FormulaError("syntax", f"unknown operator {op}")

    def t_lit(self, n):
        if n.get("lit") is None and "t" not in n:
            return T_UNKNOWN
        t = n["t"]
        if t == "num":
            return num_type(n.get("u"), n.get("b"))
        if t == "dur":
            return T_DUR
        return {"text": T_TEXT, "bool": T_BOOL, "date": T_DATE}[t]

    def t_fact(self, n, env, sk):
        info = self.cat.lookup(n["fact"], sk)
        if info is None:
            raise FormulaError("unknown_fact", f"'{n['fact']}' is not in the fact catalogue")
        self.facts_used.add(n["fact"])
        for k, v in n.get("p", {}).items():
            if k not in info.params:
                raise FormulaError("unknown_parameter", f"'{n['fact']}' has no parameter '{k}'")
            self.same(info.params[k], self.t_lit(v), f"parameter {k}", code="parameter_type")
        for k in info.params:
            if k not in n.get("p", {}):
                raise FormulaError("unknown_parameter", f"'{n['fact']}' requires parameter '{k}'")
        if "at" in n:
            self.expect(self.check(n["at"], env, sk), "date", "at")
        t = info.type
        if "from" in n:
            src = self.check(n["from"], env, sk)
            if src.kind == "set":
                return Type("set", elem=t)
            if src.kind != "ref":
                raise FormulaError("type_mismatch", f"a path step needs a reference or a set of references, got {src}")
            if src.kind == "unknown":
                return t
        return t

    def t_call(self, n, env, sk):
        fn, a = n["fn"], n["a"]
        if fn in QUANT:
            s = self.check(a[0], env, sk)
            if s.kind != "set":
                raise FormulaError("type_mismatch", f"{fn}() needs a set")
            body = self.check(n["body"], {**env, n["var"]: s.elem}, sk)
            if fn in ("any", "all", "where"):
                self.expect(body, "bool", fn)
                return T_BOOL if fn != "where" else s
            return Type("set", elem=body)
        ts = [self.check(x, env, sk) if "map" not in x else Type("map") for x in a]

        def arity(k):
            if len(ts) != k:
                raise FormulaError("arity", f"{fn}() takes {k} argument(s)")
        if fn in ("exists", "count"):
            arity(1)
            if ts[0].kind != "set":
                raise FormulaError("type_mismatch", f"{fn}() needs a set")
            return T_BOOL if fn == "exists" else num_type()
        if fn in ("sum", "avg") or (fn in ("min", "max") and len(ts) == 1 and ts[0].kind == "set"):
            arity(1)
            if ts[0].kind != "set" or ts[0].elem.kind not in ("num", "date", "dur", "unknown"):
                raise FormulaError("type_mismatch", f"{fn}() needs a set of numbers")
            return ts[0].elem
        if fn in ("min", "max", "clamp", "coalesce"):
            if fn == "clamp":
                arity(3)
            if len(ts) < 2 and fn != "coalesce":
                raise FormulaError("arity", f"{fn}() takes at least 2 arguments")
            for t in ts[1:]:
                self.same(ts[0], t, fn, allow_unknown=True)
            return ts[0] if ts[0].kind != "unknown" else next((t for t in ts if t.kind != "unknown"), T_UNKNOWN)
        if fn in ("abs", "floor", "ceil"):
            arity(1); self.expect(ts[0], "num", fn); return ts[0]
        if fn == "round":
            arity(2); self.expect(ts[0], "num", fn); self.dimless(ts[1], fn); return ts[0]
        if fn == "if":
            arity(3); self.expect(ts[0], "bool", fn); self.same(ts[1], ts[2], fn, allow_unknown=True)
            return ts[1] if ts[1].kind != "unknown" else ts[2]
        if fn == "to":
            arity(2); self.expect(ts[0], "num", fn)
            u = a[1].get("lit")
            if a[1].get("t") != "text" or u not in UNITS:
                raise FormulaError("unknown_unit", f"to() needs a unit code literal, got {u!r}")
            if ts[0].dim != unit_dimension(u) or ts[0].dim == "Other":
                raise FormulaError("dimension_mismatch", f"cannot convert {ts[0]} to {u}")
            return Type("num", ts[0].dim, u, ts[0].base)
        if fn == "base":
            arity(3); self.expect(ts[0], "num", fn)
            b = a[1].get("lit")
            if b not in ("Primary", "Secondary"):
                raise FormulaError("base_mismatch", "base() converts to 'Primary' or 'Secondary'")
            if ts[0].dim not in ("Current", "Voltage"):
                raise FormulaError("dimension_mismatch", "base() converts a current or a voltage")
            self.dimless(ts[2], "base() ratio")
            return Type("num", ts[0].dim, ts[0].unit, b)
        if fn == "days_between":
            arity(2); self.expect(ts[0], "date", fn); self.expect(ts[1], "date", fn); return num_type()
        if fn == "add":
            arity(2); self.expect(ts[0], "date", fn); self.expect_dur(ts[1], fn); return T_DATE
        if fn in ("year", "month", "day"):
            arity(1); self.expect(ts[0], "date", fn); return num_type()
        if fn in ("len",):
            arity(1); self.expect(ts[0], "text", fn); return num_type()
        if fn in ("lower", "upper", "trim"):
            arity(1); self.expect(ts[0], "text", fn); return T_TEXT
        if fn == "substr":
            arity(3); self.expect(ts[0], "text", fn); self.dimless(ts[1], fn); self.dimless(ts[2], fn); return T_TEXT
        if fn in ("startswith", "endswith", "contains"):
            arity(2); self.expect(ts[0], "text", fn); self.expect(ts[1], "text", fn); return T_BOOL
        if fn == "decode":
            arity(3); self.expect(ts[0], "text", fn); self.expect(ts[1], "text", fn); self.dimless(ts[2], fn); return T_TEXT
        if fn == "map":
            if len(a) not in (2, 3) or "map" not in a[1]:
                raise FormulaError("arity", "map(x, {k: v, ...}, default?)")
            kt = ts[0]
            vt = None
            for k, v in a[1]["map"]:
                self.same(kt, self.check(k, env, sk), "map key", allow_unknown=True)
                t = self.check(v, env, sk)
                if vt is None:
                    vt = t
                else:
                    self.same(vt, t, "map values")
            if len(a) == 3:
                self.same(vt, ts[2], "map default")
            return vt
        if fn == "number":
            arity(1); self.expect(ts[0], "text", fn); return num_type()
        if fn == "text":
            arity(1); return T_TEXT
        raise FormulaError("unknown_function", f"'{fn}' is not a function of the grammar")

    def t_cadence(self, n, env, sk):
        if n["cadence"] == "interval" and isinstance(n.get("from"), dict):
            self.expect(self.check(n["from"], env, sk), "date", "cadence anchor")
        return Type("cadence")

    # helpers
    def expect(self, t, kind, what):
        if t.kind == "unknown":
            return
        if t.kind != kind:
            raise FormulaError("type_mismatch", f"{what} needs {kind}, got {t}")

    def expect_dur(self, t, what):
        if t.kind == "dur" or (t.kind == "num" and t.dim == "Time") or t.kind == "unknown":
            return
        raise FormulaError("type_mismatch", f"{what} needs a duration, got {t}")

    def dimless(self, t, what):
        if t.kind == "unknown":
            return
        if t.kind != "num" or t.dim is not None:
            raise FormulaError("type_mismatch", f"{what} needs a dimensionless number, got {t}")

    def same(self, a, b, what, allow_unknown=False, code=None):
        if allow_unknown and (a.kind == "unknown" or b.kind == "unknown"):
            return
        if a.kind == "dur" and b.kind == "num" and b.dim == "Time" or b.kind == "dur" and a.kind == "num" and a.dim == "Time":
            return
        if a.kind != b.kind:
            raise FormulaError(code or "type_mismatch", f"{what}: {a} against {b}")
        if a.kind == "num":
            if (a.dim is None) != (b.dim is None):
                raise FormulaError("missing_unit", f"{what}: {a} against {b} — a literal against a dimensioned term must carry a unit")
            if a.dim != b.dim or (a.dim == "Other" and a.unit != b.unit):
                raise FormulaError("dimension_mismatch", f"{what}: {a} against {b}")
            if a.base and b.base and a.base != b.base:
                raise FormulaError("base_mismatch", f"{what}: {a} against {b}")
        if a.kind == "set":
            self.same(a.elem, b.elem, what, allow_unknown=True)

    def enum_check(self, n, l, r):
        for side, other in (("l", "r"), ("r", "l")):
            f, lit = n[side], n[other]
            if "fact" in f and "lit" in lit and lit.get("t") == "text":
                info = self.cat.lookup(f["fact"])
                if info and info.allowed is not None and lit["lit"] not in info.allowed:
                    raise FormulaError("enumeration_value", f"'{lit['lit']}' is not an allowed value of {f['fact']}")

    def t_addsub(self, op, l, r):
        if l.kind == "unknown":
            return r
        if r.kind == "unknown":
            return l
        if l.kind == "date" and (r.kind == "dur" or (r.kind == "num" and r.dim == "Time")):
            return T_DATE
        if l.kind == "date" and r.kind == "date" and op == "-":
            return T_DUR
        if l.kind == "dur" and r.kind == "dur":
            return T_DUR
        if l.kind == "num" and r.kind == "num":
            self.same(l, r, op)
            return Type("num", l.dim, l.unit or r.unit, l.base or r.base)
        raise FormulaError("type_mismatch", f"'{op}' over {l} and {r}")

    def t_muldiv(self, op, l, r, n):
        if l.kind == "unknown":
            return r if r.kind == "num" else T_UNKNOWN
        if r.kind == "unknown":
            return l
        if l.kind == "dur" and r.kind == "num" and r.dim is None or l.kind == "num" and l.dim is None and r.kind == "dur" and op == "*":
            return T_DUR
        if l.kind != "num" or r.kind != "num":
            raise FormulaError("type_mismatch", f"'{op}' over {l} and {r}")
        if l.base and r.base and l.base != r.base:
            raise FormulaError("base_mismatch", f"'{op}': {l} against {r}")
        base = l.base or r.base
        if r.dim is None:
            return Type("num", l.dim, l.unit, base)
        if l.dim is None:
            if op == "*":
                return Type("num", r.dim, r.unit, base)
            raise FormulaError("dimension_mismatch", f"a dimensionless number divided by {r} has no named dimension")
        if op == "/" and l.dim == r.dim and l.dim != "Other":
            return Type("num", None, None, base)          # x / x -> dimensionless (Ratio)
        if op == "*":
            d = PRODUCTS.get((l.dim, r.dim)) or PRODUCTS.get((r.dim, l.dim))
        else:
            d = QUOTIENTS.get((l.dim, r.dim))
            if d is None and l.dim == "Impedance" and r.dim == "Length":
                return Type("num", "Other", f"{l.unit}/{r.unit}", base)
        if d is None:
            raise FormulaError("dimension_mismatch", f"'{op}' over {l.dim} and {r.dim} has no named dimension")
        return Type("num", d, _base_unit_of(d), base)


def _base_unit_of(dim):
    for code, (d, base, _) in UNITS.items():
        if d == dim and base is None:
            return code
    return None


# -------------------------------------------------------------------------------------- evaluator
class FactReader:
    """read(subject, name, params, at) -> value | UNKNOWN. params: dict name -> plain value. Subclass."""

    def read(self, subject, name, params, at):
        return UNKNOWN


@dataclass
class Result:
    value: object
    unknowns: list


def evaluate(node, reader, subject, at, env=None):
    ev = Evaluator(reader, at)
    v = ev.ev(node, subject, dict(env or {}))
    return Result(v, ev.unknowns)


def is_unknown(v):
    return v is UNKNOWN


class Evaluator:
    def __init__(self, reader, at):
        self.reader, self.at, self.unknowns = reader, at, []

    def unk(self, why):
        self.unknowns.append(why)
        return UNKNOWN

    def ev(self, n, subj, env):
        if "lit" in n:
            return lit_value(n)
        if "fn" in n:
            return self.ev_call(n, subj, env)
        if "var" in n:
            v = n["var"]
            if v == "@at":
                return self.at
            return env.get(v, UNKNOWN)
        if "fact" in n:
            return self.ev_fact(n, subj, env)
        if "set" in n:
            return [self.ev(x, subj, env) for x in n["set"]]
        if "cadence" in n:
            return self.ev_cadence(n, subj, env)
        op = n["op"]
        if op == "and":
            r = True
            for a in n["a"]:
                v = self.ev(a, subj, env)
                if v is False:
                    return False
                if v is UNKNOWN:
                    r = UNKNOWN
            return r
        if op == "or":
            r = False
            for a in n["a"]:
                v = self.ev(a, subj, env)
                if v is True:
                    return True
                if v is UNKNOWN:
                    r = UNKNOWN
            return r
        if op == "not":
            v = self.ev(n["x"], subj, env)
            return UNKNOWN if v is UNKNOWN else (not v)
        if op == "isunknown":
            return self.ev(n["x"], subj, env) is UNKNOWN
        if op == "neg":
            v = self.ev(n["x"], subj, env)
            if v is UNKNOWN:
                return v
            return Quantity(-v.value, v.unit, v.base) if isinstance(v, Quantity) else Duration(-v.n, v.unit)
        l, r = self.ev(n["l"], subj, env), self.ev(n["r"], subj, env)
        if op == "in":
            if l is UNKNOWN or r is UNKNOWN:
                return UNKNOWN
            seen_unknown = False
            for x in r:
                c = self.compare(l, x)
                if c is UNKNOWN:
                    seen_unknown = True
                elif c == 0:
                    return True
            return UNKNOWN if seen_unknown else False
        if l is UNKNOWN or r is UNKNOWN:
            return UNKNOWN
        if op in COMPARE:
            c = self.compare(l, r)
            if c is UNKNOWN:
                return UNKNOWN
            return {"=": c == 0, "<>": c != 0, "<": c < 0, "<=": c <= 0, ">": c > 0, ">=": c >= 0}[op]
        if op == "like":
            return _like(l, r)
        if op == "matches":
            try:
                return re.search(r, l) is not None
            except re.error:
                return self.unk("bad pattern")
        return self.arith(op, l, r)

    def compare(self, a, b):
        if isinstance(a, Quantity) and isinstance(b, Quantity):
            bv = b.value if (a.unit == b.unit or not a.unit or not b.unit) else convert(b.value, b.unit, a.unit)
            if bv is None:
                return self.unk("unit conversion")
            return (a.value > bv) - (a.value < bv)
        if isinstance(a, Duration) and isinstance(b, Duration):
            sa, sb = a.seconds(), b.seconds()
            if sa is None or sb is None:
                return (a.n > b.n) - (a.n < b.n) if a.unit == b.unit else self.unk("calendar duration comparison")
            return (sa > sb) - (sa < sb)
        if type(a) is not type(b):
            return self.unk("type")
        return (a > b) - (a < b)

    def arith(self, op, l, r):
        try:
            if isinstance(l, datetime):
                if op in ("+", "-") and isinstance(r, (Duration, Quantity)):
                    d = r if isinstance(r, Duration) else Duration(r.value, r.unit)
                    return add_duration(l, d if op == "+" else Duration(-d.n, d.unit))
                if op == "-" and isinstance(r, datetime):
                    return Duration(Decimal((l - r).total_seconds()), "s")
                return self.unk("date arithmetic")
            if isinstance(l, Duration) or isinstance(r, Duration):
                if op == "*" and isinstance(l, Duration) and isinstance(r, Quantity):
                    return Duration(l.n * r.value, l.unit)
                if op == "*" and isinstance(r, Duration) and isinstance(l, Quantity):
                    return Duration(r.n * l.value, r.unit)
                if op == "/" and isinstance(l, Duration) and isinstance(r, Quantity):
                    if r.value == 0:
                        return self.unk("division by zero")
                    return Duration(l.n / r.value, l.unit)
                if op in ("+", "-") and isinstance(l, Duration) and isinstance(r, Duration) and l.unit == r.unit:
                    return Duration(l.n + r.n if op == "+" else l.n - r.n, l.unit)
                return self.unk("duration arithmetic")
            if not (isinstance(l, Quantity) and isinstance(r, Quantity)):
                return self.unk("arithmetic over non-numbers")
            base = l.base or r.base
            if op in ("+", "-"):
                rv = r.value if (l.unit == r.unit or not l.unit or not r.unit) else convert(r.value, r.unit, l.unit)
                if rv is None:
                    return self.unk("unit conversion")
                return Quantity(l.value + rv if op == "+" else l.value - rv, l.unit or r.unit, base)
            if op in ("*", "/"):
                if r.value == 0 and op == "/":
                    return self.unk("division by zero")
                lu, ru = l.unit, r.unit
                lv, rv = l.value, r.value
                if lu and ru:                                   # both dimensioned: combine in base units
                    ld, rd = unit_dimension(lu), unit_dimension(ru)
                    if ld != "Other" and rd != "Other" and not (op == "/" and ld == "Impedance" and rd == "Length"):
                        lv, lu = to_base(lv, lu)
                        rv, ru = to_base(rv, ru)
                    elif op == "/" and ld == rd == "Other" and lu == ru:
                        return Quantity(lv / rv, None, base)
                u = _unit_product(lu, ru, op)
                return Quantity(lv * rv if op == "*" else lv / rv, u, base)
            if op == "^":
                return Quantity(l.value ** r.value, l.unit, base)
        except (InvalidOperation, OverflowError, ZeroDivisionError):
            return self.unk("arithmetic failure")
        return self.unk(f"operator {op}")

    def ev_fact(self, n, subj, env):
        at = self.at
        if "at" in n:
            at = self.ev(n["at"], subj, env)
            if at is UNKNOWN:
                return self.unk(n["fact"])
        params = {k: lit_value(v) for k, v in n.get("p", {}).items()}
        if "from" in n:
            src = self.ev(n["from"], subj, env)
            if src is UNKNOWN:
                return self.unk(n["fact"])
            if isinstance(src, list):
                out = []
                for s in src:
                    v = self.read(s, n["fact"], params, at)
                    out.append(v)
                return out
            if isinstance(src, Ref):
                return self.read(src, n["fact"], params, at)
            return self.unk(n["fact"])
        return self.read(subj, n["fact"], params, at)

    def read(self, subj, name, params, at):
        v = self.reader.read(subj, name, params, at)
        if v is UNKNOWN or v is None:
            return self.unk(name)
        return v

    def ev_call(self, n, subj, env):
        fn = n["fn"]
        if fn in QUANT:
            s = self.ev(n["a"][0], subj, env)
            if s is UNKNOWN:
                return UNKNOWN
            var = n["var"]
            if fn in ("any", "all"):
                r = False if fn == "any" else True
                for x in s:
                    b = self.ev(n["body"], subj, {**env, var: x})
                    if fn == "any" and b is True:
                        return True
                    if fn == "all" and b is False:
                        return False
                    if b is UNKNOWN:
                        r = UNKNOWN
                return r
            if fn == "where":
                return [x for x in s if self.ev(n["body"], subj, {**env, var: x}) is True]
            return [self.ev(n["body"], subj, {**env, var: x}) for x in s]
        a = [self.ev(x, subj, env) for x in n["a"]] if fn != "map" else [self.ev(n["a"][0], subj, env)]
        if fn == "coalesce":
            return next((x for x in a if x is not UNKNOWN), UNKNOWN)
        if fn == "if":
            if a[0] is UNKNOWN:
                return UNKNOWN
            return a[1] if a[0] else a[2]
        if fn == "map":
            k = a[0]
            if k is UNKNOWN:
                return UNKNOWN
            for mk, mv in n["a"][1]["map"]:
                kv = self.ev(mk, subj, env)
                if self.compare(k, kv) == 0:
                    return self.ev(mv, subj, env)
            return self.ev(n["a"][2], subj, env) if len(n["a"]) == 3 else self.unk("map: no match")
        if fn in ("exists", "count"):
            if a[0] is UNKNOWN:
                return UNKNOWN
            return (len(a[0]) > 0) if fn == "exists" else Quantity(Decimal(len(a[0])))
        if fn in ("sum", "avg") or (fn in ("min", "max") and len(a) == 1 and isinstance(a[0], list)):
            s = a[0]
            if s is UNKNOWN or not s or any(x is UNKNOWN for x in s):
                return self.unk(fn)
            if fn in ("min", "max"):
                best = s[0]
                for x in s[1:]:
                    c = self.compare(x, best)
                    if c is UNKNOWN:
                        return UNKNOWN
                    if (c < 0) if fn == "min" else (c > 0):
                        best = x
                return best
            tot = s[0]
            for x in s[1:]:
                tot = self.arith("+", tot, x)
                if tot is UNKNOWN:
                    return tot
            return tot if fn == "sum" else self.arith("/", tot, Quantity(Decimal(len(s))))
        if any(x is UNKNOWN for x in a):
            return UNKNOWN
        try:
            return self.call(fn, a, n)
        except (InvalidOperation, OverflowError, ZeroDivisionError, ValueError, re.error):
            return self.unk(fn)

    def call(self, fn, a, n):
        if fn in ("min", "max"):
            best = a[0]
            for x in a[1:]:
                c = self.compare(x, best)
                if c is UNKNOWN:
                    return UNKNOWN
                if (c < 0) if fn == "min" else (c > 0):
                    best = x
            return best
        if fn == "clamp":
            x, lo, hi = a
            if self.compare(x, lo) is UNKNOWN or self.compare(x, hi) is UNKNOWN:
                return UNKNOWN
            return lo if self.compare(x, lo) < 0 else hi if self.compare(x, hi) > 0 else x
        if fn == "abs":
            return Quantity(abs(a[0].value), a[0].unit, a[0].base)
        if fn == "floor":
            return Quantity(a[0].value.to_integral_value(rounding="ROUND_FLOOR"), a[0].unit, a[0].base)
        if fn == "ceil":
            return Quantity(a[0].value.to_integral_value(rounding="ROUND_CEILING"), a[0].unit, a[0].base)
        if fn == "round":
            q = Decimal(1).scaleb(-int(a[1].value))
            return Quantity(a[0].value.quantize(q, rounding="ROUND_HALF_UP"), a[0].unit, a[0].base)      # half away from zero: T-SQL ROUND, C# MidpointRounding.AwayFromZero
        if fn == "to":
            v = convert(a[0].value, a[0].unit, a[1])
            return self.unk("to: conversion") if v is None else Quantity(v, a[1], a[0].base)
        if fn == "base":
            x, target, ratio = a
            if x.base == target or x.base is None:
                return Quantity(x.value, x.unit, target)
            r = ratio.value
            if r == 0:
                return self.unk("base: zero ratio")
            return Quantity(x.value * r if target == "Primary" else x.value / r, x.unit, target)
        if fn == "days_between":
            return Quantity(Decimal((a[1] - a[0]).total_seconds()) / Decimal(86400))
        if fn == "add":
            d = a[1] if isinstance(a[1], Duration) else Duration(a[1].value, a[1].unit)
            return add_duration(a[0], d)
        if fn in ("year", "month", "day"):
            return Quantity(Decimal(getattr(a[0], fn)))
        if fn == "len":
            return Quantity(Decimal(len(a[0])))
        if fn in ("lower", "upper"):
            return getattr(a[0], fn)()
        if fn == "trim":
            return a[0].strip()
        if fn == "substr":
            s, start, ln = a[0], int(a[1].value), int(a[2].value)
            return s[start - 1:start - 1 + ln]            # 1-based, as T-SQL SUBSTRING
        if fn == "startswith":
            return a[0].startswith(a[1])
        if fn == "endswith":
            return a[0].endswith(a[1])
        if fn == "contains":
            return a[1] in a[0]
        if fn == "decode":
            m = re.search(a[0], a[1])
            if not m:
                return self.unk("decode: no match")
            g = m.group(int(a[2].value))
            return self.unk("decode: empty group") if g is None else g
        if fn == "number":
            try:
                return Quantity(Decimal(a[0].strip()))
            except InvalidOperation:
                return self.unk("number: not numeric")
        if fn == "text":
            return text_of(a[0])
        raise FormulaError("unknown_function", fn)

    def ev_cadence(self, n, subj, env):
        # returns the due instant for the subject given the anchor, or UNKNOWN (the caller falls back to EffectiveFrom)
        k = n["cadence"]
        if k == "interval":
            anchor = self.ev(n["from"], subj, env) if isinstance(n.get("from"), dict) else env.get("effective", UNKNOWN)
            if anchor is UNKNOWN:
                return self.unk("cadence anchor")
            return add_duration(anchor, lit_value(n["every"]))
        if k == "calendar":
            base = self.at
            if n["period"] == "year":
                end = datetime(base.year + 1, 1, 1, tzinfo=base.tzinfo)
            elif n["period"] == "quarter":
                q = (base.month - 1) // 3
                end = datetime(base.year + (1 if q == 3 else 0), 1 if q == 3 else 3 * (q + 1) + 1, 1, tzinfo=base.tzinfo)
            else:
                end = datetime(base.year + (1 if base.month == 12 else 0), 1 if base.month == 12 else base.month + 1, 1, tzinfo=base.tzinfo)
            return add_duration(end, lit_value(n["offset"])) if "offset" in n else end
        if k == "event":
            ev = env.get("event", UNKNOWN)
            return UNKNOWN if ev is UNKNOWN else add_duration(ev, lit_value(n["within"]))
        return env.get("effective", UNKNOWN)


def lit_value(n):
    if n.get("lit") is None and "t" not in n:
        return UNKNOWN
    t = n["t"]
    if t == "num":
        return Quantity(Decimal(n["lit"]), n.get("u"), n.get("b"))
    if t == "dur":
        return Duration(Decimal(n["lit"]), n["u"])
    if t == "date":
        return parse_datetime(n["lit"])
    return n["lit"]


def text_of(v):
    if isinstance(v, Quantity):
        return _dec_str(v.value)
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, datetime):
        return format_datetime(v)
    if isinstance(v, Duration):
        return f"{_dec_str(v.n)} {v.unit}"
    return str(v)


def add_duration(d, dur):
    n = dur.n
    if dur.unit == "y" or dur.unit == "mo":
        months = int(n * (12 if dur.unit == "y" else 1))
        frac = n * (12 if dur.unit == "y" else 1) - months
        y, m = divmod(d.month - 1 + months, 12)
        y += d.year
        day = min(d.day, calendar.monthrange(y, m + 1)[1])
        out = d.replace(year=y, month=m + 1, day=day)
        return out + timedelta(days=float(frac) * 30) if frac else out
    secs = dur.seconds()
    if secs is None:
        raise ValueError("calendar duration")
    return d + timedelta(seconds=float(secs))


def _unit_product(u1, u2, op):
    d1, d2 = unit_dimension(u1) if u1 else None, unit_dimension(u2) if u2 else None
    if d2 is None:
        return u1
    if d1 is None:
        return u2 if op == "*" else None
    if op == "/" and d1 == d2:
        return None
    if op == "*":
        d = PRODUCTS.get((d1, d2)) or PRODUCTS.get((d2, d1))
    else:
        d = QUOTIENTS.get((d1, d2))
        if d is None and d1 == "Impedance" and d2 == "Length":
            return f"{u1}/{u2}"
    return _base_unit_of(d) if d else None


def _like(s, pattern):
    rx = "^" + "".join(".*" if c == "%" else "." if c == "_" else re.escape(c) for c in pattern) + "$"
    return re.match(rx, s, re.S) is not None


# ---------------------------------------------------------------------------------------- upgrade
def upgrade(payload):
    """Grammar 0 (the gate's predicate tree, or a rule payload holding one) -> grammar 1. Idempotent on grammar 1."""
    if isinstance(payload, str):
        payload = json.loads(payload)
    if payload.get("g") == GRAMMAR:
        return payload
    if "predicate" in payload or "subjectKinds" in payload:
        out = {k: v for k, v in payload.items() if k != "predicate"}
        if "predicate" in payload:
            out["scope"] = _up_node(payload["predicate"])
        return {"g": GRAMMAR, **out}
    return {"g": GRAMMAR, **_up_node(payload)} if _is_g0(payload) else payload


def _is_g0(n):
    return isinstance(n, dict) and ("all" in n or "any" in n or ("not" in n and "op" not in n) or ("fact" in n and "op" in n))


def _up_node(n):
    if not _is_g0(n):
        return n
    if "all" in n or "any" in n:
        parts = [_up_node(x) for x in n.get("all", n.get("any"))]
        return parts[0] if len(parts) == 1 else {"op": "and" if "all" in n else "or", "a": parts}
    if "not" in n:
        return {"op": "not", "x": _up_node(n["not"])}
    op, v = n["op"], n.get("value")
    if op == "in":
        return {"op": "in", "l": {"fact": n["fact"]}, "r": {"set": [_up_lit(x) for x in v]}}
    return {"op": op, "l": {"fact": n["fact"]}, "r": _up_lit(v)}


def _up_lit(v):
    if isinstance(v, bool):
        return {"lit": v, "t": "bool"}
    if isinstance(v, (int, float)):
        return _num(str(v))
    if v is None:
        return {"lit": None}
    return {"lit": str(v), "t": "text"}


def fact_names(node):
    """Every fact name a node references, at any depth (mirrors compliance.fPayloadFactNames)."""
    out = set()

    def walk(n):
        if isinstance(n, dict):
            if "fact" in n and isinstance(n["fact"], str):
                out.add(n["fact"])
            for v in n.values():
                walk(v)
        elif isinstance(n, list):
            for x in n:
                walk(x)
    walk(node)
    return out
