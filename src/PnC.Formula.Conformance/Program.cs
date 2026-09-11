using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using PnC.Formula;

// The conformance runner: the same assertions as docs/schema/grammar/test_formula.py, over the same case files.
// usage: PnC.Formula.Conformance [cases directory]   (default: ../../../docs/schema/grammar/cases from the repo layout)

string casesDir = args.Length > 0 ? args[0] : FindCases();
int passed = 0, failed = 0;
var failures = new List<string>();

var catalogue = CatalogueFrom((JsonObject)Load("catalogue.json")!);
var fixture = (JsonObject)Load("fixture.json")!;
var envTypes = ((JsonObject)fixture["env_types"]!).ToDictionary(kv => kv.Key, kv => Fx.TypeOf((JsonObject)kv.Value!), StringComparer.Ordinal);
var envValues = ((JsonObject)fixture["env_values"]!).ToDictionary(kv => kv.Key, kv => Fx.ValueFrom((JsonObject)kv.Value!), StringComparer.Ordinal);
var at = Values.ParseDateTime(fixture["at"]!.GetValue<string>());
var reader = new FixtureReader(fixture);

foreach (var c in (JsonArray)Load("expressions.json")!)
{
    var cs = (JsonObject)c!;
    var id = cs["id"]!.GetValue<string>();
    var text = cs["text"]!.GetValue<string>();
    try
    {
        if (cs.ContainsKey("error"))
        {
            var want = cs["error"]!.GetValue<string>();
            try { Checker.Check(Parser.Parse(text), catalogue, envTypes); Fail(id, $"expected error {want}, got none"); }
            catch (FormulaException fe) { if (fe.Code == want) Pass(); else Fail(id, $"expected error {want}, got {fe.Code}: {fe.Message}"); }
            continue;
        }
        var ast = Parser.Parse(text);
        var canon = Canonical.ToCanonical(ast);
        var wantAst = Canonical.ToCanonical(cs["ast"]!);
        if (canon != wantAst) { Fail(id, $"canonical form\n    got  {canon}\n    want {wantAst}"); continue; }
        var printed = Printer.Print(ast);
        if (Canonical.ToCanonical(Parser.Parse(printed)) != canon) { Fail(id, $"printer round-trip: {printed}"); continue; }
        var t = Checker.Check(ast, catalogue, envTypes).ToString();
        if (t != cs["type"]!.GetValue<string>()) { Fail(id, $"type: got {t}, want {cs["type"]}"); continue; }
        var r = Evaluator.Evaluate(ast, reader, cs["subject"]!.GetValue<string>(), at, envValues);
        var got = Fx.ValueTo(r.Value);
        var want2 = Canonical.ToCanonical(cs["value"]!, root: false);
        if (Canonical.ToCanonical(got, root: false) != want2) { Fail(id, $"value of {text}\n    got  {Canonical.ToCanonical(got, root: false)} (unknowns {string.Join("; ", r.Unknowns)})\n    want {want2}"); continue; }
        Pass();
    }
    catch (Exception ex) { Fail(id, $"threw {ex.GetType().Name}: {ex.Message}"); }
}

var cadEnv = ((JsonObject)fixture["cadence_env"]!).ToDictionary(kv => kv.Key, kv => (object)Values.ParseDateTime(kv.Value!.GetValue<string>()), StringComparer.Ordinal);
foreach (var c in (JsonArray)Load("cadence.json")!)
{
    var cs = (JsonObject)c!;
    var id = cs["id"]!.GetValue<string>();
    try
    {
        var ast = Parser.ParseCadence(cs["text"]!.GetValue<string>());
        if (Canonical.ToCanonical(ast) != Canonical.ToCanonical(cs["ast"]!)) { Fail(id, "canonical form"); continue; }
        if (Canonical.ToCanonical(Parser.ParseCadence(Printer.Print(ast))) != Canonical.ToCanonical(ast)) { Fail(id, "printer round-trip"); continue; }
        Checker.Check(ast, catalogue, envTypes);
        var r = Evaluator.Evaluate(ast, reader, cs["subject"]!.GetValue<string>(), at, cadEnv);
        if (Canonical.ToCanonical(Fx.ValueTo(r.Value), root: false) != Canonical.ToCanonical(cs["value"]!, root: false)) { Fail(id, $"value: got {Canonical.ToCanonical(Fx.ValueTo(r.Value), root: false)}"); continue; }
        Pass();
    }
    catch (Exception ex) { Fail(id, $"threw {ex.GetType().Name}: {ex.Message}"); }
}

foreach (var c in (JsonArray)Load("grammar0.json")!)
{
    var cs = (JsonObject)c!;
    var id = cs["id"]!.GetValue<string>();
    try
    {
        var up = Canonical.Upgrade((JsonObject)cs["grammar0"]!.DeepClone());
        if (Canonical.ToCanonical(up) != Canonical.ToCanonical(cs["grammar1"]!)) { Fail(id, $"upgrade: got {Canonical.ToCanonical(up)}"); continue; }
        if (Canonical.ToCanonical(Canonical.Upgrade(up)) != Canonical.ToCanonical(up)) { Fail(id, "upgrade not idempotent"); continue; }
        if (cs["text"] is JsonValue tv && tv.TryGetValue<string>(out var txt))
        {
            var parsed = Parser.Parse(txt);
            var upNoG = (JsonObject)up.DeepClone(); upNoG.Remove("g");
            if (Canonical.ToCanonical(parsed, root: false) != Canonical.ToCanonical(upNoG, root: false)) { Fail(id, "text differs from the upgraded form"); continue; }
        }
        Pass();
    }
    catch (Exception ex) { Fail(id, $"threw {ex.GetType().Name}: {ex.Message}"); }
}

// the two extra tests of test_formula.py
{
    var a = Parser.Parse("device.settings.50P1P>1.5A@Secondary   and(device.technology='Microprocessor')");
    var b = Parser.Parse("device.settings.50P1P > 1.5 A@Secondary and device.technology = 'Microprocessor' -- note");
    if (Canonical.ToCanonical(a) == Canonical.ToCanonical(b)) Pass(); else Fail("canonical-stable", "whitespace/comments changed the canonical form");
    var names = Canonical.FactNames(Parser.Parse("any(scheme.members[role='Relay'], m -> m.device.technology = 'Static') and base(device.settings.50P1P, 'Primary', device.template.ct_ratio) > 1 A"));
    if (names.SetEquals(new[] { "scheme.members", "device.technology", "device.settings.50P1P", "device.template.ct_ratio" })) Pass(); else Fail("fact-names", string.Join(",", names));
}

foreach (var f in failures) Console.WriteLine("FAIL " + f);
Console.WriteLine($"conformance: {passed} passed, {failed} failed");
return failed == 0 ? 0 : 1;

// ---------------------------------------------------------------------------------------- helpers
void Pass() => passed++;
void Fail(string id, string why) { failed++; failures.Add($"{id}: {why}"); }

JsonNode? Load(string name) => JsonNode.Parse(File.ReadAllText(Path.Combine(casesDir, name)));

static string FindCases()
{
    var dir = AppContext.BaseDirectory;
    for (int i = 0; i < 8 && dir is not null; i++)
    {
        var candidate = Path.Combine(dir, "docs", "schema", "grammar", "cases");
        if (Directory.Exists(candidate)) return candidate;
        dir = Path.GetDirectoryName(dir.TrimEnd(Path.DirectorySeparatorChar));
    }
    throw new DirectoryNotFoundException("docs/schema/grammar/cases not found; pass the directory as the first argument");
}

static Catalogue CatalogueFrom(JsonObject spec)
{
    var facts = new List<FactInfo>();
    foreach (var (name, s) in spec)
    {
        var so = (JsonObject)s!;
        var ps = so["params"] is JsonObject p ? p.ToDictionary(kv => kv.Key, kv => new FormulaType(kv.Value!.GetValue<string>()), StringComparer.Ordinal) : null;
        var allowed = so["allowed"] is JsonArray al ? al.Select(x => x!.GetValue<string>()).ToList() : null;
        facts.Add(new FactInfo(name, Fx.TypeOf(so), ps, so["subject"]?.GetValue<string>(), allowed, so["kind"]?.GetValue<string>()));
    }
    return new Catalogue(facts);
}

static class Fx
{
    public static FormulaType TypeOf(JsonObject spec)
    {
        var t = spec["type"]!.GetValue<string>();
        return t switch
        {
            "num" => FormulaType.Num(spec["unit"]?.GetValue<string>(), spec["base"]?.GetValue<string>()),
            "set" => new FormulaType("set", Elem: TypeOf((JsonObject)spec["elem"]!)),
            "ref" => new FormulaType("ref", RefKind: spec["kind"]?.GetValue<string>()),
            _ => new FormulaType(t),
        };
    }

    public static object ValueFrom(JsonObject? v)
    {
        if (v is null || (v["unknown"] is JsonValue uv && uv.TryGetValue<bool>(out var u) && u)) return Unknown.Value;
        if (v.ContainsKey("num")) return new Quantity(Values.ParseDecimal(v["num"]!.GetValue<string>()), v["u"]?.GetValue<string>(), v["b"]?.GetValue<string>());
        if (v.ContainsKey("text")) return v["text"]!.GetValue<string>();
        if (v.ContainsKey("bool")) return v["bool"]!.GetValue<bool>();
        if (v.ContainsKey("date")) return Values.ParseDateTime(v["date"]!.GetValue<string>());
        if (v.ContainsKey("dur")) return new Duration(Values.ParseDecimal(v["dur"]!.GetValue<string>()), v["u"]!.GetValue<string>());
        if (v.ContainsKey("ref")) return new Ref(v["ref"]!.GetValue<string>(), v["kind"]!.GetValue<string>());
        if (v["set"] is JsonArray set) return set.Select(x => ValueFrom((JsonObject)x!)).ToList();
        throw new InvalidOperationException(v.ToJsonString());
    }

    public static JsonObject ValueTo(object v)
    {
        if (Values.IsUnknown(v)) return new JsonObject { ["unknown"] = true };
        switch (v)
        {
            case Quantity q:
            {
                var o = new JsonObject { ["num"] = Values.DecText(q.Value) };
                if (q.Unit is not null) o["u"] = q.Unit;
                if (q.Base is not null) o["b"] = q.Base;
                return o;
            }
            case bool b: return new JsonObject { ["bool"] = b };
            case string s: return new JsonObject { ["text"] = s };
            case DateTimeOffset d: return new JsonObject { ["date"] = Values.FormatDateTime(d) };
            case Duration du: return new JsonObject { ["dur"] = Values.DecText(du.N), ["u"] = du.Unit };
            case Ref r: return new JsonObject { ["ref"] = r.Id, ["kind"] = r.Kind };
            case List<object> list: { var a = new JsonArray(); foreach (var x in list) a.Add(ValueTo(x)); return new JsonObject { ["set"] = a }; }
            default: throw new InvalidOperationException(v.GetType().Name);
        }
    }
}

/// <summary>The fixture as a fact reader: per-subject values, parameter matching, an as-of history (as test_formula.py).</summary>
sealed class FixtureReader : IFactReader
{
    readonly JsonObject _fx;
    public FixtureReader(JsonObject fx) { _fx = fx; }

    public object? Read(object? subject, string name, IReadOnlyDictionary<string, object> parameters, DateTimeOffset at)
    {
        var sid = subject is Ref r ? r.Id : subject as string ?? "";
        if (_fx["at_history"] is JsonObject hist && hist[sid] is JsonObject hs && hs[name] is JsonArray h)
        {
            object best = Unknown.Value;
            foreach (var entry in h)
            {
                var start = Values.ParseDateTime(entry![0]!.GetValue<string>());
                if (start <= at) best = Fx.ValueFrom((JsonObject)entry[1]!);
            }
            return best;
        }
        if (((JsonObject)_fx["subjects"]!)[sid] is not JsonObject subj || subj[name] is not JsonObject v) return Unknown.Value;
        if (v["params"] is JsonObject ps)
        {
            var given = parameters.ToDictionary(kv => kv.Key, kv => kv.Value is Quantity q ? (object)q.Value : kv.Value, StringComparer.Ordinal);
            bool match = ps.Count == given.Count && ps.All(kv => given.TryGetValue(kv.Key, out var gv) && PlainEquals(kv.Value, gv));
            if (!match) return v.ContainsKey("set") ? new List<object>() : Unknown.Value;
            var copy = new JsonObject();
            foreach (var kv in v) if (kv.Key != "params") copy[kv.Key] = kv.Value?.DeepClone();
            return Fx.ValueFrom(copy);
        }
        return Fx.ValueFrom(v);
    }

    static bool PlainEquals(JsonNode? expected, object actual)
    {
        var e = expected!.AsValue();
        if (e.TryGetValue<bool>(out var b)) return actual is bool ab && ab == b;
        if (e.TryGetValue<string>(out var s)) return actual is string a && a == s;
        if (e.TryGetValue<decimal>(out var d)) return actual is decimal ad && ad == d;
        return false;
    }
}
