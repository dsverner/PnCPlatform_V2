using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace PnC.Api.Definitions;

/// <summary>
/// The subset of JSON Schema that docs/design/procedure.schema.json and workflow.schema.json use, evaluated against a
/// document: type, required, properties, additionalProperties (false or a schema), enum, const, oneOf, $ref into $defs,
/// items, minItems, minimum, minLength, maxLength, pattern, default (ignored). The schema files stay the single
/// authoring contract (PROCEDURE-ENGINE §8); no schema library is added (API.md §10: one package, PnCPlatform #239).
/// Every violation is reported with its JSON path, so an author sees all of them at once.
/// </summary>
public sealed class SchemaCheck
{
    private readonly JsonObject _root;
    private readonly JsonObject _defs;

    public SchemaCheck(JsonObject schema)
    {
        _root = schema;
        _defs = schema["$defs"] as JsonObject ?? new JsonObject();
    }

    public sealed record Violation(string Path, string Message);

    public IReadOnlyList<Violation> Validate(JsonNode? document)
    {
        var errors = new List<Violation>();
        Check(_root, document, "$", errors, 0);
        return errors;
    }

    private JsonObject Resolve(JsonObject schema)
    {
        if (schema["$ref"] is JsonValue r && r.TryGetValue<string>(out var s) && s.StartsWith("#/$defs/", StringComparison.Ordinal))
            return _defs[s["#/$defs/".Length..]] as JsonObject ?? throw new InvalidOperationException($"schema $ref {s} not found");
        return schema;
    }

    private static string TypeOf(JsonNode? n) => n switch
    {
        null => "null",
        JsonObject => "object",
        JsonArray => "array",
        JsonValue v when v.TryGetValue<bool>(out _) => "boolean",
        JsonValue v when v.TryGetValue<string>(out _) => "string",
        JsonValue v when v.TryGetValue<decimal>(out var d) => d == Math.Floor(d) ? "integer" : "number",
        _ => "unknown",
    };

    private void Check(JsonObject schemaIn, JsonNode? node, string path, List<Violation> errors, int depth)
    {
        if (depth > 64) { errors.Add(new(path, "document nests too deeply")); return; }
        var schema = Resolve(schemaIn);

        if (schema["oneOf"] is JsonArray oneOf)
        {
            var matches = 0; List<Violation>? last = null;
            foreach (var alt in oneOf)
            {
                var e = new List<Violation>();
                Check((JsonObject)alt!, node, path, e, depth + 1);
                if (e.Count == 0) matches++; else last = e;
            }
            if (matches != 1) errors.Add(new(path, matches == 0 ? "matches none of the allowed forms" + (last is { Count: > 0 } ? ": " + last[0].Message : "") : "matches more than one of the allowed forms"));
            return;
        }

        if (schema["type"] is JsonValue tv && tv.TryGetValue<string>(out var type))
        {
            var actual = TypeOf(node);
            var ok = type switch
            {
                "number" => actual is "number" or "integer",
                "integer" => actual == "integer",
                _ => actual == type,
            };
            if (!ok) { errors.Add(new(path, $"must be {type}, is {actual}")); return; }
        }
        if (schema["const"] is JsonValue cv && !JsonNode.DeepEquals(cv, node))
            errors.Add(new(path, $"must be {cv.ToJsonString()}"));
        if (schema["enum"] is JsonArray en && !en.Any(x => JsonNode.DeepEquals(x, node)))
            errors.Add(new(path, $"must be one of {string.Join(", ", en.Select(x => x?.ToJsonString()))}"));

        switch (node)
        {
            case JsonValue v when v.TryGetValue<string>(out var s):
                if (schema["minLength"] is JsonValue ml && ml.TryGetValue<int>(out var min) && s.Length < min) errors.Add(new(path, $"must be at least {min} character(s)"));
                if (schema["maxLength"] is JsonValue xl && xl.TryGetValue<int>(out var max) && s.Length > max) errors.Add(new(path, $"must be at most {max} character(s)"));
                if (schema["pattern"] is JsonValue pv && pv.TryGetValue<string>(out var pat) && !Regex.IsMatch(s, pat, RegexOptions.None, TimeSpan.FromSeconds(1)))
                    errors.Add(new(path, $"must match {pat}"));
                break;
            case JsonValue v when v.TryGetValue<decimal>(out var d):
                if (schema["minimum"] is JsonValue mv && mv.TryGetValue<decimal>(out var minimum) && d < minimum) errors.Add(new(path, $"must be at least {minimum}"));
                break;
            case JsonArray a:
                if (schema["minItems"] is JsonValue mi && mi.TryGetValue<int>(out var minItems) && a.Count < minItems) errors.Add(new(path, $"must have at least {minItems} item(s)"));
                if (schema["items"] is JsonObject items)
                    for (var i = 0; i < a.Count; i++) Check(items, a[i], $"{path}[{i}]", errors, depth + 1);
                break;
            case JsonObject o:
                var props = schema["properties"] as JsonObject;
                if (schema["required"] is JsonArray req)
                    foreach (var r in req)
                        if (!o.ContainsKey(r!.GetValue<string>())) errors.Add(new(path, $"missing required property '{r.GetValue<string>()}'"));
                foreach (var (k, val) in o)
                {
                    var childPath = $"{path}.{k}";
                    if (props is not null && props[k] is JsonObject ps) { Check(ps, val, childPath, errors, depth + 1); continue; }
                    switch (schema["additionalProperties"])
                    {
                        case JsonValue ap when ap.TryGetValue<bool>(out var allowed) && !allowed:
                            errors.Add(new(childPath, "is not a property of this object")); break;
                        case JsonObject aps:
                            Check(aps, val, childPath, errors, depth + 1); break;
                    }
                }
                break;
        }
    }
}
