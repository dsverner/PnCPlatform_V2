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

    // DeferFileWrite (#230): process.SetParsedSetting's switch for callers that write the settings file once after many edits;
    // taken from a body it would let a caller leave an outstanding record's file behind its settings
    // OverrideApprovedByActorId (#232): a segregation override's approver approves from their own session (security.ApproveOverride);
    // a name in a body was taken as the approval, with nothing to show that person approved
    private static readonly HashSet<string> NeverBound = new(StringComparer.OrdinalIgnoreCase) { "ActorId", "MigrationRunId", "DeferFileWrite", "OverrideApprovedByActorId" };
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
            // "now" is the database's (2026-09-23): the API's machine can run ahead of or behind SQL Server — on VGS-PC02 ~209 ms —
            // and a read at this machine's now misses what the database stamped a moment ago in its own time
            cmd.Parameters.Add("@asOf", SqlDbType.DateTimeOffset).Value = asOf is { } at ? at : DBNull.Value;
            source = $"{Q(view.Schema)}.{Q(view.Name)}(ISNULL(@asOf, SYSDATETIMEOFFSET()), SYSUTCDATETIME())";
        }
        else
        {
            if (asOf is not null) throw new ApiException(400, "as_of_not_supported", $"{view.Key} is a current view; use its f…AsOf function for a point in time.");
            source = $"{Q(view.Schema)}.{Q(view.Name)}";
        }

        var where = new List<string>();
        var i = 0;
        // W8 (#145 addendum): a materialised read model takes its equality filters in memory too — a state predicate pushed into
        // the SQL of vSettingsRecord (GridState = 'Archived') measured 42–54 s on QA against 0.6–1.7 s for the whole view; only
        // the read scope stays in SQL, where it belongs (IDENTITY §5)
        var materialise = MaterialiseBeforePaging.Contains(view.Key);
        var memFilters = new List<(string Column, string Value, string SqlType, bool Contains)>();
        foreach (var (name, value) in filters)
        {
            // #176: a filter named with a trailing '~' searches a text column for the value anywhere inside it — Name~=SEL-221
            // finds "SEL-221F Z1-3=.125-64 OHMS". Every chooser needs this: nobody knows a relay's recorded name exactly. It
            // cannot seek an index, so it is for a person typing into a search box over a few thousand rows, never for a report.
            var contains = name.EndsWith('~');
            var colName = contains ? name[..^1] : name;
            var col = view.Columns.FirstOrDefault(c => c.Name.Equals(colName, StringComparison.OrdinalIgnoreCase))
                      ?? throw new ApiException(400, "unknown_column", $"'{colName}' is not a column of {view.Key}.");
            if (contains && !IsTextColumn(col.SqlType))
                throw new ApiException(400, "not_searchable", $"'{col.Name}' is {col.SqlType}, not text, so it cannot be searched with '~'.");
            // an identifier predicate seeks and stays in SQL (one request, one station: 0.4–0.9 s); a predicate on a computed
            // state (GridState) is the one the optimizer mishandles, so it is applied in memory
            if (materialise && !col.SqlType.Equals("uniqueidentifier", StringComparison.OrdinalIgnoreCase)) { if (value != "null" && !contains) ConvertScalar(value, col.SqlType); memFilters.Add((col.Name, value, col.SqlType, contains)); continue; }
            if (value == "null") { where.Add($"{Q(col.Name)} IS NULL"); continue; }
            var pn = $"@f{i++}";
            if (contains)
            {
                cmd.Parameters.Add(new SqlParameter(pn, SqlDbType.NVarChar, -1) { Value = "%" + EscapeLike(value) + "%" });
                where.Add($"{Q(col.Name)} LIKE {pn} ESCAPE '\\'");
                continue;
            }
            var sp = new SqlParameter(pn, SqlDbTypeOf(col.SqlType)) { Value = ConvertScalar(value, col.SqlType) };
            cmd.Parameters.Add(sp);
            where.Add($"{Q(col.Name)} = {pn}");
        }

        // IDENTITY.md §5: read scope is as strict as write scope. The set of readable subjects is the database's
        // (security.fReadableSubjects); the API contributes only the subject column and family.
        var scopeJoin = "";
        var scopePrelude = "";
        if (scope is not null)
        {
            cmd.Parameters.Add("@su", SqlDbType.UniqueIdentifier).Value = scope.UserEntityId;
            cmd.Parameters.Add("@sp", SqlDbType.NVarChar, 80).Value = scope.PermissionCode;
            var families = scope.Family == "Any" ? new[] { "Node", "Asset", "Record", "WorkRequest", "Scheme" } : new[] { scope.Family };
            var sets = families.Select(f => $"SELECT [SubjectEntityId] FROM [security].[fReadableSubjects](@su, @sp, N'{f}', SYSDATETIMEOFFSET())");
            // #222: the readable set is computed in a statement of its own, before the view is touched.
            // security.fReadableSubjects is an inline function, so in one statement the optimizer is free to push the
            // read's own filter into its body. It does, and the function's plan changes: a filter on the very column the
            // scope joins on (asset/vPlacement?AssetEntityId=…, asset/vAsset?EntityId=…) propagated to asset.Placement
            // inside the function's scope_assets, whose estimate fell to one row, and the estate's whole node tree was
            // then expanded before the grant was applied — a Filter on the subtree LIKE ran 10 409 times over 108 million
            // spooled location.Node rows, 87.3 s of an 87.5 s query (actual plan, DEV 2026-09-22). Measured on DEV,
            // 7 909 placements: this statement 95.0 s → 0.30 s with the set materialised first (0.05–0.10 s once the
            // INSERT's plan is cached), and over HTTP an "Execution Timeout Expired" 500 at 30.3 s → 200 in 0.08 s warm.
            // What does not work, measured: OPTION (FORCE ORDER) 83.2 s, OPTION (OPTIMIZE FOR UNKNOWN) 87.0 s, OPTION
            // (HASH JOIN) refused, and a covering location.Node ([Path]) INCLUDE ([EntityId]) filtered index 83.6 s — the
            // damage is the join order inside the function, not a missing seek.
            // A table variable with a primary key, and OPTION (RECOMPILE) kept on the read below: that recompile happens
            // after the INSERT, so the set's true size is known. The set itself is unchanged, so read scope is exactly as strict.
            // The INSERT deliberately carries NO hint. Almost all of this function's cost is compiling it, not running it:
            // 387 ms compile against 7 ms execution for the administrator's 12 579 work requests (actual plan, DEV
            // 2026-09-22). Under OPTION (RECOMPILE) the batch paid that compile twice and a screen read went 0.39 s → 0.68 s,
            // failing the smoke's NFR-2 second; with the INSERT's plan cached it is 0.26 s — better than before. #147's
            // warning (a plan cached for one grant's readable set serving another) is answered by the shape, not by a hint:
            // the read is over @__scope and still recompiles, and the INSERT's plan is the function's own, which the same
            // measurement ran across grants both ways (Global plan → subtree read 0.10 s, subtree plan → Global read 0.06 s).
            scopePrelude = "SET NOCOUNT ON;\n"
                         + "DECLARE @__scope TABLE ([__ScopeId] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);\n"
                         + $"INSERT INTO @__scope ([__ScopeId]) SELECT DISTINCT [SubjectEntityId] FROM ({string.Join(" UNION ", sets)}) __s;\n";
            if (scope.Family == "Any")
            {
                // W4 (decision #118): a subject of a kind outside the five scoped families (a settings-issue package, a
                // procedure instance…) has no node to scope by; its rows are readable under a Global grant only (IDENTITY.md §5)
                var inScope = $"{Q(scope.Column)} IN (SELECT [__ScopeId] FROM @__scope)";
                var outside = scope.KindColumn is null ? "1 = 1" : $"{Q(scope.KindColumn)} NOT IN (N'Node', N'Station', N'Panel', N'DevicePosition', N'ProtectionFunction', N'Asset', N'Device', N'Record', N'WorkRequest', N'Scheme')";
                where.Add($"({inScope} OR ({outside} AND [security].[fHasPermission](@su, @sp, NULL, NULL, SYSDATETIMEOFFSET()) = 1))");
            }
            else
            {
                // W8 (0.9.0, #158): the readable set as a distinct derived table joined to the view, not an IN (subquery) predicate.
                // On the fully loaded DEV estate the IN form took the whole settings book from 1.9 s to 100–170 s once the
                // migration's landings filled the process tables (the optimizer pushed the set into the view's correlated
                // lookups); the join form measured 1.9 s on the same data (2026-09-14, typed parameters). The derived
                // table's one column is named so no view column can be ambiguous. #222 keeps the join and moves the set
                // it joins to into @__scope above.
                scopeJoin = $" JOIN @__scope __scope ON __scope.[__ScopeId] = {Q(scope.Column)}";
            }
        }
        // W7: a scoped read is compiled for its own grant. A plan cached for one readable set (the whole registry under a
        // Global grant, 55 assets under a subtree) served another for 30 s on DEV until the cache was cleared; the
        // recompile costs ~0.1 s on the migrated estate, measured.
        // #168 (2026-09-16): on the reloaded DEV estate the optimizer drove a materialised read model from the readable set (6 879 assets)
        // and re-evaluated the view's correlated lookups per subject: every free form (join, IN, a table variable) ran past 40 s;
        // the written order — the view first, the readable set joined to it — ran in 1.7 s. FORCE ORDER pins that for the
        // hand-written read models (the MaterialiseBeforePaging list); the generated views keep the optimizer's freedom.
        var hint = scope is null ? "" : MaterialiseBeforePaging.Contains(view.Key) ? " OPTION (RECOMPILE, FORCE ORDER)" : " OPTION (RECOMPILE)";

        // Stable ordering: RowSeq is always the tiebreaker, so paging never repeats or skips a row.
        var order = new List<string>();
        // several keys, comma-separated, each "-" for descending (2026-09-23: the settings book keeps one relay's revisions
        // together, newest first — "DeviceName,DeviceEntityId,-RevisionNumber"); every name is checked against the catalogue
        foreach (var key in (orderBy ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var desc = key.StartsWith('-');
            var name = desc ? key[1..] : key;
            var col = view.Columns.FirstOrDefault(c => c.Name.Equals(name, StringComparison.OrdinalIgnoreCase))
                      ?? throw new ApiException(400, "unknown_column", $"'{name}' is not a column of {view.Key}.");
            if (!order.Any(o => o.StartsWith(Q(col.Name) + " "))) order.Add($"{Q(col.Name)} {(desc ? "DESC" : "ASC")}");
        }
        if (view.HasRowSeq) { if (!order.Any(o => o.StartsWith("[RowSeq]"))) order.Add("[RowSeq] ASC"); }
        else if (order.Count == 0) order.Add($"{Q(view.Columns[0].Name)} ASC");

        cmd.Parameters.Add("@skip", SqlDbType.Int).Value = skip;
        cmd.Parameters.Add("@take", SqlDbType.Int).Value = take;
        var body = $"SELECT {select} FROM {source}{scopeJoin}" + (where.Count > 0 ? " WHERE " + string.Join(" AND ", where) : "");
        var paging = " ORDER BY " + string.Join(", ", order) + " OFFSET @skip ROWS FETCH NEXT @take ROWS ONLY";
        // W7: a hand-written read model whose rows are correlated lookups (the parity screens' views) is materialised whole
        // before it is ordered and paged — the optimizer otherwise re-evaluates the lookups per candidate row (a page at
        // offset 5 000 measured 108 s on the migrated estate; the whole view 3 s). The list is Api:MaterialiseBeforePaging.
        // Measured on the migrated estate (W7): the plain SELECT of the whole view runs with a parallel plan in 1–6 s; the same
        // SELECT with ORDER BY / OFFSET, TOP, or SELECT INTO a temp table takes 10–120 s. So a listed view is read whole,
        // plain, and ordered and paged here in memory — its whole set is what its screen wants anyway.
        if (MaterialiseBeforePaging.Contains(view.Key))
        {
            cmd.CommandText = scopePrelude + body + hint;
            var all = new List<JsonObject>();
            await using (var rr = await cmd.ExecuteReaderAsync(ct))
                while (await rr.ReadAsync(ct)) { var row = RowToJson(rr); if (memFilters.All(f => MatchesFilter(row[f.Column], f.Value, f.SqlType, f.Contains))) all.Add(row); }
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
        cmd.CommandText = scopePrelude + body + paging + hint;

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
    /// <summary>An equality filter applied to a materialised row: "null" matches a null; text and identifiers compare ordinal-ignore-case; numbers by value; bits by 0/1/true/false.</summary>
    /// <summary>A text column is one a '~' search may look inside (#176).</summary>
    private static bool IsTextColumn(string sqlType) =>
        sqlType.ToLowerInvariant() is "nvarchar" or "varchar" or "nchar" or "char" or "text" or "ntext";

    /// <summary>The LIKE wildcards, so a person searching for "50%" finds a literal per cent rather than everything.</summary>
    private static string EscapeLike(string v) =>
        v.Replace("\\", "\\\\").Replace("%", "\\%").Replace("_", "\\_").Replace("[", "\\[");

    private static bool MatchesFilter(JsonNode? v, string value, string sqlType, bool contains = false)
    {
        if (value == "null") return v is null;
        if (v is null) return false;
        var t = sqlType.ToLowerInvariant();
        var text = v is JsonValue jv && jv.TryGetValue<string>(out var sv) ? sv : v.ToJsonString().Trim('"');
        if (contains) return text.Contains(value, StringComparison.OrdinalIgnoreCase);
        if (t is "bit") return (text is "true" or "1") == (value is "true" or "1" or "True");
        if (t is "int" or "bigint" or "smallint" or "tinyint" or "decimal" or "numeric" or "float" or "real" or "money")
            return decimal.TryParse(text, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out var a) && decimal.TryParse(value, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out var b) && a == b;
        return string.Equals(text, value, StringComparison.OrdinalIgnoreCase);
    }

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
