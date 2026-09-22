using System.Text.Json.Nodes;
using PnC.Api.Data;
using PnC.Api.Engine;
using PnC.Api.Security;

namespace PnC.Api.Endpoints;

// #219 (2026-09-21): the structured rationale over HTTP (RationaleEngine).
//   GET  /api/v1/rationale/{settingsRevisionRowId}[?line=<assetEntityId>]  the template (inputs, sections), the element map, the line
//        and the facts resolved (and the ones missing), the stored inputs, the last result and files — what the Rationale tab shows
//   POST /api/v1/rationale/{settingsRevisionRowId}/apply  { inputs: {key: value…, FaultStudy: [[…]]}, lineAssetEntityId? }
//        evaluates the sections, writes the settings on the outstanding revision, files rationale.json and rationale.docx
// Permission: ConfigurationFile.Read / ConfigurationFile.Modify on the revision's device (the subject the settings views carry).
public static class RationaleEndpoints
{
    public static void Map(WebApplication app, AuthorizationService authz)
    {
        app.MapGet("/api/v1/rationale/{revisionRowId:guid}", async (Guid revisionRowId, HttpContext http, CancellationToken ct) =>
        {
            var u = http.User(); var s = http.Session();
            var device = await DeviceOf(s, revisionRowId, ct);
            await authz.RequireAsync(s, u, "ConfigurationFile.Read", "Asset", device, "GET rationale", http.Connection.RemoteIpAddress?.ToString() ?? "", ct);
            Guid? line = Guid.TryParse(http.Request.Query["line"].FirstOrDefault(), out var lg) ? lg : null;
            var st = await RationaleEngine.LoadAsync(s, revisionRowId, line, ct);
            return Results.Json(RationaleEngine.Describe(st));
        });
        app.MapPost("/api/v1/rationale/{revisionRowId:guid}/apply", async (Guid revisionRowId, HttpContext http, CancellationToken ct) =>
        {
            var u = http.User(); var s = http.Session();
            var device = await DeviceOf(s, revisionRowId, ct);
            await authz.RequireAsync(s, u, "ConfigurationFile.Modify", "Asset", device, "POST rationale/apply", http.Connection.RemoteIpAddress?.ToString() ?? "", ct);
            JsonObject body;
            try { body = await JsonNode.ParseAsync(http.Request.Body, cancellationToken: ct) as JsonObject ?? new JsonObject(); }
            catch (System.Text.Json.JsonException) { throw new ApiException(400, "bad_json", "The body is not a JSON object."); }
            Guid? line = Guid.TryParse(body["lineAssetEntityId"]?.ToString(), out var lg) ? lg : null;
            var st = await RationaleEngine.LoadAsync(s, revisionRowId, line, ct);
            // the session carries the identity (RequestUserMiddleware); the actor is the one the procedures would resolve themselves
            var actor = await s.ScalarAsync<Guid?>("SET NOCOUNT ON; DECLARE @a UNIQUEIDENTIFIER; EXEC personnel.ResolveActor @ActorId = @a OUTPUT; SELECT @a", new Dictionary<string, object?>(), ct)
                        ?? throw new ApiException(500, "actor", "No actor for this user.");
            var result = await RationaleEngine.ApplyAsync(s, st, body["inputs"] as JsonObject ?? new JsonObject(), actor, u.DisplayName, ct);
            return Results.Json(result);
        });
    }

    static async Task<Guid> DeviceOf(SqlSession s, Guid revisionRowId, CancellationToken ct) =>
        await s.ScalarAsync<Guid?>("SELECT DeviceEntityId FROM document.vConfigurationFile WHERE RevisionRowId = @r", new Dictionary<string, object?> { ["@r"] = revisionRowId }, ct)
        ?? throw new ApiException(404, "unknown_revision", "No configuration-file revision has that id.");
}
