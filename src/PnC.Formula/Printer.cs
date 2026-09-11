using System.Text.Json.Nodes;

namespace PnC.Formula;

/// <summary>AST → normalised text (the inverse of the parser), with the reference's precedence and parenthesis rules.</summary>
public static class Printer
{
    static readonly Dictionary<string, int> Prec = new()
    {
        ["or"] = 1, ["and"] = 2, ["not"] = 3, ["="] = 4, ["<>"] = 4, ["<"] = 4, ["<="] = 4, [">"] = 4, [">="] = 4, ["in"] = 4, ["like"] = 4, ["matches"] = 4,
        ["isunknown"] = 4, ["+"] = 5, ["-"] = 5, ["*"] = 6, ["/"] = 6, ["neg"] = 7, ["^"] = 8,
    };

    static string S(JsonNode? n) => n!.GetValue<string>();

    public static string Print(JsonObject n, int parent = 0)
    {
        if (n.ContainsKey("lit")) return PrintLit(n);
        if (n.ContainsKey("fn"))
        {
            var a = (JsonArray)n["a"]!;
            if (n.ContainsKey("var") && n.ContainsKey("body"))
                return $"{S(n["fn"])}({Print((JsonObject)a[0]!)}, {S(n["var"])} -> {Print((JsonObject)n["body"]!)})";
            return $"{S(n["fn"])}(" + string.Join(", ", a.Select(x => Print((JsonObject)x!))) + ")";
        }
        if (n.ContainsKey("var")) return S(n["var"]);
        if (n.ContainsKey("fact"))
        {
            var s = S(n["fact"]);
            if (n["p"] is JsonObject p) s += "[" + string.Join(", ", p.Select(kv => $"{kv.Key}={PrintLit((JsonObject)kv.Value!)}")) + "]";
            if (n["from"] is JsonObject from) s = Print(from, 9) + "." + s;
            if (n["at"] is JsonObject at) s += " at (" + Print(at) + ")";
            return s;
        }
        if (n["set"] is JsonArray set) return "{" + string.Join(", ", set.Select(x => Print((JsonObject)x!))) + "}";
        if (n["map"] is JsonArray map) return "{" + string.Join(", ", map.Select(kv => Print((JsonObject)kv![0]!) + ": " + Print((JsonObject)kv[1]!))) + "}";
        if (n.ContainsKey("cadence")) return PrintCadence(n);
        var op = S(n["op"]);
        var pr = Prec[op];
        string outp;
        if (op is "and" or "or") outp = string.Join($" {op} ", ((JsonArray)n["a"]!).Select(x => Print((JsonObject)x!, pr + 1)));
        else if (op == "not") outp = "not " + Print((JsonObject)n["x"]!, pr);
        else if (op == "neg") outp = "-" + Print((JsonObject)n["x"]!, pr);
        else if (op == "isunknown") outp = Print((JsonObject)n["x"]!, pr + 1) + " is unknown";
        else if (op == "^")
        {
            var l = Print((JsonObject)n["l"]!, pr + 1);
            if (l.StartsWith('-')) l = "(" + l + ")";
            outp = l + " ^ " + Print((JsonObject)n["r"]!, pr);
        }
        else outp = Print((JsonObject)n["l"]!, pr) + $" {op} " + Print((JsonObject)n["r"]!, pr + 1);
        return pr < parent ? "(" + outp + ")" : outp;
    }

    public static string PrintLit(JsonObject n)
    {
        if ((n["lit"] is null) && !n.ContainsKey("t")) return "unknown";
        var t = S(n["t"]);
        switch (t)
        {
            case "num": return S(n["lit"]) + (n.ContainsKey("u") ? " " + S(n["u"]) : "") + (n.ContainsKey("b") ? "@" + S(n["b"]) : "");
            case "dur": return S(n["lit"]) + " " + S(n["u"]);
            case "text": return "'" + S(n["lit"]).Replace("'", "''") + "'";
            case "bool": return n["lit"]!.GetValue<bool>() ? "true" : "false";
            case "date": return S(n["lit"]);
            default: throw new FormulaException(ErrorCodes.Syntax, $"unknown literal type {t}");
        }
    }

    static string PrintCadence(JsonObject n)
    {
        var k = S(n["cadence"]);
        if (k == "once") return "once";
        if (k == "event") return "within " + PrintLit((JsonObject)n["within"]!) + " of event";
        if (k == "calendar") return "every calendar_" + S(n["period"]) + (n.ContainsKey("offset") ? " offset " + PrintLit((JsonObject)n["offset"]!) : "");
        var s = "every " + PrintLit((JsonObject)n["every"]!);
        if (n.ContainsKey("from"))
            s += " from " + (n["from"] is JsonValue fv && fv.TryGetValue<string>(out var eff) && eff == "effective" ? "effective" : Print((JsonObject)n["from"]!));
        return s;
    }
}
