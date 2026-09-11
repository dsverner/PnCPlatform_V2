using System.Data;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;

namespace PnC.Api.Data;

// docs/design/API.md §3. What the database exposes, read once at start from sys.*; the dispatcher
// serves exactly this and nothing else. A deploy that adds an object is followed by a restart.

public sealed record ProcParam(string Name, string SqlType, int MaxLength, byte Precision, byte Scale, bool IsOutput, bool HasDefault);

public sealed record ProcInfo(string Schema, string Name, IReadOnlyList<ProcParam> Params)
{
    public string Key => $"{Schema}.{Name}";
}

public sealed record ViewColumn(string Name, string SqlType);

public sealed record ViewInfo(string Schema, string Name, IReadOnlyList<ViewColumn> Columns, bool IsAsOfFunction)
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
        var order = new List<string>();
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
                if (!procs.TryGetValue(key, out var list)) { list = []; procs[key] = list; order.Add(key); }
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
                var ps = procs[$"{schema}.{name}"]
                    .Select(p => p with { HasDefault = HasDefault(header, p.Name) })
                    .ToList();
                withDefaults[$"{schema}.{name}"] = new ProcInfo(schema, name, ps);
            }
        }

        // --- views (v*) and as-of table functions (f*AsOf) with their columns
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
                views[key] = new ViewInfo(key[..dot], key[(dot + 1)..], list, kinds[key]);
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
