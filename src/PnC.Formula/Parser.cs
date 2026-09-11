using System.Text.Json.Nodes;

namespace PnC.Formula;

/// <summary>
/// Recursive-descent parser producing the canonical AST as JsonObject nodes with the reference implementation's
/// keys (FORMULA-GRAMMAR.md §8). Mirrors docs/schema/grammar/formula.py class Parser.
/// </summary>
public sealed class Parser
{
    static readonly string[] Compare = { "=", "<>", "<", "<=", ">", ">=" };
    public static readonly string[] Quant = { "any", "all", "select", "where" };

    readonly List<Tok> _t;
    int _i;
    readonly List<string> _scope = new();

    public Parser(string text) { _t = Lexer.Tokenize(text); }

    public static JsonObject Parse(string text) => new Parser(text).ParseExpression();
    public static JsonObject ParseCadence(string text) => new Parser(text).ParseCadenceNode();

    Tok Peek() => _t[_i];

    Tok Take(string? kind = null, string? value = null)
    {
        var tok = Peek();
        if ((kind is not null && tok.Kind != kind) || (value is not null && tok.Value != value))
            throw new FormulaException(ErrorCodes.Syntax, $"expected {value ?? kind}, found '{(tok.Value == "" ? tok.Kind : tok.Value)}'", tok.Pos);
        _i++;
        return tok;
    }

    bool At(string kind, string? value = null) { var tok = Peek(); return tok.Kind == kind && (value is null || tok.Value == value); }

    public JsonObject ParseExpression()
    {
        var e = POr();
        if (!At("eof")) throw new FormulaException(ErrorCodes.Syntax, $"unexpected '{Peek().Value}'", Peek().Pos);
        return e;
    }

    static JsonObject Obj(params (string k, JsonNode? v)[] kv)
    {
        var o = new JsonObject();
        foreach (var (k, v) in kv) o[k] = v;
        return o;
    }

    static JsonArray Arr(IEnumerable<JsonNode> items) { var a = new JsonArray(); foreach (var x in items) a.Add(x); return a; }

    JsonObject POr()
    {
        var parts = new List<JsonNode> { PAnd() };
        while (At("kw", "or")) { Take(); parts.Add(PAnd()); }
        return parts.Count == 1 ? (JsonObject)parts[0] : Obj(("op", "or"), ("a", Arr(parts)));
    }

    JsonObject PAnd()
    {
        var parts = new List<JsonNode> { PNot() };
        while (At("kw", "and")) { Take(); parts.Add(PNot()); }
        return parts.Count == 1 ? (JsonObject)parts[0] : Obj(("op", "and"), ("a", Arr(parts)));
    }

    JsonObject PNot()
    {
        if (At("kw", "not")) { Take(); return Obj(("op", "not"), ("x", PNot())); }
        return PCompare();
    }

    JsonObject PCompare()
    {
        var l = PAdd();
        var tok = Peek();
        if (tok.Kind == "op" && Compare.Contains(tok.Value)) { Take(); return Obj(("op", tok.Value), ("l", l), ("r", PAdd())); }
        if (tok.Kind == "kw" && tok.Value is "in" or "like" or "matches") { Take(); return Obj(("op", tok.Value), ("l", l), ("r", PAdd())); }
        if (tok.Kind == "kw" && tok.Value == "is")
        {
            Take();
            bool neg = false;
            if (At("kw", "not")) { Take(); neg = true; }
            JsonObject node;
            if (At("kw", "unknown")) { Take(); node = Obj(("op", "isunknown"), ("x", l)); }
            else if (At("name", "empty")) { Take(); node = Obj(("op", "="), ("l", Obj(("fn", "count"), ("a", Arr(new JsonNode[] { l })))), ("r", Num("0"))); }
            else throw new FormulaException(ErrorCodes.Syntax, "expected 'unknown' or 'empty' after 'is'", Peek().Pos);
            return neg ? Obj(("op", "not"), ("x", node)) : node;
        }
        return l;
    }

    JsonObject PAdd()
    {
        var l = PMul();
        while (At("op", "+") || At("op", "-")) { var o = Take().Value; l = Obj(("op", o), ("l", l), ("r", PMul())); }
        return l;
    }

    JsonObject PMul()
    {
        var l = PUnary();
        while (At("op", "*") || At("op", "/")) { var o = Take().Value; l = Obj(("op", o), ("l", l), ("r", PUnary())); }
        return l;
    }

    JsonObject PUnary() => PPow();

    JsonObject PPow()
    {
        if (At("op", "-"))
        {
            Take();
            var x = PPow();
            if (x.ContainsKey("lit") && x["t"]?.GetValue<string>() is "num" or "dur")
            {
                var lit = x["lit"]!.GetValue<string>();
                var copy = (JsonObject)x.DeepClone();
                copy["lit"] = lit.StartsWith('-') ? lit[1..] : "-" + lit;
                return copy;
            }
            return Obj(("op", "neg"), ("x", x));
        }
        var b = PPostfix();
        if (At("op", "^")) { Take(); return Obj(("op", "^"), ("l", b), ("r", PUnary())); }
        return b;
    }

    JsonObject PPostfix()
    {
        var e = PPrimary();
        while (true)
        {
            if (At("op", ".") && (e.ContainsKey("fact") || e.ContainsKey("var")))
            {
                Take();
                var name = Take("name").Value;
                var node = Obj(("fact", name));
                if (At("op", "[")) node["p"] = PParams();
                node["from"] = e;
                e = node;
            }
            else if (At("kw", "at") && e.ContainsKey("fact"))
            {
                Take(); Take("op", "(");
                e["at"] = POr();
                Take("op", ")");
            }
            else return e;
        }
    }

    JsonObject PParams()
    {
        Take("op", "[");
        var p = new JsonObject();
        while (true)
        {
            var k = Take("name").Value;
            Take("op", "=");
            var v = PPrimary();
            if (!v.ContainsKey("lit")) throw new FormulaException(ErrorCodes.Syntax, "a parameter value must be a literal", Peek().Pos);
            p[k] = v;
            if (At("op", ",")) { Take(); continue; }
            Take("op", "]");
            return p;
        }
    }

    JsonObject PPrimary()
    {
        var tok = Peek();
        if (tok.Kind == "op" && tok.Value == "(") { Take(); var e = POr(); Take("op", ")"); return e; }
        if (tok.Kind == "num") { Take(); return Num(tok.Value); }
        if (tok.Kind == "qty")
        {
            Take();
            var (val, u, b) = tok.Qty!.Value;
            if (Units.DurationUnits.Contains(u))
            {
                if (b is not null) throw new FormulaException(ErrorCodes.Syntax, "a duration has no base", tok.Pos);
                return Obj(("lit", NormNum(val)), ("t", "dur"), ("u", u));
            }
            var n = Obj(("lit", NormNum(val)), ("t", "num"), ("u", u));
            if (b is not null) n["b"] = b;
            return n;
        }
        if (tok.Kind == "text") { Take(); return Obj(("lit", tok.Value[1..^1].Replace("''", "'")), ("t", "text")); }
        if (tok.Kind == "date") { Take(); return Obj(("lit", NormDate(tok.Value, tok.Pos)), ("t", "date")); }
        if (tok.Kind == "kw" && tok.Value is "true" or "false") { Take(); return Obj(("lit", tok.Value == "true"), ("t", "bool")); }
        if (tok.Kind == "kw" && tok.Value == "unknown") { Take(); return Obj(("lit", null)); }
        if (tok.Kind == "atvar") { Take(); return Obj(("var", tok.Value)); }
        if (tok.Kind == "dollar") { Take(); return Obj(("var", tok.Value)); }
        if (tok.Kind == "op" && tok.Value == "{") return PSetOrMap();
        if (tok.Kind == "name")
        {
            Take();
            if (At("op", "(")) return PCall(tok.Value);
            if (At("op", "[")) return Obj(("fact", tok.Value), ("p", PParams()));
            var dot = tok.Value.IndexOf('.');
            if (dot > 0)
            {
                var head = tok.Value[..dot];
                var rest = tok.Value[(dot + 1)..];
                if (_scope.Contains(head)) return Obj(("fact", rest), ("from", Obj(("var", head))));
                return Obj(("fact", tok.Value));
            }
            return Obj(("var", tok.Value));        // a bare name is a variable (lambda- or host-bound); facts are dotted
        }
        throw new FormulaException(ErrorCodes.Syntax, $"unexpected '{(tok.Value == "" ? tok.Kind : tok.Value)}'", tok.Pos);
    }

    JsonObject PSetOrMap()
    {
        Take("op", "{");
        if (At("op", "}")) { Take(); return Obj(("set", new JsonArray())); }
        var first = POr();
        if (At("op", ":"))
        {
            Take();
            var pairs = new JsonArray { new JsonArray(first, POr()) };
            while (At("op", ",")) { Take(); var k = POr(); Take("op", ":"); pairs.Add(new JsonArray(k, POr())); }
            Take("op", "}");
            return Obj(("map", pairs));
        }
        var items = new List<JsonNode> { first };
        while (At("op", ",")) { Take(); items.Add(POr()); }
        Take("op", "}");
        return Obj(("set", Arr(items)));
    }

    JsonObject PCall(string name)
    {
        Take("op", "(");
        if (Quant.Contains(name))
        {
            var s = POr();
            Take("op", ",");
            var v = Take("name").Value;
            Take("op", "->");
            _scope.Add(v);
            var body = POr();
            _scope.RemoveAt(_scope.Count - 1);
            Take("op", ")");
            return Obj(("fn", name), ("a", Arr(new JsonNode[] { s })), ("var", v), ("body", body));
        }
        var args = new List<JsonNode>();
        if (!At("op", ")"))
        {
            args.Add(POr());
            while (At("op", ",")) { Take(); args.Add(POr()); }
        }
        Take("op", ")");
        return Obj(("fn", name), ("a", Arr(args)));
    }

    // ---- cadence (FORMULA-GRAMMAR.md §6)
    public JsonObject ParseCadenceNode()
    {
        var node = PCadence();
        if (!At("eof")) throw new FormulaException(ErrorCodes.Syntax, $"unexpected '{Peek().Value}'", Peek().Pos);
        return node;
    }

    JsonObject PCadence()
    {
        if (At("kw", "once")) { Take(); return Obj(("cadence", "once")); }
        if (At("kw", "within"))
        {
            Take();
            var d = PPrimary();
            if (d["t"]?.GetValue<string>() != "dur") throw new FormulaException(ErrorCodes.Syntax, "expected a duration after 'within'", Peek().Pos);
            Take("kw", "of"); Take("kw", "event");
            return Obj(("cadence", "event"), ("within", d));
        }
        Take("kw", "every");
        var tok = Peek();
        if (tok.Kind == "kw" && tok.Value.StartsWith("calendar_"))
        {
            Take();
            var node = Obj(("cadence", "calendar"), ("period", tok.Value["calendar_".Length..]));
            if (At("kw", "offset")) { Take(); node["offset"] = PPrimary(); }
            return node;
        }
        var dd = PPrimary();
        if (dd["t"]?.GetValue<string>() != "dur") throw new FormulaException(ErrorCodes.Syntax, "expected a duration after 'every'", tok.Pos);
        var nd = Obj(("cadence", "interval"), ("every", dd));
        if (At("kw", "from"))
        {
            Take();
            if (At("kw", "effective")) { Take(); nd["from"] = "effective"; }
            else nd["from"] = PPostfix();
        }
        return nd;
    }

    // ---- literal helpers
    public static string NormNum(string s)
    {
        try { return Values.DecText(Values.ParseDecimal(s)); }
        catch (FormatException) { throw new FormulaException(ErrorCodes.Syntax, $"bad number '{s}'"); }
        catch (OverflowException) { throw new FormulaException(ErrorCodes.Syntax, $"bad number '{s}'"); }
    }

    public static JsonObject Num(string s, string? u = null, string? b = null)
    {
        var n = Obj(("lit", NormNum(s)), ("t", "num"));
        if (u is not null) n["u"] = u;
        if (b is not null) n["b"] = b;
        return n;
    }

    static string NormDate(string s, int pos)
    {
        try { return Values.FormatDateTime(Values.ParseDateTime(s)); }
        catch (FormatException) { throw new FormulaException(ErrorCodes.Syntax, $"bad datetime '{s}'", pos); }
    }
}
