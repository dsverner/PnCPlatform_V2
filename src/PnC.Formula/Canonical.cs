using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace PnC.Formula;

/// <summary>Canonical form (FORMULA-GRAMMAR.md §8), grammar-0 upgrade (§9) and fact-name extraction.</summary>
public static class Canonical
{
    public const int Grammar = 1;

    static readonly string[] KeyOrder =
    {
        "g", "lit", "t", "u", "b", "fact", "p", "from", "at", "var", "op", "a", "x", "l", "r", "set", "map", "fn", "body",
        "cadence", "every", "period", "offset", "within",
    };

    static readonly JsonSerializerOptions Compact = new()
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        WriteIndented = false,
    };

    static int Rank(string k) { var i = Array.IndexOf(KeyOrder, k); return i < 0 ? 99 : i; }

    public static JsonNode? Order(JsonNode? node)
    {
        switch (node)
        {
            case JsonObject o:
            {
                var keys = o.Select(kv => kv.Key).OrderBy(Rank).ThenBy(k => k, StringComparer.Ordinal).ToList();
                var n = new JsonObject();
                foreach (var k in keys) n[k] = Order(o[k])?.DeepClone();
                return n;
            }
            case JsonArray a:
            {
                var n = new JsonArray();
                foreach (var x in a) n.Add(Order(x)?.DeepClone());
                return n;
            }
            default:
                return node?.DeepClone();
        }
    }

    /// <summary>The text that is stored and hashed: ordered keys, no whitespace, non-ASCII unescaped, "g" at the root.</summary>
    public static string ToCanonical(JsonNode node, bool root = true)
    {
        var n = Order(node)!;
        if (root && n is JsonObject o && !o.ContainsKey("g"))
        {
            var withG = new JsonObject { ["g"] = Grammar };
            foreach (var kv in o) withG[kv.Key] = kv.Value?.DeepClone();
            n = Order(withG)!;
        }
        return n.ToJsonString(Compact);
    }

    /// <summary>Grammar 0 (the gate's predicate tree, or a rule payload holding one) → grammar 1. Idempotent on grammar 1.</summary>
    public static JsonObject Upgrade(JsonObject payload)
    {
        if (payload["g"] is JsonValue gv && gv.TryGetValue<int>(out var g) && g == Grammar) return payload;
        if (payload.ContainsKey("predicate") || payload.ContainsKey("subjectKinds"))
        {
            var outp = new JsonObject { ["g"] = Grammar };
            foreach (var kv in payload) if (kv.Key != "predicate") outp[kv.Key] = kv.Value?.DeepClone();
            if (payload["predicate"] is JsonObject pred) outp["scope"] = UpNode(pred);
            return outp;
        }
        if (IsG0(payload))
        {
            var up = UpNode(payload);
            var outp = new JsonObject { ["g"] = Grammar };
            foreach (var kv in up) outp[kv.Key] = kv.Value?.DeepClone();
            return outp;
        }
        return payload;
    }

    static bool IsG0(JsonNode? n) => n is JsonObject o &&
        (o.ContainsKey("all") || o.ContainsKey("any") || (o.ContainsKey("not") && !o.ContainsKey("op")) || (o.ContainsKey("fact") && o.ContainsKey("op")));

    static JsonObject UpNode(JsonObject n)
    {
        if (!IsG0(n)) return n;
        if (n.ContainsKey("all") || n.ContainsKey("any"))
        {
            var isAll = n.ContainsKey("all");
            var parts = ((JsonArray)n[isAll ? "all" : "any"]!).Select(x => (JsonNode)UpNode((JsonObject)x!.DeepClone())).ToList();
            if (parts.Count == 1) return (JsonObject)parts[0];
            var a = new JsonArray(); foreach (var p in parts) a.Add(p);
            return new JsonObject { ["op"] = isAll ? "and" : "or", ["a"] = a };
        }
        if (n.ContainsKey("not")) return new JsonObject { ["op"] = "not", ["x"] = UpNode((JsonObject)n["not"]!.DeepClone()) };
        var op = n["op"]!.GetValue<string>();
        var v = n["value"];
        if (op == "in")
        {
            var set = new JsonArray(); foreach (var x in (JsonArray)v!) set.Add(UpLit(x));
            return new JsonObject { ["op"] = "in", ["l"] = new JsonObject { ["fact"] = n["fact"]!.GetValue<string>() }, ["r"] = new JsonObject { ["set"] = set } };
        }
        return new JsonObject { ["op"] = op, ["l"] = new JsonObject { ["fact"] = n["fact"]!.GetValue<string>() }, ["r"] = UpLit(v) };
    }

    static JsonObject UpLit(JsonNode? v)
    {
        if (v is null) return new JsonObject { ["lit"] = null };
        var val = v.AsValue();
        if (val.TryGetValue<bool>(out var b)) return new JsonObject { ["lit"] = b, ["t"] = "bool" };
        if (val.TryGetValue<string>(out var s)) return new JsonObject { ["lit"] = s, ["t"] = "text" };
        if (val.TryGetValue<decimal>(out var d)) return Parser.Num(Values.DecText(d));
        return new JsonObject { ["lit"] = val.ToJsonString(), ["t"] = "text" };
    }

    /// <summary>Every fact name a node references, at any depth (mirrors compliance.fPayloadFactNames).</summary>
    public static HashSet<string> FactNames(JsonNode? node)
    {
        var outp = new HashSet<string>(StringComparer.Ordinal);
        void Walk(JsonNode? n)
        {
            switch (n)
            {
                case JsonObject o:
                    if (o["fact"] is JsonValue fv && fv.TryGetValue<string>(out var f)) outp.Add(f);
                    foreach (var kv in o) Walk(kv.Value);
                    break;
                case JsonArray a:
                    foreach (var x in a) Walk(x);
                    break;
            }
        }
        Walk(node);
        return outp;
    }
}
