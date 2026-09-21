using System.Security.Cryptography;
using PnC.Api.Data;
using PnC.Api.Security;
using Microsoft.AspNetCore.Http;

namespace PnC.Api.Endpoints;

// docs/design/API.md §8c (W7, decision #144; the W6 card's item F, #136). One fixed route the generic dispatcher cannot
// provide: the bytes of a stored file.
//   GET /api/v1/files/{fileRowId}
// The file's revision's document is the subject (Document.Read, decided by the database as every read is); the bytes
// come from document.FileStore by the file's stream id; the SHA-256 the file row carries is compared before anything is
// sent (SCHEMA-DESIGN §8.1: "compared on every read"); a redacted or redaction-pending file is refused; every open is a
// logged read (config.ReadLoggedClass has document.File; audit.LogRead, FR-6.4). A file whose bytes live in the archive
// tier (FileStreamId null) answers 404 not_here.
public static class FileEndpoints
{
    public static void Map(WebApplication app, AuthorizationService authz)
    {
        // #218: the link for a desktop application — Word opens ms-word:ofv|u|<url> and fetches the url itself, so the url carries a
        // short-lived token naming this file and this user (FileLinkTokens); issued only to someone who may read the document now
        app.MapPost("/api/v1/files/{fileRowId:guid}/link", async (Guid fileRowId, HttpContext http, FileLinkTokens tokens, CancellationToken ct) =>
        {
            var u = http.User(); var s = http.Session();
            var rows = await s.RowsAsync("""
                SELECT f.FileName, f.MimeType, d.EntityId AS DocumentEntityId
                FROM document.vFile f JOIN document.vRevision r ON r.RowId = f.RevisionRowId JOIN document.vDocument d ON d.EntityId = r.DocumentEntityId
                WHERE f.RowId = @r
                """, new Dictionary<string, object?> { ["@r"] = fileRowId }, ct);
            var row = rows.FirstOrDefault() as System.Text.Json.Nodes.JsonObject ?? throw new ApiException(404, "unknown_file", "No file has that id.");
            var document = Guid.Parse(row["DocumentEntityId"]!.GetValue<string>());
            await authz.RequireAsync(s, u, "Document.Read", "Document", document, "POST files/link", http.Connection.RemoteIpAddress?.ToString() ?? "", ct);
            var (token, expires) = tokens.Issue(fileRowId, u.UserPrincipalName);
            var fileName = row["FileName"]?.GetValue<string>() ?? "file";
            var path = $"/api/v1/files/{fileRowId:D}/link/{token}/{Uri.EscapeDataString(fileName)}";
            var absolute = $"{http.Request.Scheme}://{http.Request.Host}{path}";
            var mime = row["MimeType"]?.GetValue<string>() ?? "";
            var scheme = mime.Contains("msword", StringComparison.OrdinalIgnoreCase) || mime.Contains("wordprocessingml", StringComparison.OrdinalIgnoreCase) ? "ms-word"
                       : mime.Contains("ms-excel", StringComparison.OrdinalIgnoreCase) || mime.Contains("spreadsheetml", StringComparison.OrdinalIgnoreCase) ? "ms-excel" : null;
            return Results.Ok(new { url = path, absoluteUrl = absolute, expiresAt = expires, fileName, mimeType = mime,
                                    officeUrl = scheme is null ? null : $"{scheme}:ofv|u|{absolute}" });
        });

        // the bytes: by the page (its own identity), or by a desktop application through a link (the token in the path is the identity —
        // RequestUserMiddleware; the name segment lets Word see a document); HEAD as well as GET (Word asks HEAD first)
        app.MapMethods("/api/v1/files/{fileRowId:guid}", new[] { "GET", "HEAD" }, (Guid fileRowId, HttpContext http, CancellationToken ct) => Serve(fileRowId, http, ct));
        app.MapMethods("/api/v1/files/{fileRowId:guid}/link/{token}/{name}", new[] { "GET", "HEAD" }, (Guid fileRowId, HttpContext http, CancellationToken ct) => Serve(fileRowId, http, ct));

        async Task<IResult> Serve(Guid fileRowId, HttpContext http, CancellationToken ct)
        {
            var u = http.User(); var s = http.Session();
            var rows = await s.RowsAsync("""
                SELECT f.EntityId, f.FileName, f.MimeType, f.SizeBytes, f.Sha256, f.FileStreamId, f.RedactionStatus, d.EntityId AS DocumentEntityId
                FROM document.vFile f JOIN document.vRevision r ON r.RowId = f.RevisionRowId JOIN document.vDocument d ON d.EntityId = r.DocumentEntityId
                WHERE f.RowId = @r
                """, new Dictionary<string, object?> { ["@r"] = fileRowId }, ct);
            var row = rows.FirstOrDefault() as System.Text.Json.Nodes.JsonObject ?? throw new ApiException(404, "unknown_file", "No file has that id.");
            var document = Guid.Parse(row["DocumentEntityId"]!.GetValue<string>());
            await authz.RequireAsync(s, u, "Document.Read", "Document", document, "GET files", http.Connection.RemoteIpAddress?.ToString() ?? "", ct);
            var redaction = row["RedactionStatus"]?.GetValue<string>() ?? "None";
            if (redaction != "None") throw new ApiException(403, "redacted", $"The file is {redaction}; its bytes are not served.");
            var streamId = row["FileStreamId"]?.GetValue<string>();
            if (streamId is null) throw new ApiException(404, "not_here", "The file's bytes are in the archive tier, not in the platform's store.");

            var bytes = await s.ScalarAsync<byte[]>("SELECT file_stream FROM document.FileStore WHERE stream_id = @id",
                new Dictionary<string, object?> { ["@id"] = Guid.Parse(streamId) }, ct) ?? throw new ApiException(404, "not_here", "The file store holds no bytes for this file.");
            var expected = row["Sha256"]?.GetValue<string>();   // base64 of the 32 bytes (SqlSession renders binary as base64)
            var actual = Convert.ToBase64String(SHA256.HashData(bytes));
            if (expected is not null && !string.Equals(expected, actual, StringComparison.Ordinal))
                throw new ApiException(500, "integrity", "The stored bytes do not match the SHA-256 the file row carries; nothing is served.");

            // FR-6.4: the open is a logged read of document.File (config.ReadLoggedClass, decision #144)
            await s.ExecAsync("EXEC [audit].[LogRead] @SubjectSchema = N'document', @SubjectTable = N'File', @SubjectEntityId = @e, @SubjectRowId = @r",
                new Dictionary<string, object?> { ["@e"] = Guid.Parse(row["EntityId"]!.GetValue<string>()), ["@r"] = fileRowId }, ct);

            var name = row["FileName"]?.GetValue<string>() ?? fileRowId.ToString();
            var mime = row["MimeType"]?.GetValue<string>() ?? "application/octet-stream";
            http.Response.Headers["X-Content-Type-Options"] = "nosniff";
            http.Response.Headers["Cache-Control"] = "no-store";
            // #216: a PDF (a model's instruction manual) or a text file opens in the browser's own viewer — inline, as the rendered
            // settings text does (SettingsEndpoints); ?download=1 asks for the file as a download instead. Anything else downloads.
            var wantsDownload = http.Request.Query.TryGetValue("download", out var dl) && dl.ToString() is "1" or "true";
            var inline = !wantsDownload && (mime.Equals("application/pdf", StringComparison.OrdinalIgnoreCase) || mime.StartsWith("text/", StringComparison.OrdinalIgnoreCase));
            if (inline)
            {
                http.Response.Headers.ContentDisposition = $"inline; filename=\"{name.Replace("\"", "")}\"";
                return Results.File(bytes, mime, enableRangeProcessing: true);
            }
            return Results.File(bytes, mime, fileDownloadName: name);
        }
    }
}
