using System.Text.Json.Nodes;

namespace PnC.Formula;

/// <summary>A static type of the language (FORMULA-GRAMMAR.md §3). ToString matches the reference's spelling.</summary>
public sealed record FormulaType(string Kind, string? Dim = null, string? Unit = null, string? Base = null, FormulaType? Elem = null, string? RefKind = null)
{
    public static readonly FormulaType Bool = new("bool"), Text = new("text"), Date = new("date"), Dur = new("dur"), UnknownT = new("unknown");

    public static FormulaType Num(string? unit = null, string? b = null, string? dim = null)
        => new("num", dim ?? (unit is null ? null : Units.Dimension(unit)), unit, b);

    public override string ToString()
    {
        if (Kind == "num") return "num" + ((Unit ?? Dim) is null ? "" : $"[{Unit ?? Dim}]") + (Base is null ? "" : $"@{Base}");
        if (Kind == "set") return $"set<{Elem}>";
        return Kind;
    }
}

/// <summary>A catalogue entry the checker consults (compliance.vFactCatalogue).</summary>
public sealed record FactInfo(string Name, FormulaType Type, IReadOnlyDictionary<string, FormulaType>? Params = null,
    string? SubjectKind = null, IReadOnlyList<string>? Allowed = null, string? RefKind = null)
{
    public IReadOnlyDictionary<string, FormulaType> ParamTypes => Params ?? new Dictionary<string, FormulaType>();
}

public interface ICatalogue
{
    FactInfo? Lookup(string name, string? subjectKind = null);
}

public sealed class Catalogue : ICatalogue
{
    readonly Dictionary<string, FactInfo> _facts;
    // a fact name is one fact: device.settings.<code> is catalogued once per setting code however many models carry the code
    // (W8, #153 — two SEL templates share 50G1P and the like); the first row wins, so the catalogue's own order decides the type
    public Catalogue(IEnumerable<FactInfo> facts) { _facts = facts.GroupBy(f => f.Name, StringComparer.Ordinal).ToDictionary(g => g.Key, g => g.First(), StringComparer.Ordinal); }
    public FactInfo? Lookup(string name, string? subjectKind = null) => _facts.GetValueOrDefault(name);
}

/// <summary>The authoring-time checker: types, dimensions, units, bases, parameters, enumerations (FORMULA-GRAMMAR.md §4, §10).</summary>
public sealed class Checker
{
    static readonly string[] Compare = { "=", "<>", "<", "<=", ">", ">=" };
    readonly ICatalogue _cat;
    public HashSet<string> FactsUsed { get; } = new(StringComparer.Ordinal);

    public Checker(ICatalogue catalogue) { _cat = catalogue; }

    public static FormulaType Check(JsonObject node, ICatalogue catalogue, IReadOnlyDictionary<string, FormulaType>? env = null, string? subjectKind = null)
        => new Checker(catalogue).Check(node, new Dictionary<string, FormulaType>(env ?? new Dictionary<string, FormulaType>(), StringComparer.Ordinal), subjectKind);

    static string S(JsonNode? n) => n!.GetValue<string>();

    public FormulaType Check(JsonObject n, Dictionary<string, FormulaType> env, string? sk)
    {
        if (n.ContainsKey("lit")) return TLit(n);
        if (n.ContainsKey("fn")) return TCall(n, env, sk);
        if (n.ContainsKey("var"))
        {
            var v = S(n["var"]);
            if (v == "@at") return FormulaType.Date;
            if (!env.TryGetValue(v, out var t)) throw new FormulaException(ErrorCodes.UnboundVariable, $"'{v}' is not bound here");
            return t;
        }
        if (n.ContainsKey("fact")) return TFact(n, env, sk);
        if (n["set"] is JsonArray set)
        {
            var ts = set.Select(x => Check((JsonObject)x!, env, sk)).ToList();
            if (ts.Count == 0) return new FormulaType("set", Elem: FormulaType.UnknownT);
            var known = ts.Where(t => t.Kind != "unknown").ToList();
            foreach (var t in known.Skip(1)) Same(known[0], t, "set elements");
            return new FormulaType("set", Elem: known.Count > 0 ? known[0] : FormulaType.UnknownT);
        }
        if (n.ContainsKey("map")) throw new FormulaException(ErrorCodes.Syntax, "a map literal is only valid as the second argument of map()");
        if (n.ContainsKey("cadence")) return TCadence(n, env, sk);
        var op = S(n["op"]);
        if (op is "and" or "or")
        {
            foreach (var a in (JsonArray)n["a"]!) Expect(Check((JsonObject)a!, env, sk), "bool", op);
            return FormulaType.Bool;
        }
        if (op == "not") { Expect(Check((JsonObject)n["x"]!, env, sk), "bool", op); return FormulaType.Bool; }
        if (op == "isunknown") { Check((JsonObject)n["x"]!, env, sk); return FormulaType.Bool; }
        if (op == "neg")
        {
            var t = Check((JsonObject)n["x"]!, env, sk);
            if (t.Kind is not ("num" or "dur")) throw new FormulaException(ErrorCodes.TypeMismatch, $"unary - needs a number, got {t}");
            return t;
        }
        var l = Check((JsonObject)n["l"]!, env, sk);
        var r = Check((JsonObject)n["r"]!, env, sk);
        if (Compare.Contains(op))
        {
            Same(l, r, op, allowUnknown: true);
            if (op is not ("=" or "<>") && l.Kind is not ("num" or "date" or "dur" or "text" or "unknown"))
                throw new FormulaException(ErrorCodes.TypeMismatch, $"'{op}' is not ordered over {l}");
            EnumCheck(n, l, r);
            return FormulaType.Bool;
        }
        if (op == "in")
        {
            if (r.Kind != "set") throw new FormulaException(ErrorCodes.TypeMismatch, "'in' needs a set on the right");
            Same(l, r.Elem!, "in", allowUnknown: true);
            return FormulaType.Bool;
        }
        if (op is "like" or "matches") { Expect(l, "text", op); Expect(r, "text", op); return FormulaType.Bool; }
        if (op is "+" or "-") return TAddSub(op, l, r);
        if (op is "*" or "/") return TMulDiv(op, l, r);
        if (op == "^")
        {
            if (l.Kind != "num" || r.Kind != "num" || r.Dim is not null) throw new FormulaException(ErrorCodes.TypeMismatch, "'^' needs a number and a dimensionless exponent");
            if (l.Dim is null) return l;
            var e = ((JsonObject)n["r"]!)["lit"]?.GetValue<string>();
            if (e is "2" or "-1" or "1" && l.Dim is "Length" or "Ratio")
                return e == "1" ? l : new FormulaType("num", e == "2" ? "Other" : l.Dim, e == "2" ? l.Unit + "²" : l.Unit, l.Base);
            throw new FormulaException(ErrorCodes.DimensionMismatch, "a dimensioned base needs an exponent of 1, 2 or -1 on Length or Ratio");
        }
        throw new FormulaException(ErrorCodes.Syntax, $"unknown operator {op}");
    }

    FormulaType TLit(JsonObject n)
    {
        if (n["lit"] is null && !n.ContainsKey("t")) return FormulaType.UnknownT;
        var t = S(n["t"]);
        return t switch
        {
            "num" => FormulaType.Num(n["u"]?.GetValue<string>(), n["b"]?.GetValue<string>()),
            "dur" => FormulaType.Dur,
            "text" => FormulaType.Text,
            "bool" => FormulaType.Bool,
            "date" => FormulaType.Date,
            _ => throw new FormulaException(ErrorCodes.Syntax, $"unknown literal type {t}"),
        };
    }

    FormulaType TFact(JsonObject n, Dictionary<string, FormulaType> env, string? sk)
    {
        var name = S(n["fact"]);
        var info = _cat.Lookup(name, sk) ?? throw new FormulaException(ErrorCodes.UnknownFact, $"'{name}' is not in the fact catalogue");
        FactsUsed.Add(name);
        var p = n["p"] as JsonObject;
        if (p is not null)
            foreach (var kv in p)
            {
                if (!info.ParamTypes.TryGetValue(kv.Key, out var pt) && !info.ParamTypes.TryGetValue(kv.Key + "?", out pt)) throw new FormulaException(ErrorCodes.UnknownParameter, $"'{name}' has no parameter '{kv.Key}'");
                Same(pt, TLit((JsonObject)kv.Value!), $"parameter {kv.Key}", code: ErrorCodes.ParameterType);
            }
        foreach (var k in info.ParamTypes.Keys)
            if (!k.EndsWith('?') && (p is null || !p.ContainsKey(k))) throw new FormulaException(ErrorCodes.UnknownParameter, $"'{name}' requires parameter '{k}'");   // a trailing '?' marks an optional parameter (PROCEDURE-ENGINE §7: pass=, member=)
        if (n["at"] is JsonObject at) Expect(Check(at, env, sk), "date", "at");
        var t = info.Type;
        if (n["from"] is JsonObject from)
        {
            var src = Check(from, env, sk);
            if (src.Kind == "set") return new FormulaType("set", Elem: t);
            if (src.Kind != "ref") throw new FormulaException(ErrorCodes.TypeMismatch, $"a path step needs a reference or a set of references, got {src}");
        }
        return t;
    }

    FormulaType TCall(JsonObject n, Dictionary<string, FormulaType> env, string? sk)
    {
        var fn = S(n["fn"]);
        var a = (JsonArray)n["a"]!;
        if (Parser.Quant.Contains(fn))
        {
            var s = Check((JsonObject)a[0]!, env, sk);
            if (s.Kind != "set") throw new FormulaException(ErrorCodes.TypeMismatch, $"{fn}() needs a set");
            var inner = new Dictionary<string, FormulaType>(env, StringComparer.Ordinal) { [S(n["var"])] = s.Elem! };
            var body = Check((JsonObject)n["body"]!, inner, sk);
            if (fn is "any" or "all" or "where") { Expect(body, "bool", fn); return fn == "where" ? s : FormulaType.Bool; }
            return new FormulaType("set", Elem: body);
        }
        var ts = a.Select(x => ((JsonObject)x!).ContainsKey("map") ? new FormulaType("map") : Check((JsonObject)x!, env, sk)).ToList();
        void Arity(int k) { if (ts.Count != k) throw new FormulaException(ErrorCodes.Arity, $"{fn}() takes {k} argument(s)"); }

        if (fn is "exists" or "count")
        {
            Arity(1);
            if (ts[0].Kind != "set") throw new FormulaException(ErrorCodes.TypeMismatch, $"{fn}() needs a set");
            return fn == "exists" ? FormulaType.Bool : FormulaType.Num();
        }
        if (fn is "sum" or "avg" || (fn is "min" or "max" && ts.Count == 1 && ts[0].Kind == "set"))
        {
            Arity(1);
            if (ts[0].Kind != "set" || ts[0].Elem!.Kind is not ("num" or "date" or "dur" or "unknown")) throw new FormulaException(ErrorCodes.TypeMismatch, $"{fn}() needs a set of numbers");
            return ts[0].Elem!;
        }
        if (fn is "min" or "max" or "clamp" or "coalesce")
        {
            if (fn == "clamp") Arity(3);
            if (ts.Count < 2 && fn != "coalesce") throw new FormulaException(ErrorCodes.Arity, $"{fn}() takes at least 2 arguments");
            foreach (var t in ts.Skip(1)) Same(ts[0], t, fn, allowUnknown: true);
            return ts[0].Kind != "unknown" ? ts[0] : ts.FirstOrDefault(t => t.Kind != "unknown") ?? FormulaType.UnknownT;
        }
        if (fn is "abs" or "floor" or "ceil") { Arity(1); Expect(ts[0], "num", fn); return ts[0]; }
        if (fn == "hypot")   // #171: PRC-023 reach geometry — sqrt(a² + b²) over one dimension, result in a's unit
        {
            Arity(2); Expect(ts[0], "num", fn); Expect(ts[1], "num", fn);
            Same(ts[0], ts[1], fn, allowUnknown: true);
            return ts[0].Kind != "unknown" ? ts[0] : ts[1];
        }
        if (fn is "cos" or "sin")   // #171: an Angle (deg), or a dimensionless number taken as degrees
        {
            Arity(1); Expect(ts[0], "num", fn);
            if (ts[0].Kind == "num" && ts[0].Dim is not null && ts[0].Dim != "Angle")
                throw new FormulaException(ErrorCodes.DimensionMismatch, $"{fn}() needs an angle or a dimensionless number, got {ts[0]}");
            return FormulaType.Num();
        }
        if (fn == "atan2")   // #171: atan2(y, x) over one dimension, result an Angle in degrees
        {
            Arity(2); Expect(ts[0], "num", fn); Expect(ts[1], "num", fn);
            Same(ts[0], ts[1], fn, allowUnknown: true);
            return FormulaType.Num("deg");
        }
        if (fn == "round") { Arity(2); Expect(ts[0], "num", fn); Dimless(ts[1], fn); return ts[0]; }
        if (fn == "if")
        {
            Arity(3); Expect(ts[0], "bool", fn); Same(ts[1], ts[2], fn, allowUnknown: true);
            return ts[1].Kind != "unknown" ? ts[1] : ts[2];
        }
        if (fn == "to")
        {
            Arity(2); Expect(ts[0], "num", fn);
            var lit = (JsonObject)a[1]!;
            var u = lit["lit"]?.GetValue<string>();
            if (lit["t"]?.GetValue<string>() != "text" || u is null || !Units.Table.ContainsKey(u)) throw new FormulaException(ErrorCodes.UnknownUnit, $"to() needs a unit code literal, got '{u}'");
            if (ts[0].Dim != Units.Dimension(u) || ts[0].Dim == "Other") throw new FormulaException(ErrorCodes.DimensionMismatch, $"cannot convert {ts[0]} to {u}");
            return new FormulaType("num", ts[0].Dim, u, ts[0].Base);
        }
        if (fn == "base")
        {
            Arity(3); Expect(ts[0], "num", fn);
            var b = ((JsonObject)a[1]!)["lit"]?.GetValue<string>();
            if (b is not ("Primary" or "Secondary")) throw new FormulaException(ErrorCodes.BaseMismatch, "base() converts to 'Primary' or 'Secondary'");
            if (ts[0].Dim is not ("Current" or "Voltage")) throw new FormulaException(ErrorCodes.DimensionMismatch, "base() converts a current or a voltage");
            Dimless(ts[2], "base() ratio");
            return new FormulaType("num", ts[0].Dim, ts[0].Unit, b);
        }
        if (fn == "days_between") { Arity(2); Expect(ts[0], "date", fn); Expect(ts[1], "date", fn); return FormulaType.Num(); }
        if (fn == "add") { Arity(2); Expect(ts[0], "date", fn); ExpectDur(ts[1], fn); return FormulaType.Date; }
        if (fn is "year" or "month" or "day") { Arity(1); Expect(ts[0], "date", fn); return FormulaType.Num(); }
        if (fn == "len") { Arity(1); Expect(ts[0], "text", fn); return FormulaType.Num(); }
        if (fn is "lower" or "upper" or "trim") { Arity(1); Expect(ts[0], "text", fn); return FormulaType.Text; }
        if (fn == "substr") { Arity(3); Expect(ts[0], "text", fn); Dimless(ts[1], fn); Dimless(ts[2], fn); return FormulaType.Text; }
        if (fn is "startswith" or "endswith" or "contains") { Arity(2); Expect(ts[0], "text", fn); Expect(ts[1], "text", fn); return FormulaType.Bool; }
        if (fn == "decode") { Arity(3); Expect(ts[0], "text", fn); Expect(ts[1], "text", fn); Dimless(ts[2], fn); return FormulaType.Text; }
        if (fn == "map")
        {
            if (a.Count is not (2 or 3) || !((JsonObject)a[1]!).ContainsKey("map")) throw new FormulaException(ErrorCodes.Arity, "map(x, {k: v, ...}, default?)");
            var kt = ts[0];
            FormulaType? vt = null;
            foreach (var pair in (JsonArray)((JsonObject)a[1]!)["map"]!)
            {
                Same(kt, Check((JsonObject)pair![0]!, env, sk), "map key", allowUnknown: true);
                var t = Check((JsonObject)pair[1]!, env, sk);
                if (vt is null) vt = t; else Same(vt, t, "map values");
            }
            if (a.Count == 3) Same(vt!, ts[2], "map default");
            return vt!;
        }
        if (fn == "number") { Arity(1); Expect(ts[0], "text", fn); return FormulaType.Num(); }
        if (fn == "text") { Arity(1); return FormulaType.Text; }
        throw new FormulaException(ErrorCodes.UnknownFunction, $"'{fn}' is not a function of the grammar");
    }

    FormulaType TCadence(JsonObject n, Dictionary<string, FormulaType> env, string? sk)
    {
        if (S(n["cadence"]) == "interval" && n["from"] is JsonObject from) Expect(Check(from, env, sk), "date", "cadence anchor");
        return new FormulaType("cadence");
    }

    static void Expect(FormulaType t, string kind, string what)
    {
        if (t.Kind == "unknown") return;
        if (t.Kind != kind) throw new FormulaException(ErrorCodes.TypeMismatch, $"{what} needs {kind}, got {t}");
    }

    static void ExpectDur(FormulaType t, string what)
    {
        if (t.Kind == "dur" || (t.Kind == "num" && t.Dim == "Time") || t.Kind == "unknown") return;
        throw new FormulaException(ErrorCodes.TypeMismatch, $"{what} needs a duration, got {t}");
    }

    static void Dimless(FormulaType t, string what)
    {
        if (t.Kind == "unknown") return;
        if (t.Kind != "num" || t.Dim is not null) throw new FormulaException(ErrorCodes.TypeMismatch, $"{what} needs a dimensionless number, got {t}");
    }

    static void Same(FormulaType a, FormulaType b, string what, bool allowUnknown = false, string? code = null)
    {
        if (allowUnknown && (a.Kind == "unknown" || b.Kind == "unknown")) return;
        if ((a.Kind == "dur" && b.Kind == "num" && b.Dim == "Time") || (b.Kind == "dur" && a.Kind == "num" && a.Dim == "Time")) return;
        if (a.Kind != b.Kind) throw new FormulaException(code ?? ErrorCodes.TypeMismatch, $"{what}: {a} against {b}");
        if (a.Kind == "num")
        {
            if ((a.Dim is null) != (b.Dim is null)) throw new FormulaException(ErrorCodes.MissingUnit, $"{what}: {a} against {b} — a literal against a dimensioned term must carry a unit");
            if (a.Dim != b.Dim || (a.Dim == "Other" && a.Unit != b.Unit)) throw new FormulaException(ErrorCodes.DimensionMismatch, $"{what}: {a} against {b}");
            if (a.Base is not null && b.Base is not null && a.Base != b.Base) throw new FormulaException(ErrorCodes.BaseMismatch, $"{what}: {a} against {b}");
        }
        if (a.Kind == "set") Same(a.Elem!, b.Elem!, what, allowUnknown: true);
    }

    void EnumCheck(JsonObject n, FormulaType l, FormulaType r)
    {
        foreach (var (side, other) in new[] { ("l", "r"), ("r", "l") })
        {
            var f = (JsonObject)n[side]!;
            var lit = (JsonObject)n[other]!;
            if (f.ContainsKey("fact") && lit.ContainsKey("lit") && lit["t"]?.GetValue<string>() == "text")
            {
                var info = _cat.Lookup(S(f["fact"]));
                var v = S(lit["lit"]);
                if (info?.Allowed is not null && !info.Allowed.Contains(v))
                    throw new FormulaException(ErrorCodes.EnumerationValue, $"'{v}' is not an allowed value of {S(f["fact"])}");
            }
        }
    }

    static FormulaType TAddSub(string op, FormulaType l, FormulaType r)
    {
        if (l.Kind == "unknown") return r;
        if (r.Kind == "unknown") return l;
        if (l.Kind == "date" && (r.Kind == "dur" || (r.Kind == "num" && r.Dim == "Time"))) return FormulaType.Date;
        if (l.Kind == "date" && r.Kind == "date" && op == "-") return FormulaType.Dur;
        if (l.Kind == "dur" && r.Kind == "dur") return FormulaType.Dur;
        if (l.Kind == "num" && r.Kind == "num")
        {
            Same(l, r, op);
            return new FormulaType("num", l.Dim, l.Unit ?? r.Unit, l.Base ?? r.Base);
        }
        throw new FormulaException(ErrorCodes.TypeMismatch, $"'{op}' over {l} and {r}");
    }

    static FormulaType TMulDiv(string op, FormulaType l, FormulaType r)
    {
        if (l.Kind == "unknown") return r.Kind == "num" ? r : FormulaType.UnknownT;
        if (r.Kind == "unknown") return l;
        if ((l.Kind == "dur" && r.Kind == "num" && r.Dim is null) || (l.Kind == "num" && l.Dim is null && r.Kind == "dur" && op == "*")) return FormulaType.Dur;
        if (l.Kind != "num" || r.Kind != "num") throw new FormulaException(ErrorCodes.TypeMismatch, $"'{op}' over {l} and {r}");
        if (l.Base is not null && r.Base is not null && l.Base != r.Base) throw new FormulaException(ErrorCodes.BaseMismatch, $"'{op}': {l} against {r}");
        var b = l.Base ?? r.Base;
        if (r.Dim is null) return new FormulaType("num", l.Dim, l.Unit, b);
        if (l.Dim is null)
        {
            if (op == "*") return new FormulaType("num", r.Dim, r.Unit, b);
            throw new FormulaException(ErrorCodes.DimensionMismatch, $"a dimensionless number divided by {r} has no named dimension");
        }
        if (op == "/" && l.Dim == r.Dim && l.Dim != "Other") return new FormulaType("num", null, null, b);
        var (found, d) = Units.ProductDimension(l.Dim, r.Dim, op);
        if (!found && op == "/" && l.Dim == "Impedance" && r.Dim == "Length") return new FormulaType("num", "Other", $"{l.Unit}/{r.Unit}", b);
        if (!found || d is null) throw new FormulaException(ErrorCodes.DimensionMismatch, $"'{op}' over {l.Dim} and {r.Dim} has no named dimension");
        return new FormulaType("num", d, Units.BaseUnitOf(d), b);
    }
}
