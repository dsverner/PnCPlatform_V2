using System.Security.Principal;
using System.Text.Json;
using PnC.Api.Data;
using PnC.Api.Endpoints;

namespace PnC.Api.Security;

// docs/design/API.md §2, IDENTITY.md §2. For every /api request: who is this, as one enabled security.User;
// then one connection with the session context set, so the procedures attribute the act themselves.
// Presence in the directory grants nothing: no security.User row, no access.
// W2: in Windows mode the directory SID is the preferred key (security.AlternateKey, ActiveDirectorySid);
// a user found by name with no SID key yet gets one written, and the act is logged.

public sealed record RequestUser(string IdentityName, Guid UserEntityId, Guid PersonEntityId, string UserPrincipalName, string DisplayName,
    Guid? DelegationEntityId, Guid? SponsoredPersonEntityId, string IdentityKey);

public sealed class RequestUserMiddleware(RequestDelegate next, IConfiguration config, IWebHostEnvironment env, ILogger<RequestUserMiddleware> log)
{
    public const string DevHeader = "X-PnC-Dev-User";
    public const string DelegationHeader = "X-PnC-Delegation";
    public const string SponsoredHeader = "X-PnC-Sponsored-Person";
    public const string SidKeyKind = "ActiveDirectorySid";

    public async Task InvokeAsync(HttpContext context)
    {
        if (!context.Request.Path.StartsWithSegments("/api")) { await next(context); return; }

        var mode = config["Auth:Mode"] ?? "Windows";
        var isDev = env.EnvironmentName.Equals("DEV", StringComparison.OrdinalIgnoreCase);
        string? name; string? sid = null;
        if (mode.Equals("Development", StringComparison.OrdinalIgnoreCase))
        {
            // §2.4: asserted identity is honoured only in Development mode AND the DEV environment.
            if (!isDev) throw new ApiException(500, "auth_mode", "Auth:Mode=Development is only valid in the DEV environment.");
            name = context.Request.Headers[DevHeader].FirstOrDefault();
        }
        else if (mode.Equals("Windows", StringComparison.OrdinalIgnoreCase))
        {
            name = context.User.Identity?.IsAuthenticated == true ? context.User.Identity.Name : null;
            if (OperatingSystem.IsWindows() && context.User.Identity is WindowsIdentity wi) sid = wi.User?.Value;
            // IIS presents DOMAIN\sam; security.User holds the UPN (the predecessor's QA rows read VGS01@vgsot.internal).
            // Auth:UpnSuffix maps one to the other; from W2 the SID is the durable key (IDENTITY.md §2).
            var suffix = config["Auth:UpnSuffix"];
            if (name is not null && !string.IsNullOrEmpty(suffix) && name.Contains('\\') && !name.Contains('@'))
                name = name[(name.LastIndexOf('\\') + 1)..] + "@" + suffix;
        }
        else throw new ApiException(500, "auth_mode", $"Auth:Mode '{mode}' is not Windows or Development.");

        if (string.IsNullOrWhiteSpace(name)) throw new ApiException(401, "unauthenticated", "No identity.");
        if (name.Length > 200 || name.Any(char.IsControl)) throw new ApiException(401, "unauthenticated", "Identity name is not acceptable.");
        if (sid is not null && (sid.Length > 200 || !sid.StartsWith("S-", StringComparison.Ordinal))) sid = null;

        var connectionString = config["Database:ConnectionString"] ?? throw new InvalidOperationException("Database:ConnectionString is not configured.");
        var ct = context.RequestAborted;

        // Identity lookup on a connection with no session context (the person is not yet known): SID first, then the name.
        RequestUser? user; var writeSid = false;
        await using (var probe = await SqlSession.OpenAsync(connectionString, null, ct))
        {
            System.Text.Json.Nodes.JsonArray rows = new();
            if (sid is not null)
                rows = await probe.RowsAsync("""
                    SELECT TOP (1) u.EntityId, u.PersonEntityId, u.UserPrincipalName, p.DisplayName
                    FROM security.vAlternateKey k
                    JOIN security.vUser u ON u.EntityId = k.SubjectEntityId AND u.IsEnabled = 1
                    JOIN personnel.vPerson p ON p.EntityId = u.PersonEntityId
                    WHERE k.KeyKindCode = @kind AND k.KeyValue = @sid
                    """, new Dictionary<string, object?> { ["@kind"] = SidKeyKind, ["@sid"] = sid }, ct);
            var byKey = rows.Count > 0 ? "sid" : "upn";
            if (rows.Count == 0)
            {
                rows = await probe.RowsAsync("""
                    SELECT TOP (1) u.EntityId, u.PersonEntityId, u.UserPrincipalName, p.DisplayName
                    FROM security.vUser u JOIN personnel.vPerson p ON p.EntityId = u.PersonEntityId
                    WHERE u.IsEnabled = 1 AND u.UserPrincipalName = @n
                    """, new Dictionary<string, object?> { ["@n"] = name }, ct);
                writeSid = rows.Count > 0 && sid is not null;
                // W2 card D1 (#95 amended): a user found by name who already carries a different SID is a re-created
                // directory account. Refused until an Administrator confirms the person; never registered beside.
                if (writeSid)
                {
                    var uid = Guid.Parse(rows[0]!["EntityId"]!.ToString());
                    var other = await probe.ScalarAsync<int>("""
                        SELECT COUNT(*) FROM security.vAlternateKey k WHERE k.SubjectEntityId = @u AND k.KeyKindCode = @kind AND k.KeyValue <> @sid
                        """, new Dictionary<string, object?> { ["@u"] = uid, ["@kind"] = SidKeyKind, ["@sid"] = sid }, ct);
                    if (other > 0)
                    {
                        log.LogWarning("Identity {Name} presents a SID different from the one on record; refused until an Administrator confirms", name);
                        throw new ApiException(401, "identity_changed", "This account's directory identity has changed; an Administrator must confirm it before it can sign in.");
                    }
                }
            }
            if (rows.Count == 0) { log.LogWarning("Identity {Name} has no enabled security.User", name); throw new ApiException(401, "unauthenticated", "Identity is not a platform user."); }
            var r = rows[0]!;
            user = new RequestUser(name, Guid.Parse(r["EntityId"]!.ToString()), Guid.Parse(r["PersonEntityId"]!.ToString()),
                r["UserPrincipalName"]!.ToString(), r["DisplayName"]?.ToString() ?? "",
                ParseGuid(context.Request.Headers[DelegationHeader].FirstOrDefault(), DelegationHeader),
                ParseGuid(context.Request.Headers[SponsoredHeader].FirstOrDefault(), SponsoredHeader), byKey);
        }

        // The request's own connection, attributed.
        await using var session = await SqlSession.OpenAsync(connectionString,
            new SessionIdentity(user.UserPrincipalName, user.DelegationEntityId, user.SponsoredPersonEntityId), ct);

        // First sign-in with a SID for a user known by name: record the SID as the user's alternate key, attributed to
        // the user themselves, and log it. A failure here never fails the request; the name still identified the user.
        if (writeSid)
        {
            try
            {
                await session.ExecAsync("EXEC [security].[AlternateKey_Add] @SubjectEntityId = @u, @KeyKindCode = @kind, @KeyValue = @sid",
                    new Dictionary<string, object?> { ["@u"] = user.UserEntityId, ["@kind"] = SidKeyKind, ["@sid"] = sid }, ct);
                await session.ExecAsync("EXEC [audit].[LogAction] @ActionKindCode = N'Administrative', @SubjectSchema = N'security', @SubjectTable = N'User', @SubjectEntityId = @u, @Detail = @d",
                    new Dictionary<string, object?> { ["@u"] = user.UserEntityId, ["@d"] = JsonSerializer.Serialize(new { action = "sid-registered", sid, byName = user.UserPrincipalName }) }, ct);
                log.LogInformation("Registered the directory SID for {Upn}", user.UserPrincipalName);
            }
            catch (Exception e) { log.LogWarning(e, "Could not record the directory SID for {Upn}", user.UserPrincipalName); }
        }

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
