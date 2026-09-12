using System.Text.Json;
using System.Text.Json.Serialization;
using PnC.Api.Data;

namespace PnC.Api.Security;

// docs/design/API.md §4. (schema, object) → "<SubjectClass>.<Verb>", from api-permissions.json,
// which ships beside the binary and is versioned with the release. Rules, in order: an explicit
// entry wins (null = not callable); a generated procedure is classified by suffix; a hand-written
// procedure absent from the map is NOT callable; a view is <Class>.Read.

public sealed class PermissionMap
{
    private sealed class File
    {
        [JsonPropertyName("subjectClassBySchema")] public Dictionary<string, string> BySchema { get; set; } = new();
        [JsonPropertyName("subjectClassByPrefix")] public Dictionary<string, string> ByPrefix { get; set; } = new();
        [JsonPropertyName("procedures")] public Dictionary<string, string?> Procedures { get; set; } = new();
        [JsonPropertyName("subjectKeys")] public List<string> SubjectKeys { get; set; } = new();
    }

    private readonly File _f;
    public IReadOnlyList<string> SubjectKeys => _f.SubjectKeys;

    private PermissionMap(File f) => _f = f;

    public static PermissionMap Load(string path)
    {
        var text = System.IO.File.ReadAllText(path);
        var f = JsonSerializer.Deserialize<File>(text, new JsonSerializerOptions { ReadCommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true })
                ?? throw new InvalidOperationException($"{path} is empty.");
        return new PermissionMap(f);
    }

    /// <summary>
    /// The map cannot drift from the schema: every entry that makes a procedure callable must name one the
    /// catalogue holds. An entry mapped to null (not callable) may name a procedure the API's identity cannot
    /// see — sys.procedures shows only what the login has rights on, and app_execute has none on the platform
    /// schema's procedures (Roles.sql) — so those are reported, never fatal. Found on VGS-VM02, 2026-09-11.
    /// </summary>
    public IReadOnlyList<string> Validate(Catalog catalog)
    {
        var missing = _f.Procedures.Where(kv => kv.Value is not null && !catalog.Procedures.ContainsKey(kv.Key)).Select(kv => kv.Key).ToList();
        if (missing.Count > 0)
            throw new InvalidOperationException("api-permissions.json makes procedures callable that are not in the catalogue: " + string.Join(", ", missing));
        var unseen = _f.Procedures.Where(kv => kv.Value is null && !catalog.Procedures.ContainsKey(kv.Key)).Select(kv => kv.Key).ToList();
        var unknownSchemas = _f.BySchema.Keys.Where(s => !catalog.Schemas.Contains(s, StringComparer.OrdinalIgnoreCase)).ToList();
        if (unknownSchemas.Count > 0)
            throw new InvalidOperationException("api-permissions.json maps schemas that are not served: " + string.Join(", ", unknownSchemas));
        return unseen;
    }

    public string? SubjectClass(string schema, string objectName)
    {
        // prefix rules first: "document.ConfigurationFile" covers ConfigurationFile, ConfigurationFileRevision, vConfigurationFile…
        var bare = objectName.StartsWith('v') && objectName.Length > 1 && char.IsUpper(objectName[1]) ? objectName[1..] : objectName;
        foreach (var (prefix, cls) in _f.ByPrefix)
        {
            var dot = prefix.IndexOf('.');
            if (dot < 0) continue;
            if (prefix[..dot].Equals(schema, StringComparison.OrdinalIgnoreCase) && bare.StartsWith(prefix[(dot + 1)..], StringComparison.OrdinalIgnoreCase))
                return cls;
        }
        return _f.BySchema.TryGetValue(schema.ToLowerInvariant(), out var c) ? c : null;
    }

    private static readonly string[] ModifySuffixes = ["_Add", "_Revise", "_Update", "_Append", "_Upsert"];
    private static readonly string[] ArchiveSuffixes = ["_SoftDelete", "_Deactivate"];

    /// <summary>Permission code for a procedure, or null when it is not callable over HTTP.</summary>
    public string? ForProcedure(string schema, string name)
    {
        if (_f.Procedures.TryGetValue($"{schema}.{name}", out var explicitCode)) return explicitCode;   // may be null: not callable
        var cls = SubjectClass(schema, name);
        if (cls is null) return null;
        var idx = name.LastIndexOf('_');
        if (idx < 0) return null;                                       // hand-written and unmapped: not callable
        var suffix = name[idx..];
        if (ModifySuffixes.Contains(suffix, StringComparer.Ordinal)) return $"{cls}.Modify";
        if (ArchiveSuffixes.Contains(suffix, StringComparer.Ordinal)) return $"{cls}.Archive";
        return null;
    }

    /// <summary>Permission code for a view or as-of function: &lt;Class&gt;.Read.</summary>
    public string? ForView(string schema, string name)
    {
        var cls = SubjectClass(schema, name);
        return cls is null ? null : $"{cls}.Read";
    }
}
