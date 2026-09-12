using System.Data;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;

namespace PnC.Api.Data;

// docs/design/API.md §3, IDENTITY.md §5. What the database exposes, read once at start from sys.*; the
// dispatcher serves exactly this and nothing else. A deploy that adds an object is followed by a restart.
// W2: every view also carries which of its columns is the subject a scoped read is decided on, and of
// what family — derived from the catalogue (the base table's registry) and the map's subject keys.

public sealed record ProcParam(string Name, string SqlType, int MaxLength, byte Precision, byte Scale, bool IsOutput, bool HasDefault);

public sealed record ProcInfo(string Schema, string Name, IReadOnlyList<ProcParam> Params)
{
    public string Key => $"{Schema}.{Name}";
}

public sealed record ViewColumn(string Name, string SqlType);

/// <summary>
/// SubjectColumn / SubjectFamily: the column a list read is scoped on and the family security.fReadableSubjects
/// answers for (Node, Asset, Record, WorkRequest, Scheme, or Any for a mixed-kind column). Null: the view has no
/// subject mapping and a read is decided on the class alone (Global only, as fHasPermission rules).
/// </summary>
public sealed record ViewInfo(string Schema, string Name, IReadOnlyList<ViewColumn> Columns, bool IsAsOfFunction, string? SubjectColumn, string? SubjectFamily)
{
    public string Key => $"{Schema}.{Name}";
    public bool HasRowSeq => Columns.Any(c => c.Name.Equals("RowSeq", StringComparison.OrdinalIgnoreCase));
}

public sealed class Catalog
{
    public IReadOnlyDictionary<string, ProcInfo> Procedures { get; }
    public IReadOnlyDictionary<string, ViewInfo> Views { get; }
    /// <summary>"schema.Table" pairs switched on in config.ReadLoggedClass (FR-6.4).</summary>
    public IReadOnlySet<string> ReadLoggedTables { get; }
    public IReadOnlyList<string> Schemas { get; }
    public DateTimeOffset LoadedAt { get; }

    /// <summary>The registries whose EntityIds are subjects security.fReadableSubjects can place, by family.</summary>
    public static readonly IReadOnlyDictionary<string, string> FamilyRegistries = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        ["location.NodeRegistry"] = "Node", ["asset.AssetRegistry"] = "Asset", ["record.RecordRegistry"] = "Record",
        ["work.WorkRequestRegistry"] = "WorkRequest", ["scheme.SchemeRegistry"] = "Scheme",
    };
    /// <summary>Subject columns a view may carry when its own rows are not subjects, in order of preference.</summary>
    public static readonly IReadOnlyList<(string Column, string Family)> SubjectColumns =
    [
        ("AssetEntityId", "Asset"), ("DeviceEntityId", "Asset"), ("NodeEntityId", "Node"), ("SchemeEntityId", "Scheme"),
        ("WorkRequestEntityId", "WorkRequest"), ("RecordEntityId", "Record"), ("SubjectEntityId", "Any"), ("MemberEntityId", "Any"),
    ];

    private Catalog(Dictionary<string, ProcInfo> procs, Dictionary<string, ViewInfo> views, HashSet<string> logged, IReadOnlyList<string> schemas)
    {
        Procedures = procs; Views = views; ReadLoggedTables = logged; Schemas = schemas; LoadedAt = DateTimeOffset.Now;
    }

    public ProcInfo? Procedure(string schema, string name) => Procedures.TryGetValue($"{schema}.{name}", out var p) ? p : null;
    public ViewInfo? View(string schema, string name) => Views.TryGetValue($"{schema}.{name}", out var v) ? v : null;

    public static Catalog Load(string connectionString, IReadOnlyList<string> schemas)
    {
        if (schemas.Count == 0) throw new InvalidOperationException("Api:Schemas is empty; the catalogue would be empty.");
        using var con = new SqlConnection(connectionString);
        con.Open();

        var inList = string.Join(", ", schemas.Select((_, i) => $"@s{i}"));
        void BindSchemas(SqlCommand c) { for (var i = 0; i < schemas.Count; i++) c.Parameters.Add($"@s{i}", SqlDbType.NVarChar, 128).Value = schemas[i]; }

        // --- procedures and their parameters
        var procs = new Dictionary<string, List<ProcParam>>(StringComparer.OrdinalIgnoreCase);
        using (var cmd = con.CreateCommand())
        {
            cmd.CommandText = $"""
                SELECT s.name, p.name, par.name, t.name, par.max_length, par.precision, par.scale, par.is_output
                FROM sys.procedures p
                JOIN sys.schemas s ON s.schema_id = p.schema_id
                LEFT JOIN sys.parameters par ON par.object_id = p.object_id
                LEFT JOIN sys.types t ON t.user_type_id = par.user_type_id
                WHERE s.name IN ({inList})
                ORDER BY s.name, p.name, par.parameter_id
                """;
            BindSchemas(cmd);
            using var r = cmd.ExecuteReader();
            while (r.Read())
            {
                var key = $"{r.GetString(0)}.{r.GetString(1)}";
                if (!procs.TryGetValue(key, out var list)) { list = []; procs[key] = list; }
                if (r.IsDBNull(2)) continue;
                list.Add(new ProcParam(r.GetString(2).TrimStart('@'), r.GetString(3), r.GetInt16(4), r.GetByte(5), r.GetByte(6), r.GetBoolean(7), HasDefault: false));
            }
        }

        // --- defaults: sys.parameters.has_default_value is populated for CLR procedures only, so the
        //     header of the definition is read (needs VIEW DEFINITION on the schema — Roles.sql).
        var withDefaults = new Dictionary<string, ProcInfo>(StringComparer.OrdinalIgnoreCase);
        using (var cmd = con.CreateCommand())
        {
            cmd.CommandText = $"""
                SELECT s.name, p.name, OBJECT_DEFINITION(p.object_id)
                FROM sys.procedures p JOIN sys.schemas s ON s.schema_id = p.schema_id
                WHERE s.name IN ({inList})
                """;
            BindSchemas(cmd);
            using var r = cmd.ExecuteReader();
            while (r.Read())
            {
                var schema = r.GetString(0); var name = r.GetString(1);
                var header = r.IsDBNull(2) ? "" : HeaderOf(r.GetString(2));
                var ps = procs[$"{schema}.{name}"].Select(p => p with { HasDefault = HasDefault(header, p.Name) }).ToList();
                withDefaults[$"{schema}.{name}"] = new ProcInfo(schema, name, ps);
            }
        }

        // --- which base tables each view (and as-of function) reads: from its own definition text, which the
        //     per-schema VIEW DEFINITION grant allows (sys.sql_expression_dependencies needs it on the whole database,
        //     which the service account rightly lacks — found on VGS-VM02, 2026-09-12). The views are the platform's
        //     own SQL: every source is written "FROM [schema].[table]" or "JOIN [schema].[table]".
        var viewBases = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);     // "schema.view" -> ["schema.table", ...]
        using (var cmd = con.CreateCommand())
        {
            cmd.CommandText = $"""
                SELECT s.name, o.name, OBJECT_DEFINITION(o.object_id)
                FROM sys.objects o JOIN sys.schemas s ON s.schema_id = o.schema_id
                WHERE s.name IN ({inList}) AND ((o.type = 'V' AND o.name LIKE 'v%') OR (o.type = 'IF' AND o.name LIKE 'f%AsOf'))
                """;
            BindSchemas(cmd);
            using var r = cmd.ExecuteReader();
            while (r.Read())
            {
                var key = $"{r.GetString(0)}.{r.GetString(1)}";
                var list = new List<string>();
                if (!r.IsDBNull(2))
                    foreach (Match m in SourceTable.Matches(r.GetString(2)))
                        if (!list.Contains($"{m.Groups[1].Value}.{m.Groups[2].Value}", StringComparer.OrdinalIgnoreCase)) list.Add($"{m.Groups[1].Value}.{m.Groups[2].Value}");
                viewBases[key] = list;
            }
        }
        var registryOf = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);        // "schema.table" -> "schema.XRegistry"
        using (var cmd = con.CreateCommand())
        {
            cmd.CommandText = """
                SELECT ps.name, pt.name, rs.name, rt.name
                FROM sys.foreign_keys fk
                JOIN sys.foreign_key_columns fc ON fc.constraint_object_id = fk.object_id
                JOIN sys.columns pc ON pc.object_id = fk.parent_object_id AND pc.column_id = fc.parent_column_id
                JOIN sys.tables pt ON pt.object_id = fk.parent_object_id JOIN sys.schemas ps ON ps.schema_id = pt.schema_id
                JOIN sys.tables rt ON rt.object_id = fk.referenced_object_id JOIN sys.schemas rs ON rs.schema_id = rt.schema_id
                WHERE pc.name = 'EntityId'
                """;
            using var r = cmd.ExecuteReader();
            while (r.Read()) registryOf[$"{r.GetString(0)}.{r.GetString(1)}"] = $"{r.GetString(2)}.{r.GetString(3)}";
        }

        // --- views (v*) and as-of table functions (f*AsOf) with their columns and their subject mapping
        var views = new Dictionary<string, ViewInfo>(StringComparer.OrdinalIgnoreCase);
        using (var cmd = con.CreateCommand())
        {
            cmd.CommandText = $"""
                SELECT s.name, o.name, o.type, c.name, t.name
                FROM sys.objects o
                JOIN sys.schemas s ON s.schema_id = o.schema_id
                JOIN sys.columns c ON c.object_id = o.object_id
                JOIN sys.types t ON t.user_type_id = c.user_type_id
                WHERE s.name IN ({inList})
                  AND ((o.type = 'V' AND o.name LIKE 'v%') OR (o.type = 'IF' AND o.name LIKE 'f%AsOf'))
                ORDER BY s.name, o.name, c.column_id
                """;
            BindSchemas(cmd);
            using var r = cmd.ExecuteReader();
            var cols = new Dictionary<string, List<ViewColumn>>(StringComparer.OrdinalIgnoreCase);
            var kinds = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
            while (r.Read())
            {
                var key = $"{r.GetString(0)}.{r.GetString(1)}";
                if (!cols.TryGetValue(key, out var list)) { list = []; cols[key] = list; kinds[key] = r.GetString(2).Trim() == "IF"; }
                list.Add(new ViewColumn(r.GetString(3), r.GetString(4)));
            }
            foreach (var (key, list) in cols)
            {
                var dot = key.IndexOf('.');
                var (subjectColumn, family) = SubjectOf(key, list, viewBases, registryOf);
                views[key] = new ViewInfo(key[..dot], key[(dot + 1)..], list, kinds[key], subjectColumn, family);
            }
        }

        // --- read-logged classes (FR-6.4): a row, not a release, switches a class on
        var logged = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        using (var cmd = con.CreateCommand())
        {
            cmd.CommandText = "SELECT SchemaName, TableName FROM config.vReadLoggedClass WHERE IsLogged = 1";
            using var r = cmd.ExecuteReader();
            while (r.Read()) logged.Add($"{r.GetString(0)}.{r.GetString(1)}");
        }

        return new Catalog(withDefaults, views, logged, schemas);
    }

    /// <summary>
    /// IDENTITY.md §5: the view's own rows are subjects when a base table's EntityId points at a family registry
    /// and the view carries EntityId; otherwise the first subject column the view carries; otherwise none.
    /// </summary>
    private static (string? column, string? family) SubjectOf(string viewKey, List<ViewColumn> columns,
        Dictionary<string, List<string>> viewBases, Dictionary<string, string> registryOf)
    {
        var has = new HashSet<string>(columns.Select(c => c.Name), StringComparer.OrdinalIgnoreCase);
        if (has.Contains("EntityId") && viewBases.TryGetValue(viewKey, out var bases))
            foreach (var b in bases)
                if (registryOf.TryGetValue(b, out var reg) && FamilyRegistries.TryGetValue(reg, out var fam)) return ("EntityId", fam);
                else if (FamilyRegistries.TryGetValue(b, out var famDirect)) return ("EntityId", famDirect);
        foreach (var (col, fam) in SubjectColumns)
            if (has.Contains(col)) return (col, fam);
        return (null, null);
    }

    // "FROM [schema].[table]" / "JOIN [schema].[table]" in a view or function body (brackets optional).
    private static readonly Regex SourceTable = new(@"\b(?:FROM|JOIN)\s+\[?([A-Za-z_][\w]*)\]?\s*\.\s*\[?([A-Za-z_][\w]*)\]?", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    // The parameter list precedes the first "AS" standing alone on a line.
    private static readonly Regex AsLine = new(@"^\s*AS\s*$", RegexOptions.Multiline | RegexOptions.IgnoreCase | RegexOptions.Compiled);

    internal static string HeaderOf(string definition)
    {
        var m = AsLine.Match(definition);
        return m.Success ? definition[..m.Index] : definition;
    }

    // "@Name TYPE(...) = default" — the type token, optionally parenthesised, then "=".
    internal static bool HasDefault(string header, string paramName) =>
        Regex.IsMatch(header, $@"@{Regex.Escape(paramName)}\s+[A-Za-z_][\w.]*(\s*\([^)]*\))?\s*=", RegexOptions.IgnoreCase);
}
