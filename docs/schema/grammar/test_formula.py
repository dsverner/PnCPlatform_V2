"""
Conformance suite for the formula language (FORMULA-GRAMMAR.md §12). Runs the reference implementation over
cases/*.json. The same files drive the T-SQL interpreter (ddl/tools/smoke.py wave "grammar") and the
application port. Run:  python -m unittest docs/schema/grammar/test_formula.py
"""
import io, json, os, sys, unittest
from decimal import Decimal
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import formula as F

CASES = os.path.join(HERE, "cases")


def load(name):
    with io.open(os.path.join(CASES, name), encoding="utf-8") as f:
        return json.load(f)


def type_of(spec):
    t = spec["type"]
    if t == "num":
        return F.num_type(spec.get("unit"), spec.get("base"))
    if t == "set":
        return F.Type("set", elem=type_of(spec["elem"]))
    if t == "ref":
        return F.Type("ref", ref_kind=spec.get("kind"))
    return F.Type(t)


def catalogue_from(spec):
    facts = []
    for name, s in spec.items():
        facts.append(F.FactInfo(name, type_of(s), params={k: F.Type(v) for k, v in s.get("params", {}).items()},
                                subject_kind=s.get("subject"), allowed=s.get("allowed"), ref_kind=s.get("kind")))
    return F.Catalogue(facts)


def value_from(v):
    if v is None or v.get("unknown"):
        return F.UNKNOWN
    if "num" in v:
        return F.Quantity(Decimal(v["num"]), v.get("u"), v.get("b"))
    if "text" in v:
        return v["text"]
    if "bool" in v:
        return v["bool"]
    if "date" in v:
        return F.parse_datetime(v["date"])
    if "dur" in v:
        return F.Duration(Decimal(v["dur"]), v["u"])
    if "ref" in v:
        return F.Ref(v["ref"], v["kind"])
    if "set" in v:
        return [value_from(x) for x in v["set"]]
    raise ValueError(v)


def value_to(v):
    if v is F.UNKNOWN:
        return {"unknown": True}
    if isinstance(v, F.Quantity):
        out = {"num": F._dec_str(v.value)}
        if v.unit:
            out["u"] = v.unit
        if v.base:
            out["b"] = v.base
        return out
    if isinstance(v, bool):
        return {"bool": v}
    if isinstance(v, str):
        return {"text": v}
    if isinstance(v, datetime):
        return {"date": F.format_datetime(v)}
    if isinstance(v, F.Duration):
        return {"dur": F._dec_str(v.n), "u": v.unit}
    if isinstance(v, F.Ref):
        return {"ref": v.id, "kind": v.kind}
    if isinstance(v, list):
        return {"set": [value_to(x) for x in v]}
    raise ValueError(v)


class FixtureReader(F.FactReader):
    def __init__(self, fx):
        self.fx = fx

    def read(self, subject, name, params, at):
        sid = subject.id if isinstance(subject, F.Ref) else subject
        hist = self.fx.get("at_history", {}).get(sid, {}).get(name)
        if hist is not None and at is not None:
            best = F.UNKNOWN
            for start, val in hist:
                if F.parse_datetime(start) <= at:
                    best = value_from(val)
            return best
        v = self.fx["subjects"].get(sid, {}).get(name)
        if v is None:
            return F.UNKNOWN
        if "params" in v:
            if v["params"] != {k: (x.value if isinstance(x, F.Quantity) else x) for k, x in params.items()}:
                return [] if "set" in v else F.UNKNOWN
            v = {k: x for k, x in v.items() if k != "params"}
        return value_from(v)


class Conformance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cat = catalogue_from(load("catalogue.json"))
        cls.fx = load("fixture.json")
        cls.env_t = {k: type_of(v) for k, v in cls.fx["env_types"].items()}
        cls.env_v = {k: value_from(v) for k, v in cls.fx["env_values"].items()}
        cls.at = F.parse_datetime(cls.fx["at"])
        cls.reader = FixtureReader(cls.fx)

    def test_expressions(self):
        for c in load("expressions.json"):
            with self.subTest(c["id"]):
                if "error" in c:
                    with self.assertRaises(F.FormulaError) as cm:
                        F.check(F.parse(c["text"]), self.cat, self.env_t)
                    self.assertEqual(cm.exception.code, c["error"], c["text"])
                    continue
                ast = F.parse(c["text"])
                self.assertEqual(json.loads(F.canonical(ast)), c["ast"], "canonical form")
                self.assertEqual(F.parse(F.print_ast(ast)), ast, "printer round-trip: " + F.print_ast(ast))
                t = F.check(ast, self.cat, self.env_t)
                self.assertEqual(str(t), c["type"], "type")
                r = F.evaluate(ast, self.reader, c["subject"], self.at, self.env_v)
                self.assertEqual(value_to(r.value), c["value"], f"value of {c['text']} (unknowns {r.unknowns})")

    def test_cadence(self):
        env = {k: F.parse_datetime(v) for k, v in self.fx["cadence_env"].items()}
        for c in load("cadence.json"):
            with self.subTest(c["id"]):
                ast = F.parse_cadence(c["text"])
                self.assertEqual(json.loads(F.canonical(ast)), c["ast"])
                self.assertEqual(F.parse_cadence(F.print_ast(ast)), ast)
                F.check(ast, self.cat, self.env_t)
                r = F.evaluate(ast, self.reader, c["subject"], self.at, env)
                self.assertEqual(value_to(r.value), c["value"])

    def test_grammar0(self):
        for c in load("grammar0.json"):
            with self.subTest(c["id"]):
                up = F.upgrade(c["grammar0"])
                self.assertEqual(json.loads(F.canonical(up)), c["grammar1"])
                self.assertEqual(F.upgrade(up), up, "idempotent")
                if c["text"]:
                    self.assertEqual(F.parse(c["text"]), {k: v for k, v in up.items() if k != "g"})

    def test_canonical_is_stable(self):
        a = F.parse("device.settings.50P1P>1.5A@Secondary   and(device.technology='Microprocessor')")
        b = F.parse("device.settings.50P1P > 1.5 A@Secondary and device.technology = 'Microprocessor' -- note")
        self.assertEqual(F.canonical(a), F.canonical(b))

    def test_fact_names(self):
        ast = F.parse("any(scheme.members[role='Relay'], m -> m.device.technology = 'Static') and base(device.settings.50P1P, 'Primary') > 1 A")
        self.assertEqual(F.fact_names(ast), {"scheme.members", "device.technology", "device.settings.50P1P"})


if __name__ == "__main__":
    unittest.main()
