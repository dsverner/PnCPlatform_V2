using PnC.Api.Data;
using PnC.Api.Security;

namespace PnC.Api.Endpoints;

// #168 (2026-09-16): the settings template's writer over HTTP.
//   GET /api/v1/settings/{revisionRowId}/rendered   the revision's parsed settings written as the settings text the relay
//                                                    and the group use (process.RenderSettingsText), text/plain — the file
//                                                    the platform will issue; a download for the technician's terminal
// Permission: ConfigurationFile.Read on the revision's device (the same subject the settings-record views carry).
public static class SettingsEndpoints
{
    public static void Map(WebApplication app, AuthorizationService authz)
    {
        app.MapGet("/api/v1/settings/{revisionRowId:guid}/rendered", async (Guid revisionRowId, HttpContext http, CancellationToken ct) =>
        {
            var u = http.User(); var s = http.Session();
            var device = await s.ScalarAsync<Guid?>("SELECT DeviceEntityId FROM document.vConfigurationFile WHERE RevisionRowId = @r", new Dictionary<string, object?> { ["@r"] = revisionRowId }, ct)
                ?? throw new ApiException(404, "unknown_revision", "No configuration-file revision has that id.");
            await authz.RequireAsync(s, u, "ConfigurationFile.Read", "Asset", device, "GET settings/rendered", http.Connection.RemoteIpAddress?.ToString() ?? "", ct);
            var text = await s.ScalarAsync<string>("SET NOCOUNT ON; DECLARE @t NVARCHAR(MAX); EXEC process.RenderSettingsText @ConfigurationFileRevisionRowId = @r, @Text = @t OUTPUT; SELECT @t",
                new Dictionary<string, object?> { ["@r"] = revisionRowId }, ct) ?? "";
            var name = await s.ScalarAsync<string>("SELECT TOP (1) FileName FROM document.vFile WHERE RevisionRowId = @r ORDER BY CASE FileRole WHEN N'Native' THEN 0 ELSE 1 END", new Dictionary<string, object?> { ["@r"] = revisionRowId }, ct);
            http.Response.Headers.ContentDisposition = $"inline; filename=\"{(string.IsNullOrEmpty(name) ? revisionRowId + ".txt" : name)}\"";
            return Results.Text(text, "text/plain; charset=utf-8");
        });
    }
}
