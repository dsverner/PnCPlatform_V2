using System.Text.Json.Nodes;
using PnC.Api.Data;
using PnC.Api.Engine;
using PnC.Api.Security;

namespace PnC.Api.Endpoints;

// docs/design/API.md §8g (#171). The compliance evaluator's endpoint: what the generic dispatcher cannot do because the
// obligation rules and formulas are definitions that must be evaluated in the application (PnC.Formula over
// compliance.fFactRead) before compliance.ObligationInstance rows are written.
//   POST compliance/evaluate   {subjectKind?, subjectEntityId?, mode: "Preview" | "Effective"}
//        Preview: evaluate and report (verdicts, the facts read, the formulas' values) — writes nothing; Obligation.Read.
//        Effective: open / close obligation instances and record the facts read — Obligation.Modify.
//        A subject narrows the pass to that one subject (the device sheet's "Evaluate now"); no subject = the candidates.

public static class ComplianceEndpoints
{
    public static void Map(WebApplication app, Catalog catalog, AuthorizationService authz)
    {
        var log = app.Logger;
        app.MapPost("/api/v1/compliance/evaluate", async (HttpContext http, CancellationToken ct) =>
        {
            var body = await ReadObject(http, ct);
            var mode = body["mode"]?.GetValue<string>() ?? "Preview";
            if (mode is not ("Preview" or "Effective")) throw new ApiException(400, "bad_mode", "mode must be Preview or Effective.");
            var kind = body["subjectKind"]?.GetValue<string>();
            Guid? subject = body["subjectEntityId"] is JsonValue v && v.TryGetValue<string>(out var sid) && Guid.TryParse(sid, out var g) ? g : null;
            if (subject is not null && kind is null) kind = "Device";
            var code = mode == "Effective" ? "Obligation.Modify" : "Obligation.Read";
            await authz.RequireAsync(http.Session(), http.User(), code, subject is null ? null : "Asset", subject, $"POST compliance.evaluate ({mode})", http.Connection.RemoteIpAddress?.ToString() ?? "", ct);
            var report = await new ComplianceEvaluator(http.Session(), catalog, log).EvaluateAsync(kind, subject, mode, "Manual", ct);
            return Results.Json(report);
        });
    }

    private static async Task<JsonObject> ReadObject(HttpContext http, CancellationToken ct)
    {
        if (http.Request.ContentLength is 0) return new JsonObject();
        if (!http.Request.HasJsonContentType()) { if (http.Request.ContentLength is null) return new JsonObject(); throw new ApiException(415, "unsupported_media_type", "POST bodies must be application/json."); }
        try
        {
            // a chunked body (HttpClient's PostAsJsonAsync) has no Content-Length: read it all the same — an empty stream is an empty object
            using var reader = new StreamReader(http.Request.Body);
            var text = await reader.ReadToEndAsync(ct);
            if (string.IsNullOrWhiteSpace(text)) return new JsonObject();
            return JsonNode.Parse(text) as JsonObject ?? new JsonObject();
        }
        catch (System.Text.Json.JsonException e) { throw new ApiException(400, "bad_json", e.Message); }
    }
}
