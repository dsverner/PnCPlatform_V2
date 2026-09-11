using System.Text.Json;
using Microsoft.Data.SqlClient;

namespace PnC.Api.Endpoints;

// docs/design/API.md §6. Errors are the procedures' errors: a THROW (≥ 50000) returns as 409 with
// the procedure's own message and number. Constraint violations are 409 too. Everything else is a
// 500 with the detail withheld and logged.

public sealed class ApiException(int status, string code, string detail) : Exception(detail)
{
    public int Status { get; } = status;
    public string Code { get; } = code;
}

public static class Problems
{
    public static void Map(IApplicationBuilder app, ILogger log)
    {
        app.Use(async (context, next) =>
        {
            try { await next(context); }
            catch (ApiException e) { await Write(context, e.Status, e.Code, e.Message, null); }
            catch (SqlException e) when (e.Number >= 50000) { await Write(context, 409, "rule", e.Message, e.Number); }
            catch (SqlException e) when (e.Number is 2627 or 2601 or 547) { await Write(context, 409, "constraint", e.Message, e.Number); }
            catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested) { /* the client left */ }
            catch (Exception e)
            {
                log.LogError(e, "Unhandled error on {Method} {Path}", context.Request.Method, context.Request.Path);
                await Write(context, 500, "internal", "The request failed; the error has been logged.", null);
            }
        });
    }

    private static async Task Write(HttpContext context, int status, string code, string detail, int? sqlNumber)
    {
        if (context.Response.HasStarted) return;
        // no Clear(): the security headers set before this middleware must survive on error responses
        context.Response.StatusCode = status;
        context.Response.ContentType = "application/problem+json";
        var body = new Dictionary<string, object?> { ["status"] = status, ["code"] = code, ["detail"] = detail };
        if (sqlNumber is not null) body["sqlNumber"] = sqlNumber;
        await context.Response.WriteAsync(JsonSerializer.Serialize(body));
    }
}
