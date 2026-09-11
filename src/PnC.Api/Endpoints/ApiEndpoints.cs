using System.Text.Json;
using System.Text.Json.Nodes;
using PnC.Api.Data;
using PnC.Api.Security;

namespace PnC.Api.Endpoints;

// docs/design/API.md §5–§7. The generic dispatcher and the three fixed endpoints. A handler
// validates the request shape, decides one permission, calls the procedure or view, returns.

public static class ApiEndpoints
{
    public static void Map(WebApplication app, Catalog catalog, PermissionMap map, AuthorizationService authz, string environmentName, string connectionString)
    {
        var maxTake = app.Configuration.GetValue<int?>("Api:MaxTake") ?? 500;

        // ---- /health: no identity, its own connection, no data (§7)
        app.MapGet("/health", async (CancellationToken ct) =>
        {
            string database = "ok"; string? release = null;
            try
            {
                await using var s = await SqlSession.OpenAsync(connectionString, null, ct);
                release = await s.ScalarAsync<string>("""
                    SELECT TOP (1) r.Version FROM platform.vDeployment d JOIN platform.vRelease r ON r.ReleaseId = d.ReleaseId
                    WHERE d.DatabaseName = DB_NAME() AND d.Outcome = N'Succeeded' ORDER BY d.DeployedAt DESC
                    """, new Dictionary<string, object?>(), ct);
            }
            catch (Exception) { database = "unreachable"; }
            return Results.Json(new { environment = environmentName, release, database, catalogLoadedAt = catalog.LoadedAt });
        });

        // ---- /api/v1/me: the user, the person, grants and delegations in force (§7)
        app.MapGet("/api/v1/me", async (HttpContext http, CancellationToken ct) =>
        {
            var u = http.User(); var s = http.Session();
            var args = new Dictionary<string, object?> { ["@u"] = u.UserEntityId, ["@p"] = u.PersonEntityId };
            var grants = await s.RowsAsync("""
                SELECT EntityId, RoleCode, ScopeKind, ScopeNodeEntityId, ScopeAssetClassCode, ValidFrom
                FROM security.fGrantAsOf(SYSDATETIMEOFFSET(), SYSUTCDATETIME())
                WHERE GranteeKind = N'User' AND GranteeEntityId = @u AND RevokedByActorId IS NULL AND IsDeleted = 0
                ORDER BY RoleCode
                """, args, ct);
            var delegations = await s.RowsAsync("""
                SELECT EntityId, FromPersonEntityId, RoleCode, StartsAt, EndsAt
                FROM security.fDelegationAsOf(SYSDATETIMEOFFSET(), SYSUTCDATETIME())
                WHERE ToPersonEntityId = @p AND RevokedByActorId IS NULL AND IsDeleted = 0
                  AND StartsAt <= SYSDATETIMEOFFSET() AND (EndsAt IS NULL OR EndsAt > SYSDATETIMEOFFSET())
                ORDER BY StartsAt
                """, args, ct);
            return Results.Json(new
            {
                user = new { entityId = u.UserEntityId, userPrincipalName = u.UserPrincipalName },
                person = new { entityId = u.PersonEntityId, displayName = u.DisplayName },
                actingAs = new { delegation = u.DelegationEntityId, sponsoredPerson = u.SponsoredPersonEntityId },
                grants, delegations
            });
        });

        // ---- /api/v1/catalog: everything callable, with its permission code (§3)
        app.MapGet("/api/v1/catalog", (HttpContext http) =>
        {
            _ = http.User();
            var procedures = catalog.Procedures.Values.OrderBy(p => p.Key, StringComparer.Ordinal).Select(p => new
            {
                schema = p.Schema, name = p.Name, permission = map.ForProcedure(p.Schema, p.Name),
                parameters = p.Params.Where(x => x.Name is not ("ActorId" or "MigrationRunId"))
                    .Select(x => new { name = x.Name, type = x.SqlType, output = x.IsOutput, required = !x.IsOutput && !x.HasDefault })
            });
            var views = catalog.Views.Values.OrderBy(v => v.Key, StringComparer.Ordinal).Select(v => new
            {
                schema = v.Schema, name = v.Name, permission = map.ForView(v.Schema, v.Name), asOf = v.IsAsOfFunction,
                columns = v.Columns.Select(c => new { name = c.Name, type = c.SqlType })
            });
            return Results.Json(new { schemas = catalog.Schemas, loadedAt = catalog.LoadedAt, procedures, views });
        });

        // ---- POST /api/v1/{schema}/{procedure} (§6)
        app.MapPost("/api/v1/{schema}/{procedure}", async (string schema, string procedure, HttpContext http, CancellationToken ct) =>
        {
            var u = http.User(); var s = http.Session();
            var proc = catalog.Procedure(schema, procedure) ?? throw new ApiException(404, "unknown_procedure", $"{schema}.{procedure} is not in the catalogue.");
            var code = map.ForProcedure(proc.Schema, proc.Name) ?? throw new ApiException(404, "not_callable", $"{proc.Key} is not callable over the API.");
            var body = await ReadBody(http, ct);
            var (kind, id) = SubjectOf(body, map);
            await authz.RequireAsync(s, u, code, kind ?? map.SubjectClass(proc.Schema, proc.Name), id, $"POST {proc.Key}", http.Connection.RemoteIpAddress?.ToString() ?? "", ct);
            var result = await s.ExecuteProcedureAsync(proc, body, ct);
            return Results.Json(result);
        });

        // ---- GET /api/v1/{schema}/{view} (§6)
        app.MapGet("/api/v1/{schema}/{view}", async (string schema, string view, HttpContext http, CancellationToken ct) =>
        {
            var u = http.User(); var s = http.Session();
            var v = catalog.View(schema, view) ?? throw new ApiException(404, "unknown_view", $"{schema}.{view} is not in the catalogue.");
            var code = map.ForView(v.Schema, v.Name) ?? throw new ApiException(404, "not_callable", $"{v.Key} has no permission class.");

            var q = http.Request.Query;
            var filters = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var (k, val) in q)
                if (k is not ("orderBy" or "skip" or "take" or "asOf")) filters[k] = val.ToString();
            var skip = int.TryParse(q["skip"], out var sk) && sk >= 0 ? sk : 0;
            var take = int.TryParse(q["take"], out var tk) ? Math.Clamp(tk, 1, maxTake) : Math.Min(100, maxTake);
            DateTimeOffset? asOf = null;
            if (q.ContainsKey("asOf"))
                asOf = DateTimeOffset.TryParse(q["asOf"], out var at) ? at : throw new ApiException(400, "bad_value", "asOf is not an instant.");

            Guid? subject = filters.TryGetValue("EntityId", out var e) && Guid.TryParse(e, out var g) ? g : null;
            await authz.RequireAsync(s, u, code, map.SubjectClass(v.Schema, v.Name), subject, $"GET {v.Key}", http.Connection.RemoteIpAddress?.ToString() ?? "", ct);

            // FR-6.4: a read of a logged class is written to the action log before the rows are returned.
            var baseTable = v.IsAsOfFunction ? v.Name[1..^4] : v.Name[1..];
            if (catalog.ReadLoggedTables.Contains($"{v.Schema}.{baseTable}"))
                await s.ExecAsync("EXEC [audit].[LogRead] @SubjectSchema = @sc, @SubjectTable = @tb, @SubjectEntityId = @id",
                    new Dictionary<string, object?> { ["@sc"] = v.Schema, ["@tb"] = baseTable, ["@id"] = subject }, ct);

            var rows = await s.QueryViewAsync(v, filters, q["orderBy"].FirstOrDefault(), skip, take, asOf, ct);
            return Results.Json(new { view = v.Key, skip, take, rows });
        });
    }

    private static async Task<JsonObject> ReadBody(HttpContext http, CancellationToken ct)
    {
        // Cross-site request forgery defence for Windows-authenticated browsers: only application/json is accepted,
        // which a cross-origin page cannot send without a CORS preflight this API never answers.
        if (!http.Request.HasJsonContentType())
            throw new ApiException(415, "unsupported_media_type", "POST bodies must be application/json (send {} for no parameters).");
        if (http.Request.ContentLength is 0) return new JsonObject();
        try
        {
            var node = await JsonNode.ParseAsync(http.Request.Body, cancellationToken: ct);
            return node switch { null => new JsonObject(), JsonObject o => o, _ => throw new ApiException(400, "bad_json", "The body must be a JSON object.") };
        }
        catch (JsonException) { throw new ApiException(400, "bad_json", "The body is not valid JSON."); }
    }

    // The subject of a write is the first recognised subject key in the body, in the map's order.
    private static (string? kind, Guid? id) SubjectOf(JsonObject body, PermissionMap map)
    {
        foreach (var key in map.SubjectKeys)
        {
            var found = body.FirstOrDefault(kv => kv.Key.Equals(key, StringComparison.OrdinalIgnoreCase));
            if (found.Key is null || found.Value is null) continue;
            if (Guid.TryParse(found.Value.ToString(), out var g))
                return (key == "EntityId" ? null : key.Replace("EntityId", ""), g);
        }
        return (null, null);
    }
}
