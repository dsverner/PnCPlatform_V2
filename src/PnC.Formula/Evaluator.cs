using System.Globalization;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace PnC.Formula;

/// <summary>Reads a fact for a subject; returns the value, or <see cref="Unknown.Value"/> / null when absent.</summary>
public interface IFactReader
{
    object? Read(object? subject, string name, IReadOnlyDictionary<string, object> parameters, DateTimeOffset at);
}

public sealed record EvalResult(object Value, IReadOnlyList<string> Unknowns);

/// <summary>
/// The three-valued evaluator (FORMULA-GRAMMAR.md §5). Never throws on data: every failure is Unknown, with the
/// reason appended to <see cref="Unknowns"/>. Values: bool, Quantity, string, DateTimeOffset, Duration, Ref,
/// List&lt;object&gt; (a set), Unknown.
/// </summary>
public sealed class Evaluator
{
    static readonly string[] Compare = { "=", "<>", "<", "<=", ">", ">=" };
    readonly IFactReader _reader;
    readonly DateTimeOffset _at;
    public List<string> Unknowns { get; } = new();

    public Evaluator(IFactReader reader, DateTimeOffset at) { _reader = reader; _at = at; }

    public static EvalResult Evaluate(JsonObject node, IFactReader reader, object? subject, DateTimeOffset at, IReadOnlyDictionary<string, object>? env = null)
    {
        var ev = new Evaluator(reader, at);
        var v = ev.Ev(node, subject, new Dictionary<string, object>(env ?? new Dictionary<string, object>(), StringComparer.Ordinal));
        return new EvalResult(v, ev.Unknowns);
    }

    static string S(JsonNode? n) => n!.GetValue<string>();
    static bool IsU(object? v) => Values.IsUnknown(v);
    object Unk(string why) { Unknowns.Add(why); return Unknown.Value; }

    public object Ev(JsonObject n, object? subj, Dictionary<string, object> env)
    {
        if (n.ContainsKey("lit")) return LitValue(n);
        if (n.ContainsKey("fn")) return EvCall(n, subj, env);
        if (n.ContainsKey("var"))
        {
            var v = S(n["var"]);
            if (v == "@at") return _at;
            return env.TryGetValue(v, out var val) ? val : Unknown.Value;
        }
        if (n.ContainsKey("fact")) return EvFact(n, subj, env);
        if (n["set"] is JsonArray set) return set.Select(x => Ev((JsonObject)x!, subj, env)).ToList();
        if (n.ContainsKey("cadence")) return EvCadence(n, subj, env);
        var op = S(n["op"]);
        if (op == "and")
        {
            object r = true;
            foreach (var a in (JsonArray)n["a"]!)
            {
                var v = Ev((JsonObject)a!, subj, env);
                if (v is false) return false;
                if (IsU(v)) r = Unknown.Value;
            }
            return r;
        }
        if (op == "or")
        {
            object r = false;
            foreach (var a in (JsonArray)n["a"]!)
            {
                var v = Ev((JsonObject)a!, subj, env);
                if (v is true) return true;
                if (IsU(v)) r = Unknown.Value;
            }
            return r;
        }
        if (op == "not") { var v = Ev((JsonObject)n["x"]!, subj, env); return IsU(v) ? Unknown.Value : !(bool)v; }
        if (op == "isunknown") return IsU(Ev((JsonObject)n["x"]!, subj, env));
        if (op == "neg")
        {
            var v = Ev((JsonObject)n["x"]!, subj, env);
            if (IsU(v)) return v;
            return v is Quantity q ? q with { Value = -q.Value } : v is Duration d ? d with { N = -d.N } : Unk("neg of a non-number");
        }
        var l = Ev((JsonObject)n["l"]!, subj, env);
        var r2 = Ev((JsonObject)n["r"]!, subj, env);
        if (op == "in")
        {
            if (IsU(l) || IsU(r2)) return Unknown.Value;
            if (r2 is not List<object> items) return Unk("in: not a set");
            bool seenUnknown = false;
            foreach (var x in items)
            {
                var c = CompareValues(l, x);
                if (c is null) seenUnknown = true;
                else if (c == 0) return true;
            }
            return seenUnknown ? Unknown.Value : false;
        }
        if (IsU(l) || IsU(r2)) return Unknown.Value;
        if (Compare.Contains(op))
        {
            var c = CompareValues(l, r2);
            if (c is null) return Unknown.Value;
            return op switch { "=" => c == 0, "<>" => c != 0, "<" => c < 0, "<=" => c <= 0, ">" => c > 0, _ => c >= 0 };
        }
        if (op == "like") return Like((string)l, (string)r2);
        if (op == "matches")
        {
            try { return Regex.IsMatch((string)l, (string)r2, RegexOptions.CultureInvariant); }
            catch (ArgumentException) { return Unk("bad pattern"); }
        }
        return Arith(op, l, r2);
    }

    /// <summary>-1, 0, 1; null when incomparable (an Unknown is recorded).</summary>
    public int? CompareValues(object a, object b)
    {
        if (a is Quantity qa && b is Quantity qb)
        {
            decimal? bv = (qa.Unit == qb.Unit || qa.Unit is null || qb.Unit is null) ? qb.Value : Units.Convert(qb.Value, qb.Unit, qa.Unit);
            if (bv is null) { Unk("unit conversion"); return null; }
            return qa.Value.CompareTo(bv.Value) switch { < 0 => -1, > 0 => 1, _ => 0 };
        }
        if (a is Duration da && b is Duration db)
        {
            var sa = da.Seconds(); var sb = db.Seconds();
            if (sa is null || sb is null)
            {
                if (da.Unit == db.Unit) return da.N.CompareTo(db.N) switch { < 0 => -1, > 0 => 1, _ => 0 };
                Unk("calendar duration comparison"); return null;
            }
            return sa.Value.CompareTo(sb.Value) switch { < 0 => -1, > 0 => 1, _ => 0 };
        }
        if (a.GetType() != b.GetType()) { Unk("type"); return null; }
        int c = a switch
        {
            string sa => string.CompareOrdinal(sa, (string)b),
            DateTimeOffset ta => ta.CompareTo((DateTimeOffset)b),
            bool ba => ba.CompareTo((bool)b),
            Ref ra => ra.Id.CompareTo(((Ref)b).Id) == 0 ? 0 : 1,
            _ => Comparer<object>.Default.Compare(a, b),
        };
        return c switch { < 0 => -1, > 0 => 1, _ => 0 };
    }

    public object Arith(string op, object l, object r)
    {
        try
        {
            if (l is DateTimeOffset dl)
            {
                if (op is "+" or "-" && (r is Duration || r is Quantity))
                {
                    var d = r is Duration rd ? rd : new Duration(((Quantity)r).Value, ((Quantity)r).Unit!);
                    return Values.AddDuration(dl, op == "+" ? d : d with { N = -d.N });
                }
                if (op == "-" && r is DateTimeOffset dr) return new Duration((decimal)(dl - dr).TotalSeconds, "s");
                return Unk("date arithmetic");
            }
            if (l is Duration || r is Duration)
            {
                if (op == "*" && l is Duration ld && r is Quantity rq) return new Duration(ld.N * rq.Value, ld.Unit);
                if (op == "*" && r is Duration rd2 && l is Quantity lq) return new Duration(rd2.N * lq.Value, rd2.Unit);
                if (op == "/" && l is Duration ld2 && r is Quantity rq2)
                {
                    if (rq2.Value == 0) return Unk("division by zero");
                    return new Duration(ld2.N / rq2.Value, ld2.Unit);
                }
                if (op is "+" or "-" && l is Duration a1 && r is Duration b1 && a1.Unit == b1.Unit) return new Duration(op == "+" ? a1.N + b1.N : a1.N - b1.N, a1.Unit);
                return Unk("duration arithmetic");
            }
            if (l is not Quantity x || r is not Quantity y) return Unk("arithmetic over non-numbers");
            var b = x.Base ?? y.Base;
            if (op is "+" or "-")
            {
                decimal? rv = (x.Unit == y.Unit || x.Unit is null || y.Unit is null) ? y.Value : Units.Convert(y.Value, y.Unit, x.Unit);
                if (rv is null) return Unk("unit conversion");
                return new Quantity(op == "+" ? x.Value + rv.Value : x.Value - rv.Value, x.Unit ?? y.Unit, b);
            }
            if (op is "*" or "/")
            {
                if (y.Value == 0 && op == "/") return Unk("division by zero");
                var lu = x.Unit; var ru = y.Unit; var lv = x.Value; var rv = y.Value;
                if (lu is not null && ru is not null)
                {
                    var ld = Units.Dimension(lu); var rd = Units.Dimension(ru);
                    if (ld != "Other" && rd != "Other" && !(op == "/" && ld == "Impedance" && rd == "Length"))
                    {
                        (lv, lu) = Units.ToBase(lv, lu);
                        (rv, ru) = Units.ToBase(rv, ru);
                    }
                    else if (op == "/" && ld == "Other" && rd == "Other" && lu == ru) return new Quantity(lv / rv, null, b);
                }
                var u = Units.UnitProduct(lu, ru, op);
                return new Quantity(op == "*" ? lv * rv : lv / rv, u, b);
            }
            if (op == "^") return new Quantity(Power(x.Value, y.Value), x.Unit, b);
        }
        catch (OverflowException) { return Unk("arithmetic failure"); }
        catch (DivideByZeroException) { return Unk("arithmetic failure"); }
        catch (InvalidOperationException) { return Unk("arithmetic failure"); }
        return Unk($"operator {op}");
    }

    /// <summary>b's value in a's unit; null when the two cannot be converted (as '+' and comparison do).</summary>
    static decimal? SameUnitAs(Quantity a, Quantity b)
        => (a.Unit == b.Unit || a.Unit is null || b.Unit is null) ? b.Value : Units.Convert(b.Value, b.Unit, a.Unit);

    static decimal Power(decimal x, decimal y)
    {
        if (y == decimal.Truncate(y) && Math.Abs(y) <= 64)
        {
            var n = (int)y; decimal r = 1m;
            for (int i = 0; i < Math.Abs(n); i++) r *= x;
            return n < 0 ? 1m / r : r;
        }
        return (decimal)Math.Pow((double)x, (double)y);
    }

    object EvFact(JsonObject n, object? subj, Dictionary<string, object> env)
    {
        var name = S(n["fact"]);
        var at = _at;
        if (n["at"] is JsonObject atNode)
        {
            var av = Ev(atNode, subj, env);
            if (IsU(av)) return Unk(name);
            at = (DateTimeOffset)av;
        }
        var parameters = new Dictionary<string, object>(StringComparer.Ordinal);
        if (n["p"] is JsonObject p) foreach (var kv in p) parameters[kv.Key] = LitValue((JsonObject)kv.Value!);
        if (n["from"] is JsonObject from)
        {
            var src = Ev(from, subj, env);
            if (IsU(src)) return Unk(name);
            if (src is List<object> list) return list.Select(s => Read(s, name, parameters, at)).ToList();
            if (src is Ref) return Read(src, name, parameters, at);
            return Unk(name);
        }
        return Read(subj, name, parameters, at);
    }

    object Read(object? subj, string name, IReadOnlyDictionary<string, object> parameters, DateTimeOffset at)
    {
        var v = _reader.Read(subj, name, parameters, at);
        return IsU(v) ? Unk(name) : v!;
    }

    object EvCall(JsonObject n, object? subj, Dictionary<string, object> env)
    {
        var fn = S(n["fn"]);
        var args = (JsonArray)n["a"]!;
        if (Parser.Quant.Contains(fn))
        {
            var sv = Ev((JsonObject)args[0]!, subj, env);
            if (IsU(sv)) return Unknown.Value;
            var items = (List<object>)sv;
            var v = S(n["var"]);
            var body = (JsonObject)n["body"]!;
            Dictionary<string, object> Bind(object x) => new(env, StringComparer.Ordinal) { [v] = x };
            if (fn is "any" or "all")
            {
                object r = fn == "any" ? false : true;
                foreach (var x in items)
                {
                    var b = Ev(body, subj, Bind(x));
                    if (fn == "any" && b is true) return true;
                    if (fn == "all" && b is false) return false;
                    if (IsU(b)) r = Unknown.Value;
                }
                return r;
            }
            if (fn == "where") return items.Where(x => Ev(body, subj, Bind(x)) is true).ToList();
            return items.Select(x => Ev(body, subj, Bind(x))).ToList();
        }
        var a = fn == "map" ? new List<object> { Ev((JsonObject)args[0]!, subj, env) } : args.Select(x => Ev((JsonObject)x!, subj, env)).ToList();
        if (fn == "coalesce") return a.FirstOrDefault(x => !IsU(x)) ?? Unknown.Value;
        if (fn == "if") { if (IsU(a[0])) return Unknown.Value; return (bool)a[0] ? a[1] : a[2]; }
        if (fn == "map")
        {
            var k = a[0];
            if (IsU(k)) return Unknown.Value;
            foreach (var pair in (JsonArray)((JsonObject)args[1]!)["map"]!)
            {
                var kv = Ev((JsonObject)pair![0]!, subj, env);
                if (CompareValues(k, kv) == 0) return Ev((JsonObject)pair[1]!, subj, env);
            }
            return args.Count == 3 ? Ev((JsonObject)args[2]!, subj, env) : Unk("map: no match");
        }
        if (fn is "exists" or "count")
        {
            if (IsU(a[0])) return Unknown.Value;
            var items = (List<object>)a[0];
            return fn == "exists" ? items.Count > 0 : new Quantity(items.Count);
        }
        if (fn is "sum" or "avg" || (fn is "min" or "max" && a.Count == 1 && a[0] is List<object>))
        {
            if (IsU(a[0]) || a[0] is not List<object> s || s.Count == 0 || s.Any(IsU)) return Unk(fn);
            if (fn is "min" or "max")
            {
                var best = s[0];
                foreach (var x in s.Skip(1))
                {
                    var c = CompareValues(x, best);
                    if (c is null) return Unknown.Value;
                    if (fn == "min" ? c < 0 : c > 0) best = x;
                }
                return best;
            }
            var tot = s[0];
            foreach (var x in s.Skip(1)) { tot = Arith("+", tot, x); if (IsU(tot)) return tot; }
            return fn == "sum" ? tot : Arith("/", tot, new Quantity(s.Count));
        }
        if (a.Any(IsU)) return Unknown.Value;
        try { return Call(fn, a); }
        catch (OverflowException) { return Unk(fn); }
        catch (ArgumentException) { return Unk(fn); }
        catch (FormatException) { return Unk(fn); }
        catch (InvalidCastException) { return Unk(fn); }
    }

    object Call(string fn, List<object> a)
    {
        switch (fn)
        {
            case "min":
            case "max":
            {
                var best = a[0];
                foreach (var x in a.Skip(1))
                {
                    var c = CompareValues(x, best);
                    if (c is null) return Unknown.Value;
                    if (fn == "min" ? c < 0 : c > 0) best = x;
                }
                return best;
            }
            case "clamp":
            {
                var c1 = CompareValues(a[0], a[1]); var c2 = CompareValues(a[0], a[2]);
                if (c1 is null || c2 is null) return Unknown.Value;
                return c1 < 0 ? a[1] : c2 > 0 ? a[2] : a[0];
            }
            case "abs": { var q = (Quantity)a[0]; return q with { Value = Math.Abs(q.Value) }; }
            case "floor": { var q = (Quantity)a[0]; return q with { Value = decimal.Floor(q.Value) }; }
            case "ceil": { var q = (Quantity)a[0]; return q with { Value = decimal.Ceiling(q.Value) }; }
            case "round": { var q = (Quantity)a[0]; return q with { Value = Math.Round(q.Value, (int)((Quantity)a[1]).Value, MidpointRounding.AwayFromZero) }; }
            // #171: the three geometry functions. Computed in IEEE-754 double and returned as a decimal, which
            // carries 15 significant digits of the double — so cos(60 deg) is exactly 0.5.
            case "hypot":
            {
                var p = (Quantity)a[0]; var q2 = (Quantity)a[1];
                var bv = SameUnitAs(p, q2);
                if (bv is null) return Unk("hypot: unit conversion");
                var d0 = (double)p.Value; var d1 = (double)bv.Value;
                return new Quantity((decimal)Math.Sqrt(d0 * d0 + d1 * d1), p.Unit ?? q2.Unit, p.Base ?? q2.Base);
            }
            case "cos":
            case "sin":
            {
                var q = (Quantity)a[0];
                var deg = q.Unit is null ? q.Value : Units.Convert(q.Value, q.Unit, "deg");
                if (deg is null) return Unk($"{fn}: angle conversion");
                var rad = (double)deg.Value * Math.PI / 180.0;
                return new Quantity((decimal)(fn == "cos" ? Math.Cos(rad) : Math.Sin(rad)));
            }
            case "atan2":
            {
                var y = (Quantity)a[0]; var x = (Quantity)a[1];
                var xv = SameUnitAs(y, x);
                if (xv is null) return Unk("atan2: unit conversion");
                if (y.Value == 0 && xv.Value == 0) return Unk("atan2: both arguments zero");
                return new Quantity((decimal)(Math.Atan2((double)y.Value, (double)xv.Value) * 180.0 / Math.PI), "deg");
            }
            case "to":
            {
                var q = (Quantity)a[0]; var u = (string)a[1];
                var v = q.Unit is null ? null : Units.Convert(q.Value, q.Unit, u);
                return v is null ? Unk("to: conversion") : new Quantity(v.Value, u, q.Base);
            }
            case "base":
            {
                var x = (Quantity)a[0]; var target = (string)a[1]; var ratio = (Quantity)a[2];
                if (x.Base == target || x.Base is null) return x with { Base = target };
                if (ratio.Value == 0) return Unk("base: zero ratio");
                return new Quantity(target == "Primary" ? x.Value * ratio.Value : x.Value / ratio.Value, x.Unit, target);
            }
            case "days_between": return new Quantity((decimal)((DateTimeOffset)a[1] - (DateTimeOffset)a[0]).TotalSeconds / 86400m);
            case "add":
            {
                var d = a[1] is Duration du ? du : new Duration(((Quantity)a[1]).Value, ((Quantity)a[1]).Unit!);
                return Values.AddDuration((DateTimeOffset)a[0], d);
            }
            case "year": return new Quantity(((DateTimeOffset)a[0]).Year);
            case "month": return new Quantity(((DateTimeOffset)a[0]).Month);
            case "day": return new Quantity(((DateTimeOffset)a[0]).Day);
            case "len": return new Quantity(((string)a[0]).Length);
            case "lower": return ((string)a[0]).ToLowerInvariant();
            case "upper": return ((string)a[0]).ToUpperInvariant();
            case "trim": return ((string)a[0]).Trim();
            case "substr":
            {
                var s = (string)a[0]; var start = (int)((Quantity)a[1]).Value; var len = (int)((Quantity)a[2]).Value;
                var from = Math.Max(start - 1, 0);
                if (from >= s.Length || len <= 0) return "";
                return s.Substring(from, Math.Min(len, s.Length - from));
            }
            case "startswith": return ((string)a[0]).StartsWith((string)a[1], StringComparison.Ordinal);
            case "endswith": return ((string)a[0]).EndsWith((string)a[1], StringComparison.Ordinal);
            case "contains": return ((string)a[0]).Contains((string)a[1], StringComparison.Ordinal);
            case "decode":
            {
                var m = Regex.Match((string)a[1], (string)a[0], RegexOptions.CultureInvariant);
                if (!m.Success) return Unk("decode: no match");
                var g = m.Groups[(int)((Quantity)a[2]).Value];
                return g.Success ? g.Value : Unk("decode: empty group");
            }
            case "number":
            {
                if (decimal.TryParse(((string)a[0]).Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var d)) return new Quantity(d);
                return Unk("number: not numeric");
            }
            case "text": return Values.TextOf(a[0]);
            default: throw new FormulaException(ErrorCodes.UnknownFunction, fn);
        }
    }

    object EvCadence(JsonObject n, object? subj, Dictionary<string, object> env)
    {
        var k = S(n["cadence"]);
        if (k == "interval")
        {
            object anchor = n["from"] is JsonObject from ? Ev(from, subj, env) : env.GetValueOrDefault("effective") ?? Unknown.Value;
            if (IsU(anchor)) return Unk("cadence anchor");
            return Values.AddDuration((DateTimeOffset)anchor, (Duration)LitValue((JsonObject)n["every"]!));
        }
        if (k == "calendar")
        {
            var b = _at;
            DateTimeOffset end = S(n["period"]) switch
            {
                "year" => new DateTimeOffset(b.Year + 1, 1, 1, 0, 0, 0, b.Offset),
                "quarter" => ((b.Month - 1) / 3) == 3 ? new DateTimeOffset(b.Year + 1, 1, 1, 0, 0, 0, b.Offset) : new DateTimeOffset(b.Year, 3 * ((b.Month - 1) / 3 + 1) + 1, 1, 0, 0, 0, b.Offset),
                _ => b.Month == 12 ? new DateTimeOffset(b.Year + 1, 1, 1, 0, 0, 0, b.Offset) : new DateTimeOffset(b.Year, b.Month + 1, 1, 0, 0, 0, b.Offset),
            };
            return n["offset"] is JsonObject off ? Values.AddDuration(end, (Duration)LitValue(off)) : end;
        }
        if (k == "event")
        {
            var evAt = env.GetValueOrDefault("event") ?? Unknown.Value;
            return IsU(evAt) ? Unknown.Value : Values.AddDuration((DateTimeOffset)evAt, (Duration)LitValue((JsonObject)n["within"]!));
        }
        return env.GetValueOrDefault("effective") ?? Unknown.Value;
    }

    public static object LitValue(JsonObject n)
    {
        if (n["lit"] is null && !n.ContainsKey("t")) return Unknown.Value;
        var t = S(n["t"]);
        return t switch
        {
            "num" => new Quantity(Values.ParseDecimal(S(n["lit"])), n["u"]?.GetValue<string>(), n["b"]?.GetValue<string>()),
            "dur" => new Duration(Values.ParseDecimal(S(n["lit"])), S(n["u"])),
            "date" => Values.ParseDateTime(S(n["lit"])),
            "bool" => n["lit"]!.GetValue<bool>(),
            _ => S(n["lit"]),
        };
    }

    static bool Like(string s, string pattern)
    {
        var rx = "^" + string.Concat(pattern.Select(c => c == '%' ? ".*" : c == '_' ? "." : Regex.Escape(c.ToString()))) + "$";
        return Regex.IsMatch(s, rx, RegexOptions.Singleline | RegexOptions.CultureInvariant);
    }
}
