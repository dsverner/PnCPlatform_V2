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
// W8 (#156): a second host on the build laptop pointed at another V2 database (a probe or a sweep of QA) — an explicit
// environment override that outranks appsettings.Local.json, which otherwise wins over every environment variable
if (Environment.GetEnvironmentVariable("PNC_CONNECTION") is { Length: > 0 } pncConnection)
    builder.Configuration.AddInMemoryCollection(new Dictionary<string, string?> { ["Database:ConnectionString"] = pncConnection });
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
builder.Services.AddSingleton(catalog);
builder.Services.AddSingleton<PnC.Api.Security.FileLinkTokens>();   // #218: short-lived links to one file for a desktop application (Word)
builder.Services.AddHostedService<PnC.Api.Engine.SweepService>();   // W4: the scheduled sweep (PROCEDURE-ENGINE §4.1)
builder.Services.AddHostedService<PnC.Api.Engine.ComplianceService>();   // #171: the scheduled compliance pass (obligation rules over their candidates)

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
    h["Content-Security-Policy"] = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; manifest-src 'self'; frame-src 'self' blob:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'";
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
foreach (var v in app.Configuration.GetSection("Api:MaterialiseBeforePaging").Get<string[]>() ?? []) SqlSession.MaterialiseBeforePaging.Add(v);   // W7
DefinitionEndpoints.Map(app, catalog, map, authz);
FileEndpoints.Map(app, authz);                                           // W7: the file download (#144); #218 the file link
var fileLinks = app.Services.GetRequiredService<PnC.Api.Security.FileLinkTokens>();
app.Logger.LogInformation("File links: {Seconds} s, key {Source}", fileLinks.LifetimeSeconds, fileLinks.KeyFromConfig ? "from Files:LinkKey" : "drawn at startup (links outlive neither the process nor their lifetime)");
SettingsEndpoints.Map(app, authz);                                       // #168: the rendered settings text
RationaleEndpoints.Map(app, authz);                                      // #219: the structured rationale (one section per element)
ComplianceEndpoints.Map(app, catalog, authz);                            // #171: the obligation-rule evaluator (preview / effective)
ProcessEndpoints.Map(app, catalog, map, authz, connectionString);   // W4: the procedure engine   // W3: fixed routes before the generic {schema}/{procedure}
ApiEndpoints.Map(app, catalog, map, authz, app.Environment.EnvironmentName, connectionString);
// the React shell (#163): every /app/* route the browser asks for is the one page; the router picks the screen
app.MapFallbackToFile("app/{*path:nonfile}", "app/index.html");   // nonfile: the built assets stay with the static-file middleware

app.Run();
