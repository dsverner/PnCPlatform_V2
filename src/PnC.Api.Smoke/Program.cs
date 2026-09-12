using System.Data;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.SqlClient;

// docs/design/API.md §8 (W1) and IDENTITY.md §7 (W2) — the API gate.
//
//   PnC.Api.Smoke <api base url> [<connection string> | -] [--windows=Administrator|ReadOnly|Hydro]
//
// DEV mode (no --windows): bootstraps three users through the procedures as the SYSTEM actor — Administrator
// (Global), ReadOnly (Global), and a PCEngineer scoped to the Generation · Hydro division — and asserts identity
// with X-PnC-Dev-User. Windows mode: the process's own identity; checks that need another identity are SKIPped.
// Exit 1 on any failure, 2 on bad arguments. Soft deletes only.

if (args.Length < 1) { Console.Error.WriteLine("usage: PnC.Api.Smoke <api base url> [<connection string> | -] [--windows=Administrator|ReadOnly|Hydro]"); return 2; }
var baseUrl = args[0].TrimEnd('/');
var cs = args.Length > 1 && args[1] != "-" ? args[1] : null;
var windows = args.FirstOrDefault(a => a.StartsWith("--windows="))?["--windows=".Length..];
if (windows is not null and not ("Administrator" or "ReadOnly" or "Hydro")) { Console.Error.WriteLine("--windows must be Administrator, ReadOnly or Hydro"); return 2; }

var systemActor = new Guid("00000000-0000-0000-0000-000000000001");
var adminUpn = "smoke.admin@pnc.local"; var readUpn = "smoke.readonly@pnc.local"; var hydroUpn = "smoke.hydro@pnc.local";
const string HydroDivision = "Generation · Hydro", TransmissionDivision = "Transmission";
int passed = 0, failed = 0, skipped = 0;
void Check(bool ok, string what) { if (ok) { passed++; Console.WriteLine("  PASS " + what); } else { failed++; Console.WriteLine("  FAIL " + what); } }
void Skip(string what) { skipped++; Console.WriteLine("  SKIP " + what); }

// ---- identities
HttpClient Client(string? upn)
{
    var h = new HttpClientHandler { UseDefaultCredentials = windows is not null && upn is not null };
    var c = new HttpClient(h) { BaseAddress = new Uri(baseUrl + "/"), Timeout = TimeSpan.FromSeconds(60) };
    if (windows is null && upn is not null) c.DefaultRequestHeaders.Add("X-PnC-Dev-User", upn);
    return c;
}
HttpClient? admin = windows is null || windows == "Administrator" ? Client(windows is null ? adminUpn : "self") : null;
HttpClient? readOnly = windows is null || windows == "ReadOnly" ? Client(windows is null ? readUpn : "self") : null;
HttpClient? hydro = windows is null || windows == "Hydro" ? Client(windows is null ? hydroUpn : "self") : null;
var anonymous = Client(null);
var unknown = windows is null ? Client("nobody@pnc.local") : null;

// IIS itself answers an unauthenticated request with an HTML 401 in Windows mode; only JSON bodies are parsed.
JsonNode? ParseJson(string text) { if (text.Length == 0 || !(text.TrimStart().StartsWith('{') || text.TrimStart().StartsWith('['))) return null; try { return JsonNode.Parse(text); } catch (JsonException) { return null; } }
async Task<(HttpStatusCode status, JsonNode? body)> Get(HttpClient c, string path)
{
    var r = await c.GetAsync(path);
    return (r.StatusCode, ParseJson(await r.Content.ReadAsStringAsync()));
}
async Task<(HttpStatusCode status, JsonNode? body)> Post(HttpClient c, string path, object? body)
{
    var r = body is null ? await c.PostAsync(path, null) : await c.PostAsJsonAsync(path, body);
    return (r.StatusCode, ParseJson(await r.Content.ReadAsStringAsync()));
}
string? Code(JsonNode? b) => b?["code"]?.ToString();
List<string> Ids(JsonNode? b, string column = "EntityId") => (b?["rows"] as JsonArray)?.Select(r => r?[column]?.ToString()?.ToLowerInvariant() ?? "").ToList() ?? [];

// ---- DEV bootstrap: three users, through the procedures, as the SYSTEM actor (idempotent)
if (windows is null)
{
    if (cs is null) { Console.Error.WriteLine("DEV mode needs a connection string to bootstrap the smoke users."); return 2; }
    await using var con = new SqlConnection(cs);
    await con.OpenAsync();
    async Task<Guid?> DivisionId(string name)
    {
        await using var c = con.CreateCommand();
        c.CommandText = "SELECT TOP (1) EntityId FROM location.vNode WHERE NodeTypeCode = N'Division' AND Name = @n";
        c.Parameters.AddWithValue("@n", name);
        return await c.ExecuteScalarAsync() as Guid?;
    }
    async Task<Guid> Ensure(string upn, string role, string first, string scopeKind, Guid? scopeNode)
    {
        await using var find = con.CreateCommand();
        find.CommandText = "SELECT TOP (1) EntityId FROM security.vUser WHERE UserPrincipalName = @u AND IsEnabled = 1";
        find.Parameters.AddWithValue("@u", upn);
        var existing = await find.ExecuteScalarAsync();
        if (existing is Guid g) return g;

        await using var person = con.CreateCommand();
        person.CommandText = "EXEC personnel.Person_Add @FirstName=@f, @LastName=N'Smoke', @DisplayName=@d, @Email=@u, @IsSystemAccount=1, @ActorId=@a, @EntityId=@e OUTPUT";
        person.Parameters.AddWithValue("@f", first); person.Parameters.AddWithValue("@d", first + " Smoke"); person.Parameters.AddWithValue("@u", upn);
        person.Parameters.AddWithValue("@a", systemActor);
        var pe = person.Parameters.Add("@e", SqlDbType.UniqueIdentifier); pe.Direction = ParameterDirection.Output;
        await person.ExecuteNonQueryAsync();
        var personId = (Guid)pe.Value;

        await using var user = con.CreateCommand();
        user.CommandText = "EXEC security.User_Add @PersonEntityId=@p, @UserPrincipalName=@u, @ActorId=@a, @EntityId=@e OUTPUT";
        user.Parameters.AddWithValue("@p", personId); user.Parameters.AddWithValue("@u", upn); user.Parameters.AddWithValue("@a", systemActor);
        var ue = user.Parameters.Add("@e", SqlDbType.UniqueIdentifier); ue.Direction = ParameterDirection.Output;
        await user.ExecuteNonQueryAsync();
        var userId = (Guid)ue.Value;

        await using var grant = con.CreateCommand();
        grant.CommandText = "EXEC security.Grant_Add @GranteeKind=N'User', @GranteeEntityId=@g, @RoleCode=@r, @ScopeKind=@k, @ScopeNodeEntityId=@n, @GrantedByActorId=@a, @ActorId=@a, @EntityId=@e OUTPUT";
        grant.Parameters.AddWithValue("@g", userId); grant.Parameters.AddWithValue("@r", role); grant.Parameters.AddWithValue("@k", scopeKind);
        grant.Parameters.AddWithValue("@n", (object?)scopeNode ?? DBNull.Value); grant.Parameters.AddWithValue("@a", systemActor);
        var ge = grant.Parameters.Add("@e", SqlDbType.UniqueIdentifier); ge.Direction = ParameterDirection.Output;
        await grant.ExecuteNonQueryAsync();
        Console.WriteLine($"  bootstrapped {upn} as {role}/{scopeKind}");
        return userId;
    }
    await Ensure(adminUpn, "Administrator", "Admin", "Global", null);
    await Ensure(readUpn, "ReadOnly", "Reader", "Global", null);
    var hydroDiv = await DivisionId(HydroDivision);
    if (hydroDiv is null) { Console.Error.WriteLine($"division '{HydroDivision}' is not seeded on this database (Seed_location_Divisions.sql)"); return 2; }
    await Ensure(hydroUpn, "PCEngineer", "Hydro", "NodeSubtree", hydroDiv);
}

Console.WriteLine($"PnC.Api.Smoke against {baseUrl} ({(windows is null ? "DEV header identities" : "Windows identity as " + windows)})");

// ======================================================================= W1 — the surface
// 1. /health — the app ignores the identity, but in Windows mode IIS authenticates every caller first.
{
    var (st, b) = await Get(windows is null ? anonymous : (admin ?? readOnly ?? hydro)!, "health");
    Check(st == HttpStatusCode.OK && b?["database"]?.ToString() == "ok", $"/health database ok (release {b?["release"]}, environment {b?["environment"]})");
    Check(b?["release"] is not null, "/health reports a release");
}

// 2–3. /me
if (admin is not null)
{
    var (st, b) = await Get(admin, "api/v1/me");
    Check(st == HttpStatusCode.OK && b?["user"]?["userPrincipalName"] is not null, $"/me signed in as {b?["user"]?["userPrincipalName"]} (key: {b?["user"]?["identityKey"]})");
    var grants = b?["grants"] as JsonArray;
    Check(grants is { Count: > 0 } && grants.Any(g => g?["RoleCode"]?.ToString() == "Administrator"), "/me lists the Administrator grant");
}
else Skip("/me as Administrator (other identity)");
{
    var (st, b) = await Get(anonymous, "api/v1/me");
    Check(st == HttpStatusCode.Unauthorized && (windows is not null || Code(b) == "unauthenticated"), windows is null ? "/me with no identity → 401 unauthenticated" : "/me with no identity → 401 (IIS challenge)");
}
if (unknown is not null)
{
    var (st, b) = await Get(unknown, "api/v1/me");
    Check(st == HttpStatusCode.Unauthorized && Code(b) == "unauthenticated", "/me with an unknown identity → 401 (directory presence grants nothing)");
}
else Skip("/me with an unknown identity (needs the DEV header)");

// 4. /catalog
var any = (admin ?? readOnly ?? hydro)!;
{
    var (st, b) = await Get(any, "api/v1/catalog");
    var schemas = (b?["schemas"] as JsonArray)?.Count ?? 0;
    var procs = (b?["procedures"] as JsonArray)?.Count ?? 0;
    var views = (b?["views"] as JsonArray)?.Count ?? 0;
    Check(st == HttpStatusCode.OK && schemas >= 20 && procs > 100 && views > 100, $"/catalog lists {schemas} schemas, {procs} procedures, {views} views");
    var vAsset = (b?["views"] as JsonArray)?.FirstOrDefault(v => v?["name"]?.ToString() == "vAsset" && v?["schema"]?.ToString() == "asset");
    Check(vAsset?["scope"]?.ToString() == "EntityId as Asset", $"/catalog reports asset.vAsset scoped by EntityId as Asset ({vAsset?["scope"]})");
}

// 5–6. a view read
if (readOnly is not null)
{
    var (st, b) = await Get(readOnly, "api/v1/asset/vAsset?take=5");
    Check(st == HttpStatusCode.OK && b?["rows"] is JsonArray, $"GET asset/vAsset as ReadOnly → 200 ({(b?["rows"] as JsonArray)?.Count} rows)");
    var (st2, b2) = await Get(readOnly, "api/v1/asset/vAsset?NoSuchColumn=1");
    Check(st2 == HttpStatusCode.BadRequest && Code(b2) == "unknown_column", "GET asset/vAsset?NoSuchColumn=1 → 400 unknown_column");
}
else Skip("view read as ReadOnly (other identity)");

// 7. a write refused as ReadOnly, allowed as Administrator
var stamp = DateTime.UtcNow.ToString("yyyyMMddHHmmss");
var created = new List<(string proc, string idParam, Guid id)>();
var personBody = new { FirstName = "Smoke", LastName = "W1-" + stamp, DisplayName = "Smoke W1 " + stamp, IsSystemAccount = true };
if (readOnly is not null)
{
    var (st, b) = await Post(readOnly, "api/v1/personnel/Person_Add", personBody);
    Check(st == HttpStatusCode.Forbidden && Code(b) == "forbidden", "POST personnel/Person_Add as ReadOnly → 403 forbidden");
}
else Skip("write as ReadOnly (other identity)");
if (admin is not null)
{
    var (st, b) = await Post(admin, "api/v1/personnel/Person_Add", personBody);
    var id = b?["EntityId"]?.ToString();
    Check(st == HttpStatusCode.OK && Guid.TryParse(id, out _), $"POST personnel/Person_Add as Administrator → 200 with EntityId {id}");
    if (Guid.TryParse(id, out var pid2)) created.Add(("personnel.Person_SoftDelete", "EntityId", pid2));

    // 8–9. shape errors
    var (st3, b3) = await Post(admin, "api/v1/personnel/Person_Add", new { FirstName = "only" });
    Check(st3 == HttpStatusCode.BadRequest && Code(b3) == "missing_parameter", "POST personnel/Person_Add with a missing required parameter → 400 missing_parameter");
    var (st4, b4) = await Post(admin, "api/v1/asset/NoSuchProcedure", new { });
    Check(st4 == HttpStatusCode.NotFound && Code(b4) == "unknown_procedure", "POST asset/NoSuchProcedure → 404 unknown_procedure");
    var (st5, b5) = await Post(admin, "api/v1/personnel/ResolveActor", new { });
    Check(st5 == HttpStatusCode.NotFound && Code(b5) == "not_callable", "POST personnel/ResolveActor → 404 not_callable");
    var (st6, b6) = await Post(admin, "api/v1/personnel/Person_Add", new { FirstName = "x", LastName = "y", DisplayName = "z", ActorId = systemActor });
    Check(st6 == HttpStatusCode.BadRequest && Code(b6) == "unknown_parameter", "ActorId in a body is refused (attribution is the database's)");
    var form = await admin.PostAsync("api/v1/personnel/Person_Add", new FormUrlEncodedContent(new Dictionary<string, string> { ["FirstName"] = "x" }));
    Check(form.StatusCode == HttpStatusCode.UnsupportedMediaType, "a non-JSON POST (a cross-site form) -> 415 unsupported_media_type");

    // 10. a THROW surfaces as 409 rule in the procedure's words
    var (st7, b7) = await Post(admin, "api/v1/config/ApproveDefinitionVersion", new { VersionRowId = Guid.NewGuid() });
    Check(st7 == HttpStatusCode.Conflict && Code(b7) == "rule" && b7?["sqlNumber"]?.GetValue<int>() == 50030,
        $"a procedure's THROW → 409 rule with its own words ({b7?["detail"]})");
}
else Skip("writes as Administrator (other identity)");

// ======================================================================= W2 — roles and scopes (IDENTITY.md §7)
// The fixture: under two divisions, a station → building → panel, and one asset placed in each panel. Built through
// the API as Administrator; soft-deleted at the end. Needs an asset type that is not a device (devices need positions).
Guid? hydroStation = null, hydroBuilding = null, hydroPanel = null, hydroAsset = null, txStation = null, txBuilding = null, txPanel = null, txAsset = null;
var typeCode = "SMOKEW2";
if (admin is not null)
{
    var (dst, dsb) = await Get(admin, "api/v1/location/vNode?NodeTypeCode=Division&take=20");
    var divisions = (dsb?["rows"] as JsonArray)?.ToDictionary(r => r?["Name"]?.ToString() ?? "", r => Guid.Parse(r?["EntityId"]?.ToString() ?? Guid.Empty.ToString())) ?? new();
    Check(dst == HttpStatusCode.OK && divisions.ContainsKey(HydroDivision) && divisions.ContainsKey(TransmissionDivision), $"the seeded divisions are listed ({divisions.Count}: {string.Join(", ", divisions.Keys)})");
    if (divisions.ContainsKey(HydroDivision) && divisions.ContainsKey(TransmissionDivision))
    {
        var (tst, tsb) = await Post(admin, "api/v1/ref/AssetType_Upsert", new { AssetTypeCode = typeCode, Name = "smoke W2 non-device type", AssetClassCode = "Secondary", IsDevice = false });
        Check(tst == HttpStatusCode.OK, $"ref/AssetType_Upsert {typeCode} → {(int)tst} {Code(tsb)}");
        async Task<Guid?> Node(string type, Guid parent, string name)
        {
            var (s, b) = await Post(admin, "api/v1/location/AddNode", new { NodeTypeCode = type, ParentEntityId = parent, Name = name });
            var id = b?["EntityId"]?.ToString();
            if (s != HttpStatusCode.OK || !Guid.TryParse(id, out var g)) { Check(false, $"AddNode {type} '{name}' → {(int)s} {Code(b)} {b?["detail"]}"); return null; }
            return g;
        }
        async Task<Guid?> Asset(Guid panel, string name)
        {
            var (s, b) = await Post(admin, "api/v1/asset/Asset_Add", new { AssetTypeCode = typeCode, Name = name, Status = "InService" });
            var id = b?["EntityId"]?.ToString();
            if (s != HttpStatusCode.OK || !Guid.TryParse(id, out var g)) { Check(false, $"Asset_Add '{name}' → {(int)s} {Code(b)} {b?["detail"]}"); return null; }
            var (ps, pb) = await Post(admin, "api/v1/asset/PlaceAsset", new { AssetEntityId = g, NodeEntityId = panel, PlacementKind = "Installed" });
            if (ps != HttpStatusCode.OK) { Check(false, $"PlaceAsset '{name}' → {(int)ps} {Code(pb)} {pb?["detail"]}"); return g; }
            return g;
        }
        hydroStation = await Node("Station", divisions[HydroDivision], $"Smoke W2 Hydro station {stamp}");
        if (hydroStation is Guid hs) hydroBuilding = await Node("Building", hs, "Smoke W2 Hydro building");
        if (hydroBuilding is Guid hb) hydroPanel = await Node("Panel", hb, "Smoke W2 Hydro panel");
        if (hydroPanel is Guid hp) hydroAsset = await Asset(hp, $"Smoke W2 Hydro asset {stamp}");
        txStation = await Node("Station", divisions[TransmissionDivision], $"Smoke W2 Transmission station {stamp}");
        if (txStation is Guid ts) txBuilding = await Node("Building", ts, "Smoke W2 Transmission building");
        if (txBuilding is Guid tb) txPanel = await Node("Panel", tb, "Smoke W2 Transmission panel");
        if (txPanel is Guid tp) txAsset = await Asset(tp, $"Smoke W2 Transmission asset {stamp}");
        Check(hydroAsset is not null && txAsset is not null, "fixture: one asset placed under each of two divisions");
    }
}
else Skip("W2 fixture (needs the Administrator identity)");

var fixtureOk = hydroAsset is not null && txAsset is not null && hydroStation is not null && txStation is not null;
if (hydro is not null && fixtureOk)
{
    var (ms, mb) = await Get(hydro, "api/v1/me");
    var g = (mb?["grants"] as JsonArray)?.FirstOrDefault();
    Check(ms == HttpStatusCode.OK && g?["RoleCode"]?.ToString() == "PCEngineer" && g?["ScopeKind"]?.ToString() == "NodeSubtree" && g?["ScopeNodeName"]?.ToString() == HydroDivision,
        $"/me as the Hydro engineer: PCEngineer, NodeSubtree on {g?["ScopeNodeName"]}");

    var (ast, ab) = await Get(hydro, "api/v1/asset/vAsset?take=500");
    var assetIds = Ids(ab);
    Check(ast == HttpStatusCode.OK && assetIds.Contains(hydroAsset.ToString()!.ToLowerInvariant()) && !assetIds.Contains(txAsset.ToString()!.ToLowerInvariant()),
        $"as Hydro, asset/vAsset lists the Hydro asset and not the Transmission asset ({assetIds.Count} rows)");
    var (nst, nb) = await Get(hydro, "api/v1/location/vNode?take=500");
    var nodeIds = Ids(nb);
    Check(nst == HttpStatusCode.OK && nodeIds.Contains(hydroStation.ToString()!.ToLowerInvariant()) && !nodeIds.Contains(txStation.ToString()!.ToLowerInvariant()),
        $"as Hydro, location/vNode lists the Hydro station and not the Transmission station ({nodeIds.Count} rows)");
    var (sst, sb) = await Get(hydro, "api/v1/location/vNode?NodeTypeCode=Station&take=500");
    var stationRows = (sb?["rows"] as JsonArray)?.Select(r => r?["Name"]?.ToString() ?? "").ToList() ?? [];
    Check(sst == HttpStatusCode.OK && stationRows.All(n => !n.Contains("Transmission")), $"as Hydro, no station row outside scope is visible ({stationRows.Count} stations)");
    var (ost, ob) = await Get(hydro, $"api/v1/asset/vAsset?EntityId={txAsset}");
    Check(ost == HttpStatusCode.Forbidden && Code(ob) == "forbidden", "as Hydro, a single read of the Transmission asset → 403 forbidden");
    var (pst, pb) = await Get(hydro, "api/v1/asset/vPlacement?take=500");
    var placedAssets = Ids(pb, "AssetEntityId");
    Check(pst == HttpStatusCode.OK && placedAssets.Contains(hydroAsset.ToString()!.ToLowerInvariant()) && !placedAssets.Contains(txAsset.ToString()!.ToLowerInvariant()),
        $"as Hydro, asset/vPlacement (scoped by its AssetEntityId column) shows only the Hydro placement ({placedAssets.Count} rows)");

    // writes: in scope allowed, outside scope refused
    var (w1s, w1b) = await Post(hydro, "api/v1/location/AddNode", new { NodeTypeCode = "Room", ParentEntityId = hydroBuilding, Name = "Smoke W2 Hydro room" });
    var roomId = w1b?["EntityId"]?.ToString();
    Check(w1s == HttpStatusCode.OK && Guid.TryParse(roomId, out _), $"as Hydro, AddNode under the Hydro building → 200 ({Code(w1b)} {w1b?["detail"]})");
    if (Guid.TryParse(roomId, out var rid)) created.Add(("location.Node_SoftDelete", "EntityId", rid));
    var (w2s, w2b) = await Post(hydro, "api/v1/location/AddNode", new { NodeTypeCode = "Room", ParentEntityId = txBuilding, Name = "Smoke W2 stray room" });
    Check(w2s == HttpStatusCode.Forbidden && Code(w2b) == "forbidden", "as Hydro, AddNode under the Transmission building → 403 forbidden");
}
else Skip("scope checks as the Hydro engineer (needs that identity and the fixture)");

if (admin is not null && fixtureOk)
{
    var (ast, ab) = await Get(admin, "api/v1/asset/vAsset?take=500");
    var ids = Ids(ab);
    Check(ast == HttpStatusCode.OK && ids.Contains(hydroAsset.ToString()!.ToLowerInvariant()) && ids.Contains(txAsset.ToString()!.ToLowerInvariant()), "as Administrator (Global), both assets are listed");
}
if (readOnly is not null && fixtureOk)
{
    var (ast, ab) = await Get(readOnly, "api/v1/asset/vAsset?take=500");
    var ids = Ids(ab);
    Check(ast == HttpStatusCode.OK && ids.Contains(hydroAsset.ToString()!.ToLowerInvariant()) && ids.Contains(txAsset.ToString()!.ToLowerInvariant()), "as ReadOnly (Global), both assets are listed");
}
if (admin is not null || readOnly is not null)
{
    // Grant.Read is the Administrator's and ReadOnly's (IDENTITY.md §3); the engineer roles do not hold it.
    var (rs, rb) = await Get((admin ?? readOnly)!, "api/v1/security/vRole?take=50");
    var roles = (rb?["rows"] as JsonArray)?.Select(r => r?["RoleCode"]?.ToString()).OrderBy(x => x).ToList() ?? [];
    var expected = new[] { "Administrator", "Assignee", "PCApprover", "PCEngineer", "PCTechnician", "PlacementOverride", "ReadOnly" }.OrderBy(x => x).ToList();
    Check(rs == HttpStatusCode.OK && roles.SequenceEqual(expected), $"security/vRole: exactly the active roles of IDENTITY.md §3 ({string.Join(", ", roles)})");
}
if (hydro is not null)
{
    // A PCEngineer holds no Grant.Read: the role list is refused, not filtered to empty (observed on VM02 2026-09-12 as pnc-gate-hydro).
    var (rs, rb) = await Get(hydro, "api/v1/security/vRole?take=50");
    Check(rs == HttpStatusCode.Forbidden && Code(rb) == "forbidden", $"security/vRole as the Hydro engineer → 403 forbidden (no Grant.Read) [{(int)rs} {Code(rb)}]");
}

// 7b. the refusals were logged
if (cs is not null && windows is null)
{
    await using var con = new SqlConnection(cs);
    await con.OpenAsync();
    async Task<int> Refusals(string upn)
    {
        await using var cmd = con.CreateCommand();
        cmd.CommandText = """
            SELECT COUNT(*) FROM audit.vActionLog l JOIN personnel.vActor a ON a.ActorId = l.ActorId
            JOIN security.vUser u ON u.PersonEntityId = a.PersonEntityId
            WHERE l.ActionKindCode = N'AccessRefused' AND u.UserPrincipalName = @u AND l.OccurredAt > DATEADD(minute, -5, SYSDATETIMEOFFSET())
            """;
        cmd.Parameters.AddWithValue("@u", upn);
        return Convert.ToInt32(await cmd.ExecuteScalarAsync());
    }
    Check(await Refusals(readUpn) > 0, $"audit.vActionLog holds an AccessRefused row for {readUpn}");
    if (fixtureOk) Check(await Refusals(hydroUpn) >= 2, $"audit.vActionLog holds the Hydro engineer's two refusals (single read, out-of-scope write)");
}
else Skip("AccessRefused in audit.vActionLog (needs a connection string and the DEV identities)");

// 11. cleanup — soft deletes only, through the API as Administrator, children before parents
if (admin is not null)
{
    foreach (var (asset, panel) in new[] { (hydroAsset, hydroPanel), (txAsset, txPanel) })
        if (asset is Guid a)
        {
            var (ps, pb) = await Get(admin, $"api/v1/asset/vPlacement?AssetEntityId={a}");
            foreach (var pl in (pb?["rows"] as JsonArray) ?? new JsonArray())
                if (Guid.TryParse(pl?["EntityId"]?.ToString(), out var plid)) created.Add(("asset.Placement_SoftDelete", "EntityId", plid));
            created.Add(("asset.Asset_SoftDelete", "EntityId", a));
        }
    foreach (var n in new[] { hydroPanel, hydroBuilding, hydroStation, txPanel, txBuilding, txStation })
        if (n is Guid nid) created.Add(("location.Node_SoftDelete", "EntityId", nid));
    foreach (var (proc, idParam, id) in created)
    {
        var parts = proc.Split('.');
        var (st, b) = await Post(admin, $"api/v1/{parts[0]}/{parts[1]}", new Dictionary<string, object> { [idParam] = id });
        Check(st == HttpStatusCode.OK, $"cleanup {proc} {id} → {(int)st} {Code(b)} {b?["detail"]}");
    }
    if (fixtureOk) { var (ts, tb) = await Post(admin, "api/v1/ref/AssetType_Deactivate", new { AssetTypeCode = typeCode }); Check(ts == HttpStatusCode.OK, $"cleanup ref/AssetType_Deactivate {typeCode} → {(int)ts} {Code(tb)}"); }
}

Console.WriteLine($"SMOKE {(failed == 0 ? "PASS" : "FAIL")}: {passed} passed, {failed} failed, {skipped} skipped");
return failed == 0 ? 0 : 1;
