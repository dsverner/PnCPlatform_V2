using System.Data;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.SqlClient;
using PnC.Api.Endpoints;

namespace PnC.Api.Data;

// docs/design/API.md §2.3, §6. One connection per request: opened, session context set from the
// authenticated identity, used, closed. Attribution belongs to personnel.ResolveActor on the
// database side; this class never passes an ActorId of the application's choosing.

public sealed record SessionIdentity(string UserPrincipalName, Guid? DelegationEntityId, Guid? SponsoredPersonEntityId);

/// <summary>A list read's scope (IDENTITY.md §5): which column of the view names the subject, of which family, for whom, under which permission.</summary>
public sealed record ScopeFilter(string Column, string Family, Guid UserEntityId, string PermissionCode, string? KindColumn = null);

public sealed class SqlSession : IAsyncDisposable
{
    private readonly SqlConnection _con;
    public SqlConnection Connection => _con;

    private SqlSession(SqlConnection con) => _con = con;

    /// <summary>Opens a connection and sets the session context the procedures read.</summary>
    public static async Task<SqlSession> OpenAsync(string connectionString, SessionIdentity? identity, CancellationToken ct)
    {
        var con = new SqlConnection(connectionString);
        await con.OpenAsync(ct);
        if (identity is not null)
        {
            await using var cmd = con.CreateCommand();
            cmd.CommandText = """
                EXEC sp_set_session_context @key = N'UserPrincipalName', @value = @upn, @read_only = 1;
                IF @delegation IS NOT NULL EXEC sp_set_session_context @key = N'DelegationEntityId', @value = @delegation, @read_only = 1;
                IF @sponsored IS NOT NULL EXEC sp_set_session_context @key = N'SponsoredPersonEntityId', @value = @sponsored, @read_only = 1;
                """;
            cmd.Parameters.Add("@upn", SqlDbType.NVarChar, 200).Value = identity.UserPrincipalName;
            cmd.Parameters.Add("@delegation", SqlDbType.UniqueIdentifier).Value = (object?)identity.DelegationEntityId ?? DBNull.Value;
            cmd.Parameters.Add("@sponsored", SqlDbType.UniqueIdentifier).Value = (object?)identity.SponsoredPersonEntityId ?? DBNull.Value;
            await cmd.ExecuteNonQueryAsync(ct);
        }
        return new SqlSession(con);
    }

    /// <summary>Bracket-quotes an identifier from the catalogue; a "]" inside a name is doubled, as QUOTENAME does.</summary>
    public static string Q(string identifier) => "[" + identifier.Replace("]", "]]") + "]";

    // ------------------------------------------------------------------ procedures

    private static readonly HashSet<string> NeverBound = new(StringComparer.OrdinalIgnoreCase) { "ActorId", "MigrationRunId" };
    /// <summary>Views materialised whole before ordering and paging (W7; Api:MaterialiseBeforePaging).</summary>
    public static HashSet<string> MaterialiseBeforePaging { get; } = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// Binds the body to the procedure's catalogued parameters (never the other way round), runs it,
    /// and returns OUTPUT parameters at top level plus every result set under "results".
    /// </summary>
    public async Task<JsonObject> ExecuteProcedureAsync(ProcInfo proc, JsonObject body, CancellationToken ct)
    {
        await using var cmd = _con.CreateCommand();
        cmd.CommandType = CommandType.StoredProcedure;
        cmd.CommandText = $"{Q(proc.Schema)}.{Q(proc.Name)}";

        var bodyKeys = body.Select(kv => kv.Key).ToList();
        var outputs = new List<SqlParameter>();
        foreach (var p in proc.Params)
        {
            if (NeverBound.Contains(p.Name)) continue;           // §2.3: attribution is the database's
            var key = bodyKeys.FirstOrDefault(k => k.Equals(p.Name, StringComparison.OrdinalIgnoreCase));
            var given = key is not null && body[key] is not null;
            var sp = MakeParameter(p);
            if (p.IsOutput)
            {
                sp.Direction = ParameterDirection.InputOutput;
                sp.Value = given ? ConvertValue(body[key!]!, p) : DBNull.Value;
                outputs.Add(sp);
                cmd.Parameters.Add(sp);
                continue;
            }
            if (!given)
            {
                if (p.HasDefault) continue;                      // the procedure's own default applies
                throw new ApiException(400, "missing_parameter", $"Parameter '{p.Name}' is required by {proc.Key}.");
            }
            sp.Value = ConvertValue(body[key!]!, p);
            cmd.Parameters.Add(sp);
        }
        foreach (var k in bodyKeys)
        {
            if (NeverBound.Contains(k))
                throw new ApiException(400, "unknown_parameter", $"'{k}' is never accepted from a client; attribution is the database's (API.md §2.3).");
            if (!proc.Params.Any(p => p.Name.Equals(k, StringComparison.OrdinalIgnoreCase)))
                throw new ApiException(400, "unknown_parameter", $"'{k}' is not a parameter of {proc.Key}.");
        }

        var result = new JsonObject();
        var results = new JsonArray();
        await using (var r = await cmd.ExecuteReaderAsync(ct))
        {
            do
            {
                var rows = new JsonArray();
                while (await r.ReadAsync(ct)) rows.Add(RowToJson(r));
                if (r.FieldCount > 0) results.Add(rows);
            } while (await r.NextResultAsync(ct));
        }
        foreach (var o in outputs)
            result[o.ParameterName.TrimStart('@')] = ToJson(o.Value);
        result["results"] = results;
        return result;
    }

    // ------------------------------------------------------------------ views

    private static readonly HashSet<string> UdtTypes = new(StringComparer.OrdinalIgnoreCase) { "geography", "geometry", "hierarchyid" };

    /// <summary>
    /// Reads a view with equality filters, ordering and paging. Every column name comes from the
    /// catalogue; nothing from the query string reaches SQL text.
    /// </summary>
    public async Task<JsonArray> QueryViewAsync(ViewInfo view, IReadOnlyDictionary<string, string> filters, string? orderBy,
        int skip, int take, DateTimeOffset? asOf, ScopeFilter? scope, CancellationToken ct)
    {
        await using var cmd = _con.CreateCommand();
        var select = string.Join(", ", view.Columns.Select(c => UdtTypes.Contains(c.SqlType) ? $"{Q(c.Name)}.ToString() AS {Q(c.Name)}" : Q(c.Name)));
        string source;
        if (view.IsAsOfFunction)
        {
            var at = asOf ?? DateTimeOffset.Now;
            cmd.Parameters.Add("@asOf", SqlDbType.DateTimeOffset).Value = at;
            cmd.Parameters.Add("@believed", SqlDbType.DateTime2).Value = DateTime.UtcNow;
            source = $"{Q(view.Schema)}.{Q(view.Name)}(@asOf, @believed)";
        }
        else
        {
            if (asOf is not null) throw new ApiException(400, "as_of_not_supported", $"{view.Key} is a current view; use its f…AsOf function for a point in time.");
            source = $"{Q(view.Schema)}.{Q(view.Name)}";
        }

        var where = new List<string>();
        var i = 0;
        foreach (var (name, value) in filters)
        {
            var col = view.Columns.FirstOrDefault(c => c.Name.Equals(name, StringComparison.OrdinalIgnoreCase))
                      ?? throw new ApiException(400, "unknown_column", $"'{name}' is not a column of {view.Key}.");
            if (value == "null") { where.Add($"{Q(col.Name)} IS NULL"); continue; }
            var pn = $"@f{i++}";
            var sp = new SqlParameter(pn, SqlDbTypeOf(col.SqlType)) { Value = ConvertScalar(value, col.SqlType) };
            cmd.Parameters.Add(sp);
            where.Add($"{Q(col.Name)} = {pn}");
        }

        // IDENTITY.md §5: read scope is as strict as write scope. The set of readable subjects is the database's
        // (security.fReadableSubjects); the API contributes only the subject column and family.
        if (scope is not null)
        {
            cmd.Parameters.Add("@su", SqlDbType.UniqueIdentifier).Value = scope.UserEntityId;
            cmd.Parameters.Add("@sp", SqlDbType.NVarChar, 80).Value = scope.PermissionCode;
            var families = scope.Family == "Any" ? new[] { "Node", "Asset", "Record", "WorkRequest", "Scheme" } : new[] { scope.Family };
            var sets = families.Select(f => $"SELECT [SubjectEntityId] FROM [security].[fReadableSubjects](@su, @sp, N'{f}', SYSDATETIMEOFFSET())");
            var inScope = $"{Q(scope.Column)} IN ({string.Join(" UNION ", sets)})";
            if (scope.Family == "Any")
            {
                // W4 (decision #118): a subject of a kind outside the five scoped families (a settings-issue package, a
                // procedure instance…) has no node to scope by; its rows are readable under a Global grant only (IDENTITY.md §5)
                var outside = scope.KindColumn is null ? "1 = 1" : $"{Q(scope.KindColumn)} NOT IN (N'Node', N'Station', N'Panel', N'DevicePosition', N'ProtectionFunction', N'Asset', N'Device', N'Record', N'WorkRequest', N'Scheme')";
                inScope = $"({inScope} OR ({outside} AND [security].[fHasPermission](@su, @sp, NULL, NULL, SYSDATETIMEOFFSET()) = 1))";
            }
            where.Add(inScope);
        }
        // W7: a scoped read is compiled for its own grant. A plan cached for one readable set (the whole registry under a
        // Global grant, 55 assets under a subtree) served another for 30 s on DEV until the cache was cleared; the
        // recompile costs ~0.1 s on the migrated estate, measured.
        var hint = scope is not null ? " OPTION (RECOMPILE)" : "";

        // Stable ordering: RowSeq is always the tiebreaker, so paging never repeats or skips a row.
        var order = new List<string>();
        if (!string.IsNullOrEmpty(orderBy))
        {
            var desc = orderBy.StartsWith('-');
            var name = desc ? orderBy[1..] : orderBy;
            var col = view.Columns.FirstOrDefault(c => c.Name.Equals(name, StringComparison.OrdinalIgnoreCase))
                      ?? throw new ApiException(400, "unknown_column", $"'{name}' is not a column of {view.Key}.");
            order.Add($"{Q(col.Name)} {(desc ? "DESC" : "ASC")}");
        }
        if (view.HasRowSeq) { if (!order.Any(o => o.StartsWith("[RowSeq]"))) order.Add("[RowSeq] ASC"); }
        else if (order.Count == 0) order.Add($"{Q(view.Columns[0].Name)} ASC");

        cmd.Parameters.Add("@skip", SqlDbType.Int).Value = skip;
        cmd.Parameters.Add("@take", SqlDbType.Int).Value = take;
        var body = $"SELECT {select} FROM {source}" + (where.Count > 0 ? " WHERE " + string.Join(" AND ", where) : "");
        var paging = " ORDER BY " + string.Join(", ", order) + " OFFSET @skip ROWS FETCH NEXT @take ROWS ONLY";
        // W7: a hand-written read model whose rows are correlated lookups (the parity screens' views) is materialised whole
        // before it is ordered and paged — the optimizer otherwise re-evaluates the lookups per candidate row (a page at
        // offset 5 000 measured 108 s on the migrated estate; the whole view 3 s). The list is Api:MaterialiseBeforePaging.
        // Measured on the migrated estate (W7): the plain SELECT of the whole view runs with a parallel plan in 1–6 s; the same
        // SELECT with ORDER BY / OFFSET, TOP, or SELECT INTO a temp table takes 10–120 s. So a listed view is read whole,
        // plain, and ordered and paged here in memory — its whole set is what its screen wants anyway.
        if (MaterialiseBeforePaging.Contains(view.Key))
        {
            cmd.CommandText = body + hint;
            var all = new List<JsonObject>();
            await using (var rr = await cmd.ExecuteReaderAsync(ct))
                while (await rr.ReadAsync(ct)) all.Add(RowToJson(rr));
            var keys = order.Select(o => (name: o.Split(' ')[0].Trim('[', ']'), desc: o.EndsWith(" DESC"))).ToList();
            var types = view.Columns.ToDictionary(c => c.Name, c => c.SqlType, StringComparer.OrdinalIgnoreCase);
            all.Sort((x, y) =>
            {
                foreach (var (name, desc) in keys)
                {
                    var c = CompareJson(x[name], y[name], types.GetValueOrDefault(name) ?? "");
                    if (c != 0) return desc ? -c : c;
                }
                return 0;
            });
            var page = new JsonArray();
            foreach (var row in all.Skip(skip).Take(take)) page.Add(row);
            return page;
        }
        cmd.CommandText = body + paging + hint;

        var rows = new JsonArray();
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) rows.Add(RowToJson(r));
        return rows;
    }

    // ------------------------------------------------------------------ helpers

    /// <summary>The engine's clock is the database's (W7): the host's clock ran 1.2 s behind the server's on DEV, and a fact
    /// the database had just written was invisible to a guard evaluated "now" by the host (the API-side twin of #79).</summary>
    public async Task<DateTimeOffset> NowAsync(CancellationToken ct)
    {
        await using var cmd = _con.CreateCommand();
        cmd.CommandText = "SELECT SYSDATETIMEOFFSET()";
        return (DateTimeOffset)(await cmd.ExecuteScalarAsync(ct))!;
    }

    public async Task<T?> ScalarAsync<T>(string sql, IReadOnlyDictionary<string, object?> args, CancellationToken ct)
    {
        await using var cmd = _con.CreateCommand();
        cmd.CommandText = sql;
        foreach (var (k, v) in args) cmd.Parameters.AddWithValue(k, v ?? DBNull.Value);
        var v0 = await cmd.ExecuteScalarAsync(ct);
        return v0 is null or DBNull ? default : (T)v0;
    }

    public async Task<JsonArray> RowsAsync(string sql, IReadOnlyDictionary<string, object?> args, CancellationToken ct)
    {
        await using var cmd = _con.CreateCommand();
        cmd.CommandText = sql;
        foreach (var (k, v) in args) cmd.Parameters.AddWithValue(k, v ?? DBNull.Value);
        var rows = new JsonArray();
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) rows.Add(RowToJson(r));
        return rows;
    }

    public async Task ExecAsync(string sql, IReadOnlyDictionary<string, object?> args, CancellationToken ct)
    {
        await using var cmd = _con.CreateCommand();
        cmd.CommandText = sql;
        foreach (var (k, v) in args) cmd.Parameters.AddWithValue(k, v ?? DBNull.Value);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    /// <summary>SQL ordering semantics over the JSON a row was rendered to: nulls first, numbers and instants by value, text ordinal-ignore-case.</summary>
    private static int CompareJson(JsonNode? a, JsonNode? b, string sqlType)
    {
        if (a is null && b is null) return 0;
        if (a is null) return -1;
        if (b is null) return 1;
        var t = sqlType.ToLowerInvariant();
        if (t is "int" or "bigint" or "smallint" or "tinyint" or "decimal" or "numeric" or "float" or "real" or "money")
            return Convert.ToDecimal(a.GetValue<object>()).CompareTo(Convert.ToDecimal(b.GetValue<object>()));
        if (t.StartsWith("datetime") || t == "date" || t == "time")
            return DateTimeOffset.Parse(a.ToString()).CompareTo(DateTimeOffset.Parse(b.ToString()));
        if (t == "bit") return (a.GetValue<bool>() ? 1 : 0).CompareTo(b.GetValue<bool>() ? 1 : 0);
        return string.Compare(a.ToString(), b.ToString(), StringComparison.OrdinalIgnoreCase);
    }

    private static JsonObject RowToJson(SqlDataReader r)
    {
        var o = new JsonObject();
        for (var i = 0; i < r.FieldCount; i++) o[r.GetName(i)] = ToJson(r.IsDBNull(i) ? DBNull.Value : r.GetValue(i));
        return o;
    }

    private static JsonNode? ToJson(object? v) => v switch
    {
        null or DBNull => null,
        string s => s,
        bool b => b,
        byte n => n, short n => n, int n => n, long n => n,
        decimal d => d, double d => d, float f => f,
        Guid g => g.ToString(),
        DateTimeOffset dto => dto.ToString("o", CultureInfo.InvariantCulture),
        DateTime dt => dt.ToString("o", CultureInfo.InvariantCulture),
        DateOnly d => d.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
        TimeSpan t => t.ToString(),
        byte[] bytes => Convert.ToBase64String(bytes),
        _ => v.ToString()
    };

    private static SqlParameter MakeParameter(ProcParam p)
    {
        var sp = new SqlParameter("@" + p.Name, SqlDbTypeOf(p.SqlType));
        switch (sp.SqlDbType)
        {
            case SqlDbType.NVarChar or SqlDbType.VarChar or SqlDbType.NChar or SqlDbType.Char or SqlDbType.VarBinary or SqlDbType.Binary:
                sp.Size = p.MaxLength == -1 ? -1 : (sp.SqlDbType is SqlDbType.NVarChar or SqlDbType.NChar ? p.MaxLength / 2 : p.MaxLength);
                break;
            case SqlDbType.Decimal:
                sp.Precision = p.Precision; sp.Scale = p.Scale; break;
            case SqlDbType.DateTimeOffset or SqlDbType.DateTime2 or SqlDbType.Time:
                sp.Scale = p.Scale; break;
        }
        return sp;
    }

    public static SqlDbType SqlDbTypeOf(string sqlType) => sqlType.ToLowerInvariant() switch
    {
        "uniqueidentifier" => SqlDbType.UniqueIdentifier,
        "nvarchar" or "sysname" => SqlDbType.NVarChar,
        "varchar" => SqlDbType.VarChar,
        "nchar" => SqlDbType.NChar,
        "char" => SqlDbType.Char,
        "bit" => SqlDbType.Bit,
        "tinyint" => SqlDbType.TinyInt,
        "smallint" => SqlDbType.SmallInt,
        "int" => SqlDbType.Int,
        "bigint" => SqlDbType.BigInt,
        "decimal" or "numeric" => SqlDbType.Decimal,
        "money" or "smallmoney" => SqlDbType.Money,
        "float" => SqlDbType.Float,
        "real" => SqlDbType.Real,
        "datetimeoffset" => SqlDbType.DateTimeOffset,
        "datetime2" => SqlDbType.DateTime2,
        "datetime" => SqlDbType.DateTime,
        "date" => SqlDbType.Date,
        "time" => SqlDbType.Time,
        "varbinary" or "binary" or "image" or "timestamp" => SqlDbType.VarBinary,
        "xml" => SqlDbType.Xml,
        _ => SqlDbType.NVarChar          // UDTs and anything unexpected travel as text
    };

    private static object ConvertValue(JsonNode node, ProcParam p)
    {
        if (node is JsonObject or JsonArray) return node.ToJsonString();     // JSON payloads are text to the procedure
        var jv = (JsonValue)node;
        // a JsonValue wrapping a CLR value (a Guid, a DateTimeOffset the engine passes) renders as JSON text with quotes; take the unquoted text
        string T() => jv.TryGetValue<string>(out var s) ? s : jv.TryGetValue<DateTimeOffset>(out var dto) ? dto.ToString("o") : jv.ToJsonString().Trim('"');
        try
        {
            switch (SqlDbTypeOf(p.SqlType))
            {
                case SqlDbType.UniqueIdentifier: return Guid.Parse(T());
                case SqlDbType.Bit: return jv.TryGetValue<bool>(out var b) ? b : bool.Parse(T());
                case SqlDbType.TinyInt: return byte.Parse(T(), CultureInfo.InvariantCulture);
                case SqlDbType.SmallInt: return short.Parse(T(), CultureInfo.InvariantCulture);
                case SqlDbType.Int: return int.Parse(T(), CultureInfo.InvariantCulture);
                case SqlDbType.BigInt: return long.Parse(T(), CultureInfo.InvariantCulture);
                case SqlDbType.Decimal or SqlDbType.Money: return decimal.Parse(T(), CultureInfo.InvariantCulture);
                case SqlDbType.Float or SqlDbType.Real: return double.Parse(T(), CultureInfo.InvariantCulture);
                case SqlDbType.DateTimeOffset: return DateTimeOffset.Parse(T(), CultureInfo.InvariantCulture);
                case SqlDbType.DateTime2 or SqlDbType.DateTime or SqlDbType.Date: return DateTime.Parse(T(), CultureInfo.InvariantCulture);
                case SqlDbType.Time: return TimeSpan.Parse(jv.ToString(), CultureInfo.InvariantCulture);
                case SqlDbType.VarBinary: return Convert.FromBase64String(jv.ToString());
                default: return jv.ToString();
            }
        }
        catch (Exception e) when (e is FormatException or OverflowException or InvalidOperationException)
        {
            throw new ApiException(400, "bad_value", $"'{p.Name}' does not accept '{jv}' as {p.SqlType}.");
        }
    }

    private static object ConvertScalar(string value, string sqlType)
    {
        try
        {
            return SqlDbTypeOf(sqlType) switch
            {
                SqlDbType.UniqueIdentifier => Guid.Parse(value),
                SqlDbType.Bit => value is "1" or "true" or "True",
                SqlDbType.TinyInt or SqlDbType.SmallInt or SqlDbType.Int or SqlDbType.BigInt => long.Parse(value, CultureInfo.InvariantCulture),
                SqlDbType.Decimal or SqlDbType.Money or SqlDbType.Float or SqlDbType.Real => decimal.Parse(value, CultureInfo.InvariantCulture),
                SqlDbType.DateTimeOffset => DateTimeOffset.Parse(value, CultureInfo.InvariantCulture),
                SqlDbType.DateTime2 or SqlDbType.DateTime or SqlDbType.Date => DateTime.Parse(value, CultureInfo.InvariantCulture),
                _ => value
            };
        }
        catch (Exception e) when (e is FormatException or OverflowException)
        {
            throw new ApiException(400, "bad_value", $"'{value}' is not a {sqlType}.");
        }
    }

    public ValueTask DisposeAsync() => _con.DisposeAsync();
}
