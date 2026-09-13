using System.Text.Json;
using System.Text.Json.Nodes;
using PnC.Api.Data;
using PnC.Api.Security;

namespace PnC.Api.Endpoints;

// docs/design/API.md §5–§7, IDENTITY.md §5. The generic dispatcher and the three fixed endpoints. A handler
// validates the request shape, decides one permission, calls the procedure or view, returns. W2: a list read
// is scoped by security.fReadableSubjects; a write's subject comes from the map's typed subject keys.

public static class ApiEndpoints
{
    public static void Map(WebApplication app, Catalog catalog, PermissionMap map, AuthorizationService authz, string environmentName, string connectionString)
    {
        var maxTake = app.Configuration.GetValue<int?>("Api:MaxTake") ?? 500;

        // ---- /health: no identity of its own, its own connection, no data (§7)
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
                SELECT g.EntityId, g.RoleCode, g.ScopeKind, g.ScopeNodeEntityId, n.Name AS ScopeNodeName, g.ScopeAssetClassCode, g.ValidFrom
                FROM security.fGrantAsOf(SYSDATETIMEOFFSET(), SYSUTCDATETIME()) g
                LEFT JOIN location.vNode n ON n.EntityId = g.ScopeNodeEntityId
                WHERE g.GranteeKind = N'User' AND g.GranteeEntityId = @u AND g.RevokedByActorId IS NULL AND g.IsDeleted = 0
                ORDER BY g.RoleCode
                """, args, ct);
            var delegations = await s.RowsAsync("""
                SELECT EntityId, FromPersonEntityId, RoleCode, StartsAt, EndsAt
                FROM security.fDelegationAsOf(SYSDATETIMEOFFSET(), SYSUTCDATETIME())
                WHERE ToPersonEntityId = @p AND RevokedByActorId IS NULL AND IsDeleted = 0
                  AND StartsAt <= SYSDATETIMEOFFSET() AND (EndsAt IS NULL OR EndsAt > SYSDATETIMEOFFSET())
                ORDER BY StartsAt
                """, args, ct);
            // W5: the permission codes the person's roles carry (grants and delegations in force), so a screen can say
            // what it will refuse before the API does; the API's own check is still the one that decides.
            var permissions = await s.RowsAsync("""
                SELECT DISTINCT rp.PermissionCode
                FROM security.vRolePermission rp
                WHERE rp.RoleCode IN (
                    SELECT g.RoleCode FROM security.fGrantAsOf(SYSDATETIMEOFFSET(), SYSUTCDATETIME()) g
                    WHERE g.GranteeKind = N'User' AND g.GranteeEntityId = @u AND g.RevokedByActorId IS NULL AND g.IsDeleted = 0
                    UNION SELECT dl.RoleCode FROM security.fDelegationAsOf(SYSDATETIMEOFFSET(), SYSUTCDATETIME()) dl
                    WHERE dl.ToPersonEntityId = @p AND dl.RevokedByActorId IS NULL AND dl.IsDeleted = 0
                      AND dl.StartsAt <= SYSDATETIMEOFFSET() AND (dl.EndsAt IS NULL OR dl.EndsAt > SYSDATETIMEOFFSET()))
                ORDER BY rp.PermissionCode
                """, args, ct);
            // W8 (#149, the grants screen): the session's own actor, resolved by the database (personnel.ResolveActor from the
            // session context) — a grant names who granted it (@GrantedByActorId), and that is this id, never one the page picks
            var actorId = await s.ScalarAsync<Guid?>("SET NOCOUNT ON; DECLARE @a UNIQUEIDENTIFIER; EXEC personnel.ResolveActor @ActorId = @a OUTPUT; SELECT @a", new Dictionary<string, object?>(), ct);
            return Results.Json(new
            {
                user = new { entityId = u.UserEntityId, userPrincipalName = u.UserPrincipalName, identityKey = u.IdentityKey },
                person = new { entityId = u.PersonEntityId, displayName = u.DisplayName },
                actorId,
                actingAs = new { delegation = u.DelegationEntityId, sponsoredPerson = u.SponsoredPersonEntityId },
                grants, delegations,
                permissions = permissions.Select(r => r!["PermissionCode"]!.GetValue<string>()).ToList(),
            });
        });

        // ---- /api/v1/catalog: everything callable, with its permission code and, for views, how a list is scoped (§3, IDENTITY §5)
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
                scope = v.SubjectColumn is null ? "class" : $"{v.SubjectColumn} as {v.SubjectFamily}",
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
            var (kind, id) = SubjectOf(body, map, map.SubjectClass(proc.Schema, proc.Name));
            await authz.RequireAsync(s, u, code, kind, id, $"POST {proc.Key}", http.Connection.RemoteIpAddress?.ToString() ?? "", ct);
            var result = await s.ExecuteProcedureAsync(proc, body, ct);
            return Results.Json(result);
        });

        // ---- GET /api/v1/{schema}/{view} (§6; IDENTITY §5 for the scope)
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

            // A single-entity read is decided on that entity (the subject column's kind); a list on the class, then scoped row by row.
            Guid? subject = null; string? subjectKind = null;
            if (v.SubjectColumn is not null && filters.TryGetValue(v.SubjectColumn, out var e) && Guid.TryParse(e, out var g))
            {
                subject = g;
                subjectKind = v.SubjectFamily == "Any" ? (filters.TryGetValue("SubjectKind", out var sk2) ? sk2 : null) : v.SubjectFamily;
            }
            // A list of a scoped view: held in any scope, then the rows are filtered. A single entity, or an unscoped view: fHasPermission.
            if (subject is null && v.SubjectColumn is not null)
                await authz.RequireHeldAsync(s, u, code, $"GET {v.Key}", http.Connection.RemoteIpAddress?.ToString() ?? "", ct);
            else
                await authz.RequireAsync(s, u, code, subjectKind ?? map.SubjectClass(v.Schema, v.Name), subject, $"GET {v.Key}", http.Connection.RemoteIpAddress?.ToString() ?? "", ct);

            // FR-6.4: a read of a logged class is written to the action log before the rows are returned.
            var baseTable = v.IsAsOfFunction ? v.Name[1..^4] : v.Name[1..];
            if (catalog.ReadLoggedTables.Contains($"{v.Schema}.{baseTable}"))
                await s.ExecAsync("EXEC [audit].[LogRead] @SubjectSchema = @sc, @SubjectTable = @tb, @SubjectEntityId = @id",
                    new Dictionary<string, object?> { ["@sc"] = v.Schema, ["@tb"] = baseTable, ["@id"] = subject }, ct);

            var scope = v.SubjectColumn is null ? null : new ScopeFilter(v.SubjectColumn, v.SubjectFamily!, u.UserEntityId, code, v.Columns.Any(c => c.Name == "SubjectKind") ? "SubjectKind" : null);
            var rows = await s.QueryViewAsync(v, filters, q["orderBy"].FirstOrDefault(), skip, take, asOf, scope, ct);
            return Results.Json(new { view = v.Key, skip, take, scope = scope is null ? "class" : $"{scope.Column} as {scope.Family}", rows });
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

    /// <summary>
    /// The subject of a write: the first typed subject key the body carries, in the map's order (IDENTITY.md §5;
    /// API-W1-SECURITY.md #11). A key whose kind is "*" takes the object's class; "$SubjectKind" takes the body's
    /// SubjectKind field. No key: the class alone, which a scoped grant never covers (fHasPermission, fail closed).
    /// </summary>
    private static (string? kind, Guid? id) SubjectOf(JsonObject body, PermissionMap map, string? classKind)
    {
        foreach (var sk in map.SubjectKeys)
        {
            var found = body.FirstOrDefault(kv => kv.Key.Equals(sk.Key, StringComparison.OrdinalIgnoreCase));
            if (found.Key is null || found.Value is null) continue;
            if (!Guid.TryParse(found.Value.ToString(), out var g)) continue;
            var kind = sk.Kind switch
            {
                "*" => classKind,
                "$SubjectKind" => body.FirstOrDefault(kv => kv.Key.Equals("SubjectKind", StringComparison.OrdinalIgnoreCase)).Value?.ToString() ?? classKind,
                "$MemberKind" => body.FirstOrDefault(kv => kv.Key.Equals("MemberKind", StringComparison.OrdinalIgnoreCase)).Value?.ToString() ?? classKind,
                _ => sk.Kind
            };
            return (kind, g);
        }
        return (classKind, null);
    }
}
