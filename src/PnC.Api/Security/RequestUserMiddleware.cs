using PnC.Api.Data;
using PnC.Api.Endpoints;

namespace PnC.Api.Security;

// docs/design/API.md §2. For every /api request: who is this, as one enabled security.User; then
// one connection with the session context set, so the procedures attribute the act themselves.
// Presence in the directory grants nothing: no security.User row, no access.

public sealed record RequestUser(string IdentityName, Guid UserEntityId, Guid PersonEntityId, string UserPrincipalName, string DisplayName,
    Guid? DelegationEntityId, Guid? SponsoredPersonEntityId);

public sealed class RequestUserMiddleware(RequestDelegate next, IConfiguration config, IWebHostEnvironment env, ILogger<RequestUserMiddleware> log)
{
    public const string DevHeader = "X-PnC-Dev-User";
    public const string DelegationHeader = "X-PnC-Delegation";
    public const string SponsoredHeader = "X-PnC-Sponsored-Person";

    public async Task InvokeAsync(HttpContext context)
    {
        if (!context.Request.Path.StartsWithSegments("/api")) { await next(context); return; }

        var mode = config["Auth:Mode"] ?? "Windows";
        var isDev = env.EnvironmentName.Equals("DEV", StringComparison.OrdinalIgnoreCase);
        string? name;
        if (mode.Equals("Development", StringComparison.OrdinalIgnoreCase))
        {
            // §2.4: asserted identity is honoured only in Development mode AND the DEV environment.
            if (!isDev) throw new ApiException(500, "auth_mode", "Auth:Mode=Development is only valid in the DEV environment.");
            name = context.Request.Headers[DevHeader].FirstOrDefault();
        }
        else if (mode.Equals("Windows", StringComparison.OrdinalIgnoreCase))
        {
            name = context.User.Identity?.IsAuthenticated == true ? context.User.Identity.Name : null;
            // IIS presents DOMAIN\sam; security.User holds the UPN (the predecessor's QA rows read VGS01@vgsot.internal).
            // Auth:UpnSuffix maps one to the other until W2 keys users by directory SID (API.md §2.2).
            var suffix = config["Auth:UpnSuffix"];
            if (name is not null && !string.IsNullOrEmpty(suffix) && name.Contains('\') && !name.Contains('@'))
                name = name[(name.LastIndexOf('\') + 1)..] + "@" + suffix;
        }
        else throw new ApiException(500, "auth_mode", $"Auth:Mode '{mode}' is not Windows or Development.");

        if (string.IsNullOrWhiteSpace(name)) throw new ApiException(401, "unauthenticated", "No identity.");
        if (name.Length > 200 || name.Any(char.IsControl)) throw new ApiException(401, "unauthenticated", "Identity name is not acceptable.");

        var connectionString = config["Database:ConnectionString"] ?? throw new InvalidOperationException("Database:ConnectionString is not configured.");
        var ct = context.RequestAborted;

        // Identity lookup on a connection with no session context (the person is not yet known).
        RequestUser? user;
        await using (var probe = await SqlSession.OpenAsync(connectionString, null, ct))
        {
            var rows = await probe.RowsAsync("""
                SELECT TOP (1) u.EntityId, u.PersonEntityId, u.UserPrincipalName, p.DisplayName
                FROM security.vUser u JOIN personnel.vPerson p ON p.EntityId = u.PersonEntityId
                WHERE u.IsEnabled = 1 AND u.UserPrincipalName = @n
                """, new Dictionary<string, object?> { ["@n"] = name }, ct);
            if (rows.Count == 0) { log.LogWarning("Identity {Name} has no enabled security.User", name); throw new ApiException(401, "unauthenticated", "Identity is not a platform user."); }
            var r = rows[0]!;
            user = new RequestUser(name, Guid.Parse(r["EntityId"]!.ToString()), Guid.Parse(r["PersonEntityId"]!.ToString()),
                r["UserPrincipalName"]!.ToString(), r["DisplayName"]?.ToString() ?? "",
                ParseGuid(context.Request.Headers[DelegationHeader].FirstOrDefault(), DelegationHeader),
                ParseGuid(context.Request.Headers[SponsoredHeader].FirstOrDefault(), SponsoredHeader));
        }

        // The request's own connection, attributed.
        await using var session = await SqlSession.OpenAsync(connectionString,
            new SessionIdentity(user.UserPrincipalName, user.DelegationEntityId, user.SponsoredPersonEntityId), ct);
        context.Items[typeof(RequestUser)] = user;
        context.Items[typeof(SqlSession)] = session;
        await next(context);
    }

    private static Guid? ParseGuid(string? v, string header)
    {
        if (string.IsNullOrWhiteSpace(v)) return null;
        return Guid.TryParse(v, out var g) ? g : throw new ApiException(400, "bad_header", $"{header} is not a GUID.");
    }
}

public static class RequestItems
{
    public static RequestUser User(this HttpContext c) => (RequestUser)(c.Items[typeof(RequestUser)] ?? throw new ApiException(401, "unauthenticated", "No identity."));
    public static SqlSession Session(this HttpContext c) => (SqlSession)(c.Items[typeof(SqlSession)] ?? throw new InvalidOperationException("No session on this request."));
}
