using System.Data;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.SqlClient;
using PnC.Formula;

namespace PnC.Api.Engine;

// PROCEDURE-ENGINE §7 (W4, decision #107). The evaluator's window on the database: one compliance.fFactRead call per
// read, the typed-value JSON decoded to the grammar's values. Consulted the predecessor's DbFactReader (PnCPlatform
// src/PnC.Api/Data/DbFactReader.cs, 2026-09-12); rewritten here with the procedure engine's resolution scope:
//   - step.*, branch.* and procedure.outcome read against the procedure instance whatever the ambient subject is
//     (inside a foreach the subject is the member; the step facts still belong to the run), with the current member
//     and pass supplied when the expression omits them ("the current member and the current pass first, §7");
//   - step.capture is typed by the document (the capture's declared type) after the database's best-effort read;
//   - procedure.<name> and input.<name> are the run's own bindings (Produced / Inputs JSON), never a database read.
// The reader is synchronous because the evaluator is; it holds the request's own connection.

public sealed class InstanceContext
{
    public required Guid InstanceEntityId { get; init; }
    public required JsonObject Document { get; init; }
    public JsonObject Produced { get; init; } = new();
    public JsonObject Inputs { get; init; } = new();
    /// <summary>The member subject of the block being evaluated (a foreach body), or null at the instance level.</summary>
    public string? CurrentMember { get; set; }
    public int? CurrentPass { get; set; }
    /// <summary>step id → field name → the capture's valueType node.</summary>
    public IReadOnlyDictionary<string, IReadOnlyDictionary<string, JsonObject>> CaptureTypes { get; init; } = new Dictionary<string, IReadOnlyDictionary<string, JsonObject>>();
}

public sealed class DbFactReader(SqlConnection connection, InstanceContext? context) : IFactReader
{
    public object? Read(object? subject, string name, IReadOnlyDictionary<string, object> parameters, DateTimeOffset at)
    {
        // the run's own bindings
        if (context is not null)
        {
            if (name.StartsWith("procedure.", StringComparison.Ordinal) && name != "procedure.outcome")
            {
                var n = name["procedure.".Length..];
                var v = context.Produced[n]?.GetValue<string>();
                if (v is null) return Unknown.Value;
                var kind = ProducesKind(context.Document, n) ?? "Any";
                return new Ref(v.ToLowerInvariant(), kind);
            }
            if (name.StartsWith("input.", StringComparison.Ordinal))
            {
                var n = name["input.".Length..];
                var node = context.Inputs[n];
                if (node is null) return Unknown.Value;
                var vt = context.Document["inputs"]?[n] as JsonObject;
                return Typed(node, vt);
            }
        }

        var engineFact = name.StartsWith("step.", StringComparison.Ordinal) || name.StartsWith("branch.", StringComparison.Ordinal) || name == "procedure.outcome";
        object? subj = subject;
        var ps = new Dictionary<string, object>(parameters, StringComparer.Ordinal);
        if (engineFact && context is not null)
        {
            subj = context.InstanceEntityId.ToString();
            if (!ps.ContainsKey("member") && context.CurrentMember is not null) ps["member"] = context.CurrentMember;
            if (!ps.ContainsKey("pass") && context.CurrentPass is not null) ps["pass"] = new Quantity(context.CurrentPass.Value);
        }
        else if (name.StartsWith("package.", StringComparison.Ordinal) && context is not null && subj is null)
        {
            var pkg = context.Produced["package"]?.GetValue<string>();
            if (pkg is not null) subj = pkg;
        }

        var json = ReadRaw(subj, name, ps, at);
        var value = Decode(json);
        if (name == "step.capture" && context is not null && !Values.IsUnknown(value))
        {
            var id = ps.TryGetValue("id", out var idv) ? idv.ToString() : null;
            var field = ps.TryGetValue("field", out var fv) ? fv.ToString() : null;
            if (id is not null && field is not null && context.CaptureTypes.TryGetValue(id, out var fields) && fields.TryGetValue(field, out var vt))
                return Retype(value, vt);
        }
        return value;
    }

    private string? ReadRaw(object? subject, string name, IReadOnlyDictionary<string, object> parameters, DateTimeOffset at)
    {
        using var cmd = new SqlCommand("SELECT compliance.fFactRead(@s, @n, @p, @at)", connection) { CommandTimeout = 120 };
        var sid = subject switch { Ref r => r.Id, Guid g => g.ToString(), string s => s, _ => null };
        cmd.Parameters.Add("@s", SqlDbType.UniqueIdentifier).Value = sid is not null && Guid.TryParse(sid, out var gg) ? gg : DBNull.Value;
        cmd.Parameters.Add("@n", SqlDbType.NVarChar, 200).Value = name;
        var p = new JsonObject();
        foreach (var (k, v) in parameters) p[k] = ParamJson(v);
        cmd.Parameters.Add("@p", SqlDbType.NVarChar, -1).Value = p.Count == 0 ? DBNull.Value : p.ToJsonString();
        cmd.Parameters.Add("@at", SqlDbType.DateTimeOffset).Value = at;
        return cmd.ExecuteScalar() as string;
    }

    private static JsonNode? ParamJson(object v) => v switch
    {
        Quantity q => JsonValue.Create(q.Value),
        bool b => JsonValue.Create(b),
        DateTimeOffset d => JsonValue.Create(d.ToString("o")),
        Ref r => JsonValue.Create(r.Id),
        _ => JsonValue.Create(v.ToString()),
    };

    /// <summary>The typed-value JSON of fFactRead → the grammar's values (the inverse of the CLI's Typed).</summary>
    public static object Decode(string? json)
    {
        if (json is null) return Unknown.Value;
        JsonNode? n;
        try { n = JsonNode.Parse(json); } catch (JsonException) { return Unknown.Value; }
        return Decode(n);
    }

    private static object Decode(JsonNode? n)
    {
        if (n is not JsonObject o) return Unknown.Value;
        switch (o["k"]?.GetValue<string>())
        {
            case "num": return new Quantity(Values.ParseDecimal(o["v"]!.GetValue<string>()), o["u"]?.GetValue<string>(), o["b"]?.GetValue<string>());
            case "text": return o["v"]?.GetValue<string>() ?? (object)Unknown.Value;
            case "bool": return o["v"]!.GetValue<bool>();
            case "date": return Values.ParseDateTime(o["v"]!.GetValue<string>());
            case "ref": return new Ref(o["id"]!.GetValue<string>().ToLowerInvariant(), o["kind"]?.GetValue<string>() ?? "Any");
            case "set": return ((JsonArray)o["v"]!).Select(Decode).ToList();
            default: return Unknown.Value;
        }
    }

    /// <summary>A draft or input value (as the client wrote it) as the value its declared type says it is.</summary>
    public static object Typed(JsonNode node, JsonObject? vt)
    {
        var type = vt?["type"]?.GetValue<string>();
        switch (node)
        {
            case JsonArray a:
                return a.Select(x => Typed(x!, type == "set" ? new JsonObject { ["type"] = "ref", ["refKind"] = vt?["refKind"]?.DeepClone() } : vt)).ToList();
            case JsonValue v:
                if (v.TryGetValue<bool>(out var b)) return b;
                if (v.TryGetValue<decimal>(out var d)) return type == "text" ? d.ToString(CultureInfo.InvariantCulture) : new Quantity(d, vt?["unit"]?.GetValue<string>(), vt?["base"]?.GetValue<string>());
                var s = v.GetValue<string>();
                return type switch
                {
                    "num" when decimal.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var dd) => new Quantity(dd, vt?["unit"]?.GetValue<string>(), vt?["base"]?.GetValue<string>()),
                    "date" => Values.ParseDateTime(s),
                    "ref" when Guid.TryParse(s, out _) => new Ref(s.ToLowerInvariant(), vt?["refKind"]?.GetValue<string>() ?? "Any"),
                    "bool" => bool.TryParse(s, out var bb) ? bb : Unknown.Value,
                    _ => s,
                };
            default: return Unknown.Value;
        }
    }

    private static object Retype(object value, JsonObject vt)
    {
        var type = vt["type"]?.GetValue<string>();
        return (value, type) switch
        {
            (Quantity q, "num") => new Quantity(q.Value, vt["unit"]?.GetValue<string>() ?? q.Unit, vt["base"]?.GetValue<string>() ?? q.Base),
            (Quantity q, "text") => Values.DecText(q.Value),
            (Ref r, "ref") => new Ref(r.Id, vt["refKind"]?.GetValue<string>() ?? r.Kind),
            (List<object> l, "set") => l.Select(x => x is Ref r ? new Ref(r.Id, vt["refKind"]?.GetValue<string>() ?? r.Kind) : x).ToList(),
            (string s, "date") => Values.ParseDateTime(s),
            _ => value,
        };
    }

    private static string? ProducesKind(JsonObject doc, string name)
    {
        string? found = null;
        void Walk(JsonNode? n)
        {
            if (found is not null || n is null) return;
            if (n is JsonObject o)
            {
                if (o["produces"] is JsonObject p && p["as"]?.GetValue<string>() == name) { found = p["kind"]?.GetValue<string>(); return; }
                foreach (var kv in o) Walk(kv.Value);
            }
            else if (n is JsonArray a) foreach (var x in a) Walk(x);
        }
        Walk(doc["body"]);
        return found;
    }
}
