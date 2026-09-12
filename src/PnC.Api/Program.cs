using Microsoft.AspNetCore.Server.IISIntegration;
using PnC.Api.Data;
using PnC.Api.Endpoints;
using PnC.Api.Security;

// docs/design/API.md. The host: catalogue and permission map at start, security headers first,
// problem mapping, identity, static shell, endpoints. Nothing here is a rule about the domain.

var builder = WebApplication.CreateBuilder(new WebApplicationOptions
{
    Args = args,
    // Production unless said otherwise: the DEV-only header needs BOTH Auth:Mode=Development AND this name = DEV,
    // so neither can be reached by an omission (API.md §2.4; security analysis W1).
    EnvironmentName = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Production",
});
builder.Configuration.AddJsonFile("appsettings.Local.json", optional: true, reloadOnChange: false);
if (OperatingSystem.IsWindows()) builder.Logging.AddEventLog();

var connectionString = builder.Configuration["Database:ConnectionString"]
                       ?? throw new InvalidOperationException("Database:ConnectionString is not configured (appsettings.Local.json on DEV; the service's settings elsewhere).");
var schemas = builder.Configuration.GetSection("Api:Schemas").Get<string[]>() ?? [];
var authMode = builder.Configuration["Auth:Mode"] ?? "Windows";
if (authMode.Equals("Development", StringComparison.OrdinalIgnoreCase) && !builder.Environment.EnvironmentName.Equals("DEV", StringComparison.OrdinalIgnoreCase))
    throw new InvalidOperationException($"Auth:Mode=Development is only valid when the environment name is DEV; this host is '{builder.Environment.EnvironmentName}'. "
        + "On the build laptop: $env:ASPNETCORE_ENVIRONMENT = 'DEV' (PowerShell) before dotnet run. (W1 card T1: `set` does not set a variable in PowerShell.)");

var catalog = Catalog.Load(connectionString, schemas);
var map = PermissionMap.Load(Path.Combine(AppContext.BaseDirectory, "api-permissions.json"));
var unseen = map.Validate(catalog);
var authz = new AuthorizationService();

if (authMode.Equals("Windows", StringComparison.OrdinalIgnoreCase))
    builder.Services.AddAuthentication(IISDefaults.AuthenticationScheme);

var app = builder.Build();
app.Logger.LogInformation("PnC.Api {Env}: catalogue {Procs} procedures, {Views} views across {Schemas} schemas; auth mode {Mode}",
    app.Environment.EnvironmentName, catalog.Procedures.Count, catalog.Views.Count, catalog.Schemas.Count, authMode);
if (unseen.Count > 0)
    app.Logger.LogInformation("api-permissions.json: {Count} not-callable entries name procedures this identity cannot see: {Names}", unseen.Count, string.Join(", ", unseen));

// 1. security headers on every response (§7): no inline anything, nothing cached under /api
app.Use(async (context, next) =>
{
    var h = context.Response.Headers;
    h["Content-Security-Policy"] = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; manifest-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'";
    h["X-Content-Type-Options"] = "nosniff";
    h["Referrer-Policy"] = "no-referrer";
    h["Cache-Control"] = context.Request.Path.StartsWithSegments("/api") ? "no-store" : "no-cache";
    await next(context);
});

// 2. errors as problem+json, in the procedures' words (§6)
Problems.Map(app, app.Logger);

// 3. identity, then the request's attributed connection (§2)
if (authMode.Equals("Windows", StringComparison.OrdinalIgnoreCase)) app.UseAuthentication();
app.UseMiddleware<RequestUserMiddleware>();

// 4. the PWA shell (§9)
app.UseDefaultFiles();
app.UseStaticFiles();

// 5. the endpoints (§6, §7)
ApiEndpoints.Map(app, catalog, map, authz, app.Environment.EnvironmentName, connectionString);

app.Run();
