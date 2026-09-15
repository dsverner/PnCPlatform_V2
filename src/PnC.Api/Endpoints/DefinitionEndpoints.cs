using System.Text.Json;
using System.Text.Json.Nodes;
using PnC.Api.Data;
using PnC.Api.Definitions;
using PnC.Api.Security;
using PnC.Formula;

namespace PnC.Api.Endpoints;

// docs/design/API.md §8 (W3). Three endpoints the generic dispatcher cannot provide because they need the grammar library:
//   POST /api/v1/definitions/documents                  an authored procedure or workflow document → a Draft version
//   POST /api/v1/definitions/documents/{versionRowId}/approve   approval (segregation in the database) and, for a procedure, projection
//   POST /api/v1/formula/check                          one expression type-checked against the catalogue (the live check of §8)
//   GET  /api/v1/screens                                the Effective screen definitions the person may open (#165)
// Permissions are the map's for the procedures called (Definition.Modify / Definition.Approve); refusals log as every other.
// The document kinds are a table (#165): each names its schema file, its definition kind, the procedures that store and
// approve it, and whether its expressions are compiled. A new kind of document is a row here and a seed row in
// ref.DefinitionKind — never a new endpoint.

public static class DefinitionEndpoints
{
    public static void Map(WebApplication app, Catalog catalog, PermissionMap map, AuthorizationService authz)
    {
        var schemaDir = Path.Combine(AppContext.BaseDirectory, "Schemas");
        SchemaCheck Load(string file) => new((JsonObject)JsonNode.Parse(File.ReadAllText(Path.Combine(schemaDir, file)))!);
        var kinds = new Dictionary<string, DocKind>(StringComparer.Ordinal)
        {
            ["procedure"] = new("procedure", "Program.Procedure", Load("procedure.schema.json"), Compiled: true, AddSchema: "process", AddProc: "AddProcedureVersion", ValidateProc: "ValidateProcedureDocument", ApproveSchema: "process", ApproveProc: "ApproveProcedureVersion"),
            ["workflow"] = new("workflow", "Program.Workflow", Load("workflow.schema.json"), Compiled: true, AddSchema: "process", AddProc: "AddWorkflowVersion", ValidateProc: "ValidateWorkflowDocument", ApproveSchema: "config", ApproveProc: "ApproveDefinitionVersion"),
            ["screen"] = new("screen", "Program.Screen", Load("screen.schema.json"), Compiled: false, AddSchema: "config", AddProc: "AddDefinitionVersion", ValidateProc: null, ApproveSchema: "config", ApproveProc: "ApproveDefinitionVersion"),
        };
        var byDefinitionKind = kinds.Values.ToDictionary(k => k.DefinitionKind, StringComparer.Ordinal);
        var kindList = string.Join(", ", kinds.Keys.Select(k => $"'{k}'"));

        app.MapPost("/api/v1/definitions/documents", async (HttpContext http, CancellationToken ct) =>
        {
            var u = http.User(); var s = http.Session();
            // W5 (decision #120): ?dryRun=true compiles and applies the database's structural rules but stores nothing —
            // the editor's live check. Any signed-in person may dry-run (as /formula/check); storing needs Definition.Modify.
            var dryRun = string.Equals(http.Request.Query["dryRun"], "true", StringComparison.OrdinalIgnoreCase);
            var body = await ReadObject(http, ct);
            var doc = body["document"] as JsonObject ?? throw new ApiException(400, "bad_request", "The body must carry a 'document' object (and may carry 'changeNote').");
            var kind = doc["kind"]?.GetValue<string>() ?? "";
            if (!kinds.TryGetValue(kind, out var dk)) throw new ApiException(400, "bad_request", $"document.kind must be one of {kindList}.");
            var proc = catalog.Procedure(dk.AddSchema, dk.AddProc) ?? throw new ApiException(500, "internal", $"{dk.AddSchema}.{dk.AddProc} is not in the catalogue.");
            var code = map.ForProcedure(dk.AddSchema, dk.AddProc) ?? throw new ApiException(404, "not_callable", $"{dk.AddSchema}.{dk.AddProc} is not callable over the API.");
            if (!dryRun)
                await authz.RequireAsync(s, u, code, map.SubjectClass(dk.AddSchema, dk.AddProc), null, $"POST {dk.AddSchema}.{dk.AddProc}", http.Connection.RemoteIpAddress?.ToString() ?? "", ct);

            string canonical;
            if (dk.Compiled)
            {
                var live = await LiveCatalogue.LoadAsync(s, ct);
                var wfKinds = await WorkflowSubjectKinds(s, ct);
                try { canonical = DocumentCompiler.Compile(doc, dk.Schema, live, wfKinds); }
                catch (CompileException e)
                {
                    http.Response.StatusCode = 400;
                    return Results.Json(new { status = 400, code = "document_invalid", detail = $"{e.Errors.Count} problem(s) in the document.", errors = e.Errors }, statusCode: 400);
                }
            }
            else
            {
                // a document with no expressions: the schema is the whole check, and the stored form is the document itself
                var violations = dk.Schema.Validate(doc);
                if (violations.Count > 0)
                    return Results.Json(new { status = 400, code = "document_invalid", detail = $"{violations.Count} problem(s) in the document.", errors = violations.Select(v => new CompileError(v.Path, "schema", v.Message)) }, statusCode: 400);
                canonical = doc.ToJsonString();
            }

            if (dryRun)
            {
                // the structural rules (ValidateProcedureDocument / ValidateWorkflowDocument) answer in their own words
                if (dk.ValidateProc is not null)
                {
                    try
                    {
                        await s.ExecAsync($"EXEC process.{dk.ValidateProc} @Canonical = @c", new Dictionary<string, object?> { ["@c"] = canonical }, ct);
                    }
                    catch (Microsoft.Data.SqlClient.SqlException e) when (e.Number >= 50000)
                    {
                        return Results.Json(new { status = 400, code = "document_invalid", detail = "1 problem(s) in the document.",
                            errors = new[] { new CompileError("$", $"rule {e.Number}", e.Message) } }, statusCode: 400);
                    }
                }
                return Results.Json(new { ok = true, kind, key = doc["key"]?.GetValue<string>(), canonical = JsonNode.Parse(canonical), canonicalLength = canonical.Length });
            }

            JsonObject result;
            if (dk.Compiled)
            {
                result = await s.ExecuteProcedureAsync(proc, new JsonObject { ["Canonical"] = canonical, ["ChangeNote"] = body["changeNote"]?.DeepClone() }, ct);
            }
            else
            {
                // config.AddDefinition once per key (the definition), then a Draft version of it — the generic pair the seeds use (#165)
                var key = doc["key"]!.GetValue<string>();
                var defEntity = await s.ScalarAsync<Guid?>("SELECT EntityId FROM config.vDefinition WHERE DefinitionKind = @k AND DefinitionKey = @key",
                    new Dictionary<string, object?> { ["@k"] = dk.DefinitionKind, ["@key"] = key }, ct);
                if (defEntity is null)
                {
                    var addDef = catalog.Procedure("config", "AddDefinition") ?? throw new ApiException(500, "internal", "config.AddDefinition is not in the catalogue.");
                    var added = await s.ExecuteProcedureAsync(addDef, new JsonObject { ["DefinitionKind"] = dk.DefinitionKind, ["DefinitionKey"] = key, ["Name"] = doc["name"]?.DeepClone(), ["Description"] = doc["description"]?.DeepClone() }, ct);
                    defEntity = Guid.Parse(added["EntityId"]!.GetValue<string>());
                }
                result = await s.ExecuteProcedureAsync(proc, new JsonObject { ["DefinitionKey"] = key, ["DefinitionKind"] = dk.DefinitionKind, ["PayloadText"] = canonical, ["ChangeNote"] = body["changeNote"]?.DeepClone() }, ct);
                result["DefinitionEntityId"] = defEntity.ToString();
                result["Existing"] = false;
            }
            return Results.Json(new
            {
                kind, key = doc["key"]?.GetValue<string>(),
                definitionEntityId = result["DefinitionEntityId"], versionRowId = result["VersionRowId"], versionNumber = result["VersionNumber"],
                existing = result["Existing"], canonicalLength = canonical.Length,
            });
        });

        // W5: one stored version read back for the editor — the payload with every expression printed as grammar text
        app.MapGet("/api/v1/definitions/documents/{versionRowId:guid}", async (Guid versionRowId, HttpContext http, CancellationToken ct) =>
        {
            var u = http.User(); var s = http.Session();
            await authz.RequireAsync(s, u, "Definition.Read", "DefinitionVersion", versionRowId, "GET definitions/documents", http.Connection.RemoteIpAddress?.ToString() ?? "", ct);
            var rows = await s.RowsAsync("""
                SELECT d.DefinitionKind, d.DefinitionKey, d.Name, dv.VersionNumber, dv.Status, dv.EffectiveFrom, dv.EffectiveTo, dv.ApprovedAt, dv.ChangeNote, dv.PayloadText
                FROM config.vDefinitionVersion dv JOIN config.vDefinition d ON d.EntityId = dv.DefinitionEntityId WHERE dv.RowId = @r
                """, new Dictionary<string, object?> { ["@r"] = versionRowId }, ct);
            var row = rows.FirstOrDefault() as JsonObject ?? throw new ApiException(404, "unknown_version", "No definition version has that id.");
            var kind = row["DefinitionKind"]?.GetValue<string>() ?? "";
            if (!byDefinitionKind.TryGetValue(kind, out var dk))
                throw new ApiException(400, "bad_request", $"{kind} is not a document kind the editor handles ({kindList}).");
            var stored = JsonNode.Parse(row["PayloadText"]!.GetValue<string>()) as JsonObject ?? throw new ApiException(500, "internal", "The stored payload is not a JSON object.");
            var text = dk.Compiled ? DocumentCompiler.Decompile((JsonObject)stored.DeepClone()) : (JsonObject)stored.DeepClone();
            return Results.Json(new
            {
                versionRowId, kind, key = row["DefinitionKey"]?.DeepClone(), name = row["Name"]?.DeepClone(), versionNumber = row["VersionNumber"]?.DeepClone(), status = row["Status"]?.DeepClone(),
                effectiveFrom = row["EffectiveFrom"]?.DeepClone(), effectiveTo = row["EffectiveTo"]?.DeepClone(), approvedAt = row["ApprovedAt"]?.DeepClone(), changeNote = row["ChangeNote"]?.DeepClone(),
                document = text, canonical = stored,
            });
        });

        app.MapPost("/api/v1/definitions/documents/{versionRowId:guid}/approve", async (Guid versionRowId, HttpContext http, CancellationToken ct) =>
        {
            var u = http.User(); var s = http.Session();
            var body = await ReadObject(http, ct);
            var kind = await s.ScalarAsync<string>("""
                SELECT d.DefinitionKind FROM config.vDefinitionVersion dv JOIN config.vDefinition d ON d.EntityId = dv.DefinitionEntityId WHERE dv.RowId = @r
                """, new Dictionary<string, object?> { ["@r"] = versionRowId }, ct);
            if (kind is null) throw new ApiException(404, "unknown_version", "No definition version has that id.");
            if (!byDefinitionKind.TryGetValue(kind, out var dk))
                throw new ApiException(400, "bad_request", $"{kind} is not a document kind the editor handles ({kindList}); approve it through config.ApproveDefinitionVersion.");
            var (schema, procName) = (dk.ApproveSchema, dk.ApproveProc);
            var proc = catalog.Procedure(schema, procName) ?? throw new ApiException(500, "internal", $"{schema}.{procName} is not in the catalogue.");
            var code = map.ForProcedure(schema, procName) ?? throw new ApiException(404, "not_callable", $"{schema}.{procName} is not callable over the API.");
            await authz.RequireAsync(s, u, code, "DefinitionVersion", versionRowId, $"POST {schema}.{procName}", http.Connection.RemoteIpAddress?.ToString() ?? "", ct);
            var args = new JsonObject { ["VersionRowId"] = versionRowId.ToString() };
            foreach (var k in new[] { "EffectiveFrom", "OverrideReason", "OverrideApprovedByActorId" })
                if (body[k] is not null) args[k] = body[k]!.DeepClone();
            await s.ExecuteProcedureAsync(proc, args, ct);
            var steps = kind == "Program.Procedure"
                ? await s.ScalarAsync<int>("SELECT COUNT(*) FROM process.vProcedureStep WHERE DefinitionVersionRowId = @r", new Dictionary<string, object?> { ["@r"] = versionRowId }, ct)
                : 0;
            return Results.Json(new { versionRowId, kind, approved = true, projectedSteps = steps });
        });

        // #165: the Effective screen definitions the person may open — the navigation is built from this, so it needs no
        // Definition.Read: a screen's own `permission` decides, against the permission codes /me lists.
        app.MapGet("/api/v1/screens", async (HttpContext http, CancellationToken ct) =>
        {
            var u = http.User(); var s = http.Session();
            var held = await ApiEndpoints.PermissionCodes(s, u, ct);
            var rows = await s.RowsAsync("""
                SELECT d.DefinitionKey, d.Name, dv.RowId AS VersionRowId, dv.VersionNumber, dv.PayloadText
                FROM config.vDefinition d JOIN config.vDefinitionVersion dv ON dv.DefinitionEntityId = d.EntityId
                WHERE d.DefinitionKind = N'Program.Screen' AND dv.Status = N'Effective'
                  AND dv.EffectiveFrom <= SYSDATETIMEOFFSET() AND (dv.EffectiveTo IS NULL OR dv.EffectiveTo > SYSDATETIMEOFFSET())
                ORDER BY d.DefinitionKey
                """, new Dictionary<string, object?>(), ct);
            var screens = new List<object>();
            foreach (var r in rows.Select(r => (JsonObject)r!))
            {
                if (JsonNode.Parse(r["PayloadText"]!.GetValue<string>()) is not JsonObject doc) continue;
                var permission = doc["permission"]?.GetValue<string>();
                if (permission is not null && !held.Contains(permission)) continue;
                screens.Add(new
                {
                    key = r["DefinitionKey"]?.GetValue<string>(), name = doc["name"]?.GetValue<string>() ?? r["Name"]?.GetValue<string>(), description = doc["description"]?.GetValue<string>(),
                    versionRowId = r["VersionRowId"]?.DeepClone(), versionNumber = r["VersionNumber"]?.DeepClone(),
                    menu = doc["menu"]?.DeepClone(), permission, screenKind = doc["screenKind"]?.GetValue<string>(), @params = doc["params"]?.DeepClone(),
                });
            }
            return Results.Json(new { screens });
        });

        app.MapPost("/api/v1/formula/check", async (HttpContext http, CancellationToken ct) =>
        {
            var u = http.User(); var s = http.Session();
            var body = await ReadObject(http, ct);
            var text = body["expression"]?.GetValue<string>() ?? throw new ApiException(400, "bad_request", "The body must carry 'expression' (text).");
            var subjectKind = body["subjectKind"]?.GetValue<string>();
            var env = new Dictionary<string, FormulaType>(StringComparer.Ordinal);
            if (body["env"] is JsonObject e)
                foreach (var (n, vt) in e) env[n] = DocumentCompiler.ValueType((JsonObject)vt!);
            var live = await LiveCatalogue.LoadAsync(s, ct);
            try
            {
                var ast = Parser.Parse(text);
                var checker = new Checker(live);
                var t = checker.Check(ast, env, subjectKind);
                return Results.Json(new { ok = true, type = t.ToString(), facts = checker.FactsUsed.OrderBy(x => x, StringComparer.Ordinal), canonical = Canonical.Order(ast) });
            }
            catch (FormulaException fe)
            {
                return Results.Json(new { ok = false, code = fe.Code, message = fe.Message, position = fe.Position });
            }
        });
    }

    /// <summary>One kind of authored document: its schema, how it is stored and approved, and whether it carries expressions to compile.</summary>
    private sealed record DocKind(string DocumentKind, string DefinitionKind, SchemaCheck Schema, bool Compiled, string AddSchema, string AddProc, string? ValidateProc, string ApproveSchema, string ApproveProc);

    private static async Task<IReadOnlyDictionary<string, string>> WorkflowSubjectKinds(SqlSession s, CancellationToken ct)
    {
        var rows = await s.RowsAsync("""
            SELECT d.DefinitionKey, JSON_VALUE(dv.PayloadText, '$.subjectKind') AS SubjectKind
            FROM config.vDefinition d JOIN config.vDefinitionVersion dv ON dv.DefinitionEntityId = d.EntityId
            WHERE d.DefinitionKind = N'Program.Workflow' AND dv.Status = N'Effective'
              AND dv.EffectiveFrom <= SYSDATETIMEOFFSET() AND (dv.EffectiveTo IS NULL OR dv.EffectiveTo > SYSDATETIMEOFFSET())
            """, new Dictionary<string, object?>(), ct);
        return rows.Select(r => (JsonObject)r!).Where(r => r["SubjectKind"] is not null)
            .ToDictionary(r => r["DefinitionKey"]!.GetValue<string>(), r => r["SubjectKind"]!.GetValue<string>(), StringComparer.Ordinal);
    }

    private static async Task<JsonObject> ReadObject(HttpContext http, CancellationToken ct)
    {
        if (!http.Request.HasJsonContentType())
            throw new ApiException(415, "unsupported_media_type", "POST bodies must be application/json.");
        if (http.Request.ContentLength is 0) return new JsonObject();
        try
        {
            var node = await JsonNode.ParseAsync(http.Request.Body, cancellationToken: ct);
            return node switch { null => new JsonObject(), JsonObject o => o, _ => throw new ApiException(400, "bad_json", "The body must be a JSON object.") };
        }
        catch (JsonException) { throw new ApiException(400, "bad_json", "The body is not valid JSON."); }
    }
}
