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
if (windows is not null and not ("Administrator" or "ReadOnly" or "Hydro" or "Approver" or "Technician")) { Console.Error.WriteLine("--windows must be Administrator, ReadOnly, Hydro, Approver or Technician"); return 2; }

var systemActor = new Guid("00000000-0000-0000-0000-000000000001");
var adminUpn = "smoke.admin@pnc.local"; var readUpn = "smoke.readonly@pnc.local"; var hydroUpn = "smoke.hydro@pnc.local"; var approverUpn = "smoke.approver@pnc.local"; var techUpn = "smoke.tech@pnc.local";
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
// W3: a second Administrator, so approval by someone other than the author can be observed (Author/Approve segregation)
HttpClient? approver = windows is null || windows == "Approver" ? Client(windows is null ? approverUpn : "self") : null;
// W4: a technician (PCTechnician, Global) for the field steps
HttpClient? tech = windows is null || windows == "Technician" ? Client(windows is null ? techUpn : "self") : null;
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
    await Ensure(approverUpn, "Administrator", "Approver", "Global", null);
    await Ensure(techUpn, "PCTechnician", "Tech", "Global", null);
    var hydroDiv = await DivisionId(HydroDivision);
    if (hydroDiv is null) { Console.Error.WriteLine($"division '{HydroDivision}' is not seeded on this database (Seed_location_Divisions.sql)"); return 2; }
    await Ensure(hydroUpn, "PCEngineer", "Hydro", "NodeSubtree", hydroDiv);
}

Console.WriteLine($"PnC.Api.Smoke against {baseUrl} ({(windows is null ? "DEV header identities" : "Windows identity as " + windows)})");

// ======================================================================= W1 — the surface
// 1. /health — the app ignores the identity, but in Windows mode IIS authenticates every caller first.
{
    var (st, b) = await Get(windows is null ? anonymous : (admin ?? approver ?? readOnly ?? hydro)!, "health");
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
var any = (admin ?? approver ?? readOnly ?? hydro)!;
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

// ======================================================================= W3 — definitions and the process schema
// The three example documents of PROCEDURE-ENGINE.md load through the API, are approved by a second person, and project.
// Idempotent: a document already stored (same canonical hash) answers existing=true; approval of an already Effective
// version is refused by the database (50031 "Only Draft versions can be approved"), which the run treats as done.
string Example(string name)
{
    using var st = typeof(Program).Assembly.GetManifestResourceStream("examples/" + name) ?? throw new InvalidOperationException("missing embedded " + name);
    using var rd = new StreamReader(st); return rd.ReadToEnd();
}
string Short(JsonNode? b) { var d = b?["detail"]?.ToString() ?? ""; return d.Length > 80 ? d[..80] : d; }
bool AlreadyApproved(JsonNode? b) => b?["sqlNumber"]?.GetValue<int>() == 50031;
if (admin is not null)
{
    async Task<(HttpStatusCode, JsonNode?)> Load(string file) =>
        await Post(admin, "api/v1/definitions/documents", new { document = JsonNode.Parse(Example(file)), changeNote = "W3 gate" });
    async Task<(HttpStatusCode, JsonNode?)> Approve(HttpClient who, string rowId) => await Post(who, $"api/v1/definitions/documents/{rowId}/approve", new { });
    string Errors(JsonNode? b) => b?["errors"] is JsonArray ea ? string.Join(" | ", ea.Select(x => x?["path"] + ": " + x?["message"])) : "";

    // order: the lifecycle workflow (the procedure's advances need it Effective); the procedure (the request workflow names it); the request workflow
    var (ls, lb) = await Load("settings-lifecycle.workflow.json");
    Check(ls == HttpStatusCode.OK && lb?["versionRowId"] is not null, $"load SETTINGS_LIFECYCLE workflow → {(int)ls} {Code(lb)} {Errors(lb)} (version {lb?["versionNumber"]}, existing {lb?["existing"]})");
    string? lifecycleRow = lb?["versionRowId"]?.ToString();
    if (lifecycleRow is not null)
    {
        var (as1, ab1) = await Approve(admin, lifecycleRow);
        Check(as1 == HttpStatusCode.Conflict, $"approve SETTINGS_LIFECYCLE as its author → 409 ({Short(ab1)})");
        if (approver is not null)
        {
            var (as2, ab2) = await Approve(approver, lifecycleRow);
            Check(as2 == HttpStatusCode.OK || AlreadyApproved(ab2), $"approve SETTINGS_LIFECYCLE as the second Administrator → {(int)as2} {Code(ab2)}");
        }
        else Skip("approve SETTINGS_LIFECYCLE (needs the Approver identity)");
    }

    var (ps, pb) = await Load("settings-change.procedure.json");
    Check(ps == HttpStatusCode.OK && pb?["versionRowId"] is not null, $"load SETTINGS_CHANGE procedure → {(int)ps} {Code(pb)} {Errors(pb)} {Short(pb)} (version {pb?["versionNumber"]}, existing {pb?["existing"]})");
    string? procRow = pb?["versionRowId"]?.ToString();

    var (rs, rb) = await Load("settings-change.workflow.json");
    Check(rs == HttpStatusCode.OK && rb?["versionRowId"] is not null, $"load SETTINGS_CHANGE_REQUEST workflow → {(int)rs} {Code(rb)} {Errors(rb)} {Short(rb)} (version {rb?["versionNumber"]}, existing {rb?["existing"]})");
    if (rb?["versionRowId"]?.ToString() is { } reqRow && approver is not null)
    {
        var (as3, ab3) = await Approve(approver, reqRow);
        Check(as3 == HttpStatusCode.OK || AlreadyApproved(ab3), $"approve SETTINGS_CHANGE_REQUEST as the second Administrator → {(int)as3} {Code(ab3)}");
    }

    if (procRow is not null)
    {
        var (as4, ab4) = await Approve(admin, procRow);
        Check(as4 == HttpStatusCode.Conflict, $"approve SETTINGS_CHANGE as its author → 409 ({Short(ab4)})");
        if (approver is not null)
        {
            var (as5, ab5) = await Approve(approver, procRow);
            Check(as5 == HttpStatusCode.OK || AlreadyApproved(ab5), $"approve SETTINGS_CHANGE as the second Administrator → {(int)as5} {Code(ab5)} (projected {ab5?["projectedSteps"]})");
        }
        else Skip("approve SETTINGS_CHANGE (needs the Approver identity)");
        // the projection — the design verification's counts: 14 steps, 4 advances, 1 call
        var (ss, sb) = await Get(admin, $"api/v1/process/vProcedureStep?DefinitionVersionRowId={procRow}&take=100");
        var steps = (sb?["rows"] as JsonArray) ?? new JsonArray();
        // FR-3.1's fourteen numbered steps are fifteen step blocks plus one call: [4] has two variants (BUILD_SETTINGS /
        // RECORD_SETTINGS, the electromechanical fork), RESOLVE_DIFFERENCE is unnumbered, and [14] is the call block.
        Check(ss == HttpStatusCode.OK && steps.Count == 15, $"process/vProcedureStep holds 15 rows for SETTINGS_CHANGE — the 14 FR-3.1 steps as 15 step blocks + 1 call ({steps.Count})");
        var numbered = steps.Select(r => r?["Title"]?.ToString() ?? "").Where(t => t.StartsWith('[')).Select(t => t[1..t.IndexOf(']')]).Distinct().Count();
        Check(numbered == 13 && steps.Any(r => r?["StepId"]?.ToString() == "RESOLVE_DIFFERENCE"), $"the step titles carry FR-3.1 numbers [1]–[13] ({numbered} distinct; [14] is the call) plus the unnumbered RESOLVE_DIFFERENCE");
        var advancing = steps.Count(r => r?["AdvancesTransition"] is not null);
        Check(advancing == 6, $"6 steps advance the lifecycle workflow: CHECK, APPROVE, ISSUE, APPLY, RETURN_TO_SERVICE, BASELINE ({advancing})");
        Check(steps.Count(r => r?["RequiresWitness"]?.GetValue<bool>() == true) == 1 && steps.Any(r => r?["StepId"]?.ToString() == "RETURN_TO_SERVICE" && r?["RequiresWitness"]?.GetValue<bool>() == true), "RETURN_TO_SERVICE is the one witnessed step");
        var (cs1, cb1) = await Get(admin, $"api/v1/process/vProcedureCall?DefinitionVersionRowId={procRow}");
        var calls = (cb1?["rows"] as JsonArray) ?? new JsonArray();
        Check(cs1 == HttpStatusCode.OK && calls.Count == 1 && calls[0]?["CalleeKey"]?.ToString() == "DRAWING_REVISION", $"process/vProcedureCall: 1 call, to DRAWING_REVISION ({calls.Count})");
        var (fs, fb) = await Get(admin, $"api/v1/process/vProcedureFactUse?DefinitionVersionRowId={procRow}&take=200");
        var facts = ((fb?["rows"] as JsonArray) ?? new JsonArray()).Select(r => r?["FactName"]?.ToString()).Distinct().OrderBy(x => x).ToList();
        Check(fs == HttpStatusCode.OK && facts.Contains("device.technology") && facts.Contains("step.outcome") && facts.Contains("work.outage_required") && facts.Contains("person.training_current"),
              $"process/vProcedureFactUse indexes the facts the document reads ({string.Join(", ", facts)})");
        var (rls, rlb) = await Get(admin, "api/v1/process/vProcedureStepRole?RoleCode=PCTechnician&take=100");
        Check(rls == HttpStatusCode.OK && ((rlb?["rows"] as JsonArray) ?? new JsonArray()).Any(r => r?["RequiresAst"] is not null), "process/vProcedureStepRole carries the technician's competency expression as canonical AST");
    }

    // a document the grammar refuses is refused with its path; one the structure refuses, in the rule's words
    var bad = (JsonObject)JsonNode.Parse(Example("settings-change.procedure.json"))!;
    bad["key"] = "SMOKE_BAD"; ((JsonObject)bad["roles"]!["technician"]!)["requires"] = "person.training_current = 'yes'";
    var (bs, bb) = await Post(admin, "api/v1/definitions/documents", new { document = bad });
    Check(bs == HttpStatusCode.BadRequest && Code(bb) == "document_invalid" && (bb?["errors"] as JsonArray)?.Any(e => e?["path"]?.ToString() == "$.roles.technician.requires") == true,
          $"a document whose expression fails the type check → 400 document_invalid at $.roles.technician.requires ({(bb?["errors"] as JsonArray)?[0]?["message"]})");
    var bad2 = (JsonObject)JsonNode.Parse(Example("settings-change.procedure.json"))!;
    bad2["key"] = "SMOKE_BAD2"; ((JsonObject)((JsonArray)bad2["body"]!["items"]!)[1]!)["id"] = "REQUEST";
    var (b2s, b2b) = await Post(admin, "api/v1/definitions/documents", new { document = bad2 });
    Check(b2s == HttpStatusCode.Conflict && b2b?["sqlNumber"]?.GetValue<int>() == 50121, $"a document with a duplicate block id → 409 in the rule's words ({Short(b2b)})");

    // the live expression check
    var (fcs, fcb) = await Post(admin, "api/v1/formula/check", new { expression = "value >= 0", env = new { value = new { type = "num" } } });
    Check(fcs == HttpStatusCode.OK && fcb?["ok"]?.GetValue<bool>() == true && fcb?["type"]?.ToString() == "bool", $"formula/check: value >= 0 → {fcb?["type"]}");
    var (fes, feb) = await Post(admin, "api/v1/formula/check", new { expression = "device.no_such_fact = 1" });
    Check(fes == HttpStatusCode.OK && feb?["ok"]?.GetValue<bool>() == false && feb?["code"]?.ToString() == "unknown_fact", $"formula/check: an unknown fact → {feb?["code"]}");
}
else Skip("W3 definitions (needs the Administrator identity)");
// A second person's approval, observable in every mode: the Administrator run authors a small distinct document (a
// fresh Draft each run, its description carrying the run instant); the Approver run — a different Windows identity on
// VM02, a different DEV-header user on the laptop — approves that key's latest Draft. Together the two runs show
// Author ≠ Approver on the Windows path, which the example documents cannot once they are Effective.
const string GateKey = "W3_GATE_APPROVAL";
if (admin is not null)
{
    var gateDoc = new
    {
        g = 1, kind = "procedure", key = GateKey, name = "W3 gate: authored by one Administrator, approved by another", subjectKind = "WorkRequest",
        description = $"authored {DateTimeOffset.UtcNow:O} by the gate's Administrator run; a fresh Draft each run",
        roles = new { eng = new { role = "PCEngineer" } },
        body = new { block = "sequence", id = "MAIN", items = new object[] {
            new { block = "step", id = "ONE", title = "[1] one", role = "eng", record = new { kind = "Finding" } },
            new { block = "step", id = "TWO", title = "[2] two", role = "eng", record = new { kind = "Finding" }, precondition = "step.outcome[id='ONE'] = 'Done'" } } }
    };
    var (gs, gb) = await Post(admin, "api/v1/definitions/documents", new { document = gateDoc, changeNote = "W3 gate" });
    Check(gs == HttpStatusCode.OK && gb?["existing"]?.GetValue<bool>() == false, $"author a fresh {GateKey} Draft as the Administrator → {(int)gs} (version {gb?["versionNumber"]})");
    if (gb?["versionRowId"]?.ToString() is { } gRow)
    {
        var (gas, gab) = await Post(admin, $"api/v1/definitions/documents/{gRow}/approve", new { });
        Check(gas == HttpStatusCode.Conflict && (gab?["detail"]?.ToString().Contains("segregation", StringComparison.OrdinalIgnoreCase) ?? false), $"the author cannot approve it → 409 segregation");
    }
}
if (approver is not null)
{
    // the latest Draft of the gate key, whoever authored it (the Administrator run, moments ago)
    var (dfs, dfb) = await Get(approver, $"api/v1/config/vDefinition?DefinitionKey={GateKey}");
    var defId = (dfb?["rows"] as JsonArray)?.FirstOrDefault()?["EntityId"]?.ToString();
    var (ds, db) = await Get(approver, $"api/v1/config/vDefinitionVersion?DefinitionEntityId={defId}&Status=Draft&take=100");
    var draft = (db?["rows"] as JsonArray)?.OrderByDescending(r => r?["VersionNumber"]?.GetValue<int>() ?? 0).FirstOrDefault();
    Check(ds == HttpStatusCode.OK && draft is not null, $"a {GateKey} Draft authored by the Administrator run is waiting ({draft?["VersionNumber"]})");
    if (draft?["RowId"]?.ToString() is { } dRow)
    {
        var (aps, apb) = await Post(approver, $"api/v1/definitions/documents/{dRow}/approve", new { });
        Check(aps == HttpStatusCode.OK && apb?["projectedSteps"]?.GetValue<int>() == 2, $"approve it as the second Administrator → {(int)aps} {Code(apb)} (projected {apb?["projectedSteps"]})");
        var (vs, vb) = await Get(approver, $"api/v1/config/vDefinitionVersion?RowId={dRow}");
        var row = (vb?["rows"] as JsonArray)?.FirstOrDefault();
        Check(row?["Status"]?.ToString() == "Effective" && row?["ApprovedBy"]?.ToString() != row?["CreatedBy"]?.ToString(), $"the version is Effective with ApprovedBy ≠ CreatedBy (author {row?["CreatedBy"]?.ToString()?[..8]}…, approver {row?["ApprovedBy"]?.ToString()?[..8]}…)");
    }
}
if (readOnly is not null)
{
    var (rs2, rb2) = await Post(readOnly, "api/v1/definitions/documents", new { document = JsonNode.Parse(Example("settings-lifecycle.workflow.json")) });
    Check(rs2 == HttpStatusCode.Forbidden && Code(rb2) == "forbidden", "load a document as ReadOnly → 403 forbidden");
}

// ======================================================================= W4 — the interpreter (PHASE-1-WORKFLOW W4 gate)
// One SETTINGS_CHANGE run end to end over three fixture devices (SEL-421, CGE BDD15B, Westinghouse CYL): every step
// commits; the package walks Calculated → … → InService; the CYL readback difference ends its member Superseded; the
// outage hold releases on the sweep; one step commits as deferred with two actors. Then a v2 of SETTINGS_CHANGE is
// approved and a second, half-run instance appears on the migration list while the first is untouched.
// Needs every DEV identity (admin, approver, hydro, tech); in Windows mode the run is skipped except as Administrator,
// where the fixture alone is asserted (the run needs four persons in one process).
if (admin is not null && approver is not null && hydro is not null && tech is not null)
{
    var tag = "W4_" + DateTime.UtcNow.ToString("yyyyMMddHHmmss");
    var bdd = new Guid("A0000000-0000-4000-8000-0000000BDD15"); var cyl = new Guid("A0000000-0000-4000-8000-000000000CE1"); var sel = new Guid("A0000000-0000-4000-8000-000000000421");
    var fwBdd = new Guid("A0000000-0000-4000-8000-00000BDD15F1"); var fwCyl = new Guid("A0000000-0000-4000-8000-000000CE1F01"); var fwSel = new Guid("A0000000-0000-4000-8000-000000421F01");
    string B64(string s) => Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(s));
    object File(string name, string mime, string text, string kind) => new { name, mimeType = mime, kind, contentBase64 = B64(text) };
    Guid? Id(JsonNode? b, string key = "EntityId") => Guid.TryParse(b?[key]?.ToString(), out var g) ? g : null;
    var w4ok = true;
    void Must(bool ok, string what) { Check(ok, what); if (!ok) w4ok = false; }

    // ---- fixture: nodes under the Hydro division, three relays with their firmware, a scheme, a work type, a work request, the technician's training
    var (dvs, dvb) = await Get(admin, $"api/v1/location/vNode?NodeTypeCode=Division&Name={Uri.EscapeDataString(HydroDivision)}");
    var division = Id((dvb?["rows"] as JsonArray)?.FirstOrDefault());
    Must(division is not null, $"fixture: the Hydro division exists ({division})");
    async Task<Guid?> Node(string type, Guid? parent, string name, string? subtype = null)
    {
        var (s, b) = await Post(admin, "api/v1/location/AddNode", new { NodeTypeCode = type, ParentEntityId = parent, Name = name, SubtypeCode = subtype });
        if (s != HttpStatusCode.OK) { Must(false, $"fixture: AddNode {type} '{name}' → {(int)s} {Code(b)} {b?["detail"]}"); return null; }
        return Id(b);
    }
    var station = await Node("Station", division, $"{tag} station");
    var building = await Node("Building", station, $"{tag} control building");
    var panel = await Node("Panel", building, $"{tag} panel 1");
    var positions = new List<Guid?>(); foreach (var i in new[] { 1, 2, 3 }) positions.Add(await Node("DevicePosition", panel, $"{tag} position {i}"));
    async Task<Guid?> Relay(string name, Guid model, Guid firmware, Guid? position)
    {
        var (s, b) = await Post(admin, "api/v1/asset/Asset_Add", new { AssetTypeCode = "ProtectiveRelay", Name = name, ModelId = model, Status = "InService" });
        if (s != HttpStatusCode.OK) { Must(false, $"fixture: Asset_Add '{name}' → {(int)s} {Code(b)} {b?["detail"]}"); return null; }
        var id = Id(b);
        var (ds, db) = await Post(admin, "api/v1/device/Device_Add", new { EntityId = id, PartNumber = name });
        if (ds != HttpStatusCode.OK) { Must(false, $"fixture: Device_Add '{name}' → {(int)ds} {Code(db)} {db?["detail"]}"); return id; }
        var (ps, pb) = await Post(admin, "api/v1/asset/PlaceAsset", new { AssetEntityId = id, NodeEntityId = position, PlacementKind = "Installed" });
        if (ps != HttpStatusCode.OK) { Must(false, $"fixture: PlaceAsset '{name}' → {(int)ps} {Code(pb)} {pb?["detail"]}"); return id; }
        var (fs, fb) = await Post(admin, "api/v1/device/ApplyFirmware", new { DeviceEntityId = id, FirmwareVersionId = firmware });
        if (fs != HttpStatusCode.OK) { Must(false, $"fixture: ApplyFirmware '{name}' → {(int)fs} {Code(fb)} {fb?["detail"]}"); }
        return id;
    }
    var devSel = await Relay($"{tag} SEL-421", sel, fwSel, positions[0]);
    var devBdd = await Relay($"{tag} BDD15B", bdd, fwBdd, positions[1]);
    var devCyl = await Relay($"{tag} CYL", cyl, fwCyl, positions[2]);
    Must(devSel is not null && devBdd is not null && devCyl is not null, "fixture: three relays placed with their firmware (SEL-421 microprocessor, BDD15B and CYL electromechanical)");

    async Task<Guid?> Definition(string kind, string key, string name, object? payload)
    {
        var (s, b) = await Post(admin, "api/v1/config/AddDefinition", new { DefinitionKind = kind, DefinitionKey = key, Name = name });
        if (s != HttpStatusCode.OK) { Must(false, $"fixture: AddDefinition {key} → {(int)s} {Code(b)} {b?["detail"]}"); return null; }
        var (vs, vb) = await Post(admin, "api/v1/config/AddDefinitionVersion", new { DefinitionKey = key, DefinitionKind = kind, ChangeNote = "W4 fixture", PayloadText = payload is null ? null : JsonSerializer.Serialize(payload) });
        if (vs != HttpStatusCode.OK) { Must(false, $"fixture: AddDefinitionVersion {key} → {(int)vs} {Code(vb)} {vb?["detail"]}"); return null; }
        var row = Id(vb, "VersionRowId");
        var (aps, apb) = await Post(approver, "api/v1/config/ApproveDefinitionVersion", new { VersionRowId = row });
        if (aps != HttpStatusCode.OK) { Must(false, $"fixture: ApproveDefinitionVersion {key} → {(int)aps} {Code(apb)} {apb?["detail"]}"); return null; }
        return row;
    }
    var schemeType = await Definition("Program.SchemeType", $"{tag}_SCHEME_TYPE", "W4 fixture scheme type", new { g = 1, name = "Transformer differential" });
    var (scs, scb) = await Post(admin, "api/v1/scheme/Scheme_Add", new { SchemeTypeDefinitionVersionRowId = schemeType, Name = $"{tag} 87T scheme", Status = "InService" });
    var scheme = Id(scb);
    Must(scs == HttpStatusCode.OK && scheme is not null, $"fixture: a scheme ({Code(scb)} {scb?["detail"]})");
    var workType = await Definition("Program.WorkType", $"{tag}_SETTINGS_CHANGE", "Settings change (W4 fixture)", new { g = 1, workflow = "SETTINGS_CHANGE_REQUEST", requiredRecordKinds = Array.Empty<string>() });
    var outageStart = DateTimeOffset.Now.AddSeconds(100);
    var (wrs, wrb) = await Post(admin, "api/v1/work/WorkRequest_Add", new { WorkTypeDefinitionVersionRowId = workType, Title = $"{tag} settings change", ScopeKind = "Node", ScopeEntityId = station, OutageRequired = true, OutageWindowStartAt = outageStart, OutageWindowEndAt = outageStart.AddHours(8) });
    var wr = Id(wrb);
    Must(wrs == HttpStatusCode.OK && wr is not null, $"fixture: a work request with an outage window opening in 100 s ({Code(wrb)} {wrb?["detail"]})");
    // the technician's competency: the training module the procedure names, and an attendance record
    var (tms, tmb) = await Post(admin, "api/v1/personnel/TrainingModule_Upsert", new { TrainingModuleCode = "PC_FIELD_SETTINGS", Name = "Field settings application (W4 fixture module)", RequiredFrequencyDays = 365 });
    Must(tms == HttpStatusCode.OK, $"fixture: training module PC_FIELD_SETTINGS ({Code(tmb)} {tmb?["detail"]})");
    var (tmr, tmrb) = await Get(admin, "api/v1/personnel/vTrainingModule?TrainingModuleCode=PC_FIELD_SETTINGS");
    var moduleEntity = Id((tmrb?["rows"] as JsonArray)?.FirstOrDefault());
    var (mes, meb) = await Get(tech, "api/v1/me");
    var techPerson = Id(meb?["person"], "entityId");
    // the trainer on the attendance record is the Administrator's actor (a person's actor row exists once they have acted)
    var (mas, mab) = await Get(admin, "api/v1/me");
    var (tas, tab) = await Get(admin, $"api/v1/personnel/vActor?PersonEntityId={Id(mab?["person"], "entityId")}");
    var techActor = Id((tab?["rows"] as JsonArray)?.FirstOrDefault(), "ActorId");
    var (trs, trb) = await Post(admin, "api/v1/record/Record_Add", new { RecordKindCode = "TrainingAttendance", SubjectKind = "Person", SubjectEntityId = techPerson, SecondSubjectKind = "TrainingModule", SecondSubjectEntityId = moduleEntity, OccurredAt = DateTimeOffset.Now.AddDays(-1), PerformedByActorId = techActor, OverallResult = "Pass" });
    Must(trs == HttpStatusCode.OK && moduleEntity is not null && techActor is not null, $"fixture: the technician's training attendance ({Code(trb)} {trb?["detail"]})");
    var (fcs, fcb) = await Post(admin, "api/v1/formula/check", new { expression = "person.training_current[module='PC_FIELD_SETTINGS'] = true", subjectKind = "Person" });
    Check(fcs == HttpStatusCode.OK && fcb?["ok"]?.GetValue<bool>() == true, "the technician alias's competency expression checks against the catalogue");

    if (w4ok)
    {
        // ---- the run: start the request's workflow, Start → InProgress starts SETTINGS_CHANGE pinned with DRAWING_REVISION
        var (sws, swb) = await Post(admin, "api/v1/process/workflows/start", new { workflowKey = "SETTINGS_CHANGE_REQUEST", subjectKind = "WorkRequest", subjectEntityId = wr });
        var wfReq = Id(swb, "workflowInstanceEntityId");
        Must(sws == HttpStatusCode.OK && wfReq is not null, $"start SETTINGS_CHANGE_REQUEST over the work request → {(int)sws} {Code(swb)} {swb?["detail"]}");
        var (trs1, trb1) = await Post(admin, $"api/v1/process/workflow-instances/{wfReq}/transitions", new { name = "Start" });
        Must(trs1 == HttpStatusCode.OK && trb1?["toState"]?.ToString() == "InProgress", $"transition Start → InProgress ({(int)trs1} {Code(trb1)} {trb1?["detail"]})");
        var (pis, pib) = await Get(admin, $"api/v1/process/vProcedureInstance?WorkflowInstanceEntityId={wfReq}");
        var inst = Id((pib?["rows"] as JsonArray)?.FirstOrDefault(r => r?["ParentInstanceEntityId"] is null));
        Must(inst is not null, $"entering InProgress started a SETTINGS_CHANGE instance ({inst})");
        var (pvs, pvb) = await Get(admin, $"api/v1/process/vInstanceVersionSet?ProcedureInstanceEntityId={inst}");
        var pinned = (pvb?["rows"] as JsonArray)?.Select(r => r?["CalleeKey"]?.ToString()).OrderBy(x => x).ToList() ?? [];
        Must(pinned.SequenceEqual(new[] { "DRAWING_REVISION", "SETTINGS_CHANGE" }), $"the version set pins the root and its callee ({string.Join(", ", pinned)})");

        async Task<JsonNode?> Tree() { var (_, b) = await Get(admin, $"api/v1/process/procedure-instances/{inst}"); return b; }
        async Task<Guid?> ReadyStep(string stepId, Guid? member = null, int tries = 1)
        {
            for (var i = 0; i < tries; i++)
            {
                var t = await Tree();
                var hit = (t?["blocks"] as JsonArray)?.FirstOrDefault(b => b?["step"]?["stepId"]?.ToString() == stepId && b?["step"]?["state"]?.ToString() == "Ready"
                    && (member is null || string.Equals(b?["memberSubjectEntityId"]?.ToString(), member.ToString(), StringComparison.OrdinalIgnoreCase)));
                if (hit is not null) return Id(hit?["step"], "stepInstanceEntityId");
                if (i + 1 < tries) { await Post(admin, $"api/v1/process/procedure-instances/{inst}/evaluate", new { }); }
            }
            return null;
        }
        async Task<(HttpStatusCode, JsonNode?)> RunStep(HttpClient who, string stepId, object body, Guid? member = null, HttpClient? witness = null, bool checkin = false)
        {
            var step = await ReadyStep(stepId, member, 2);
            if (step is null) { Must(false, $"{stepId}{(member is null ? "" : " [" + member.ToString()![..8] + "]")}: no Ready step instance"); return (HttpStatusCode.NotFound, null); }
            var (cls0, clb0) = await Post(who, $"api/v1/process/step-instances/{step}/claim", new { });
            if (cls0 != HttpStatusCode.OK) { Must(false, $"{stepId}: claim → {(int)cls0} {Code(clb0)} {clb0?["detail"]}"); return (cls0, clb0); }
            if (witness is not null) { var (ws, wb) = await Post(witness, $"api/v1/process/step-instances/{step}/witness", new { }); Must(ws == HttpStatusCode.OK, $"{stepId}: witnessed by a second person → {(int)ws} {Code(wb)} {wb?["detail"]}"); }
            var (rs, rb) = await Post(who, $"api/v1/process/step-instances/{step}/{(checkin ? "checkin" : "commit")}", body);
            Must(rs == HttpStatusCode.OK, $"{stepId}{(member is null ? "" : " [" + member.ToString()![..8] + "]")}: {(checkin ? "check-in" : "commit")} → {(int)rs} {Code(rb)} {rb?["detail"]} {(rb?["advanced"] is null ? "" : "· " + rb["advanced"])}");
            return (rs, rb);
        }
        Guid? package = null;
        async Task<string?> LifecycleState()
        {
            var (_, b) = await Get(admin, $"api/v1/process/vWorkflowInstance?SubjectKind=SettingsIssuePackage&SubjectEntityId={package}");
            return (b?["rows"] as JsonArray)?.Select(r => r?["CurrentState"]?.ToString()).FirstOrDefault();
        }

        // steps 1–3 by the engineer (the Administrator)
        var (r1s, r1b) = await RunStep(admin, "REQUEST", new { outcome = "Done", capture = new { trigger = "Project", sourceReference = tag } });
        package = Id(r1b, "producedEntityId");
        Must(package is not null, $"REQUEST produced the settings-issue package ({package})");
        Must((await LifecycleState()) == "Calculated", "the package's SETTINGS_LIFECYCLE instance starts in Calculated");
        await RunStep(admin, "SCOPE", new { outcome = "Done", capture = new { scheme = scheme, philosophy = "Transformer differential, 25 % slope", devices = new[] { devSel, devBdd, devCyl } } });
        await RunStep(admin, "STUDY", new { outcome = "Done", capture = new { studyKind = "ShortCircuit" }, evidence = new[] { File("study.txt", "text/plain", "Fault level study — fixture", "Study") } });
        // BUILD: the foreach over the three devices; the microprocessor relay's native file, the two electromechanical relays' text files
        await RunStep(admin, "BUILD_SETTINGS", new { outcome = "Done", evidence = new[] { File("sel421.rdb", "application/octet-stream", "SEL-421 native settings fixture", "SettingsFile") } }, devSel);
        await RunStep(admin, "RECORD_SETTINGS", new { outcome = "Done", evidence = new[] { File("bdd15b.txt", "text/plain", "WDG1=2.9, WDG2=4.2, SLOPE=25 %, HARMONIC RESTRAINT = 20%", "SettingsText") } }, devBdd);
        await RunStep(admin, "RECORD_SETTINGS", new { outcome = "Done", evidence = new[] { File("cyl.txt", "text/plain", "COMPENSATOR=1.4 OHMS, INST=14 AMPS", "SettingsText") } }, devCyl);
        var (pks, pkb) = await Get(admin, $"api/v1/document/vSettingsIssuePackageItem?PackageRevisionRowId={package}");
        Must(pks == HttpStatusCode.OK && (pkb?["rows"] as JsonArray)?.Count == 3, $"three configuration-file revisions are in the package ({(pkb?["rows"] as JsonArray)?.Count})");
        var (pss, psb) = await Get(admin, "api/v1/document/vParsedSetting?take=500");
        var parsedForRun = (psb?["rows"] as JsonArray)?.Count(r => (pkb?["rows"] as JsonArray)?.Any(i => string.Equals(i?["ConfigurationFileRevisionRowId"]?.ToString(), r?["ConfigurationFileRevisionRowId"]?.ToString(), StringComparison.OrdinalIgnoreCase)) == true) ?? 0;
        Must(parsedForRun == 6, $"the two text files parsed against their templates: 6 settings (WDG1, WDG2, SLOPE, HARMONIC_RESTRAINT; COMPENSATOR, INST) ({parsedForRun})");
        await RunStep(admin, "RATIONALE", new { outcome = "Done", evidence = new[] { File("rationale.txt", "text/plain", "Rationale — fixture", "Rationale") } });
        // the independent check by another engineer (segregation Calculate/Check on the instance: a different person)
        await RunStep(hydro, "CHECK", new { outcome = "Pass", capture = new { comments = "checked" } });
        Must((await LifecycleState()) == "Checked", "CHECK advanced the lifecycle to Checked");
        // a same-person approval would be refused: the Administrator who calculated cannot approve without an override
        {
            var step = await ReadyStep("APPROVE", null, 2);
            var (cls1, clb1) = await Post(admin, $"api/v1/process/step-instances/{step}/claim", new { });
            var (rs, rb) = await Post(admin, $"api/v1/process/step-instances/{step}/commit", new { outcome = "Approved" });
            Check(rs == HttpStatusCode.Conflict && (rb?["detail"]?.ToString().Contains("segregation", StringComparison.OrdinalIgnoreCase) ?? false), $"APPROVE by the person who calculated → 409 segregation ({rb?["detail"]?.ToString()?[..Math.Min(60, rb?["detail"]?.ToString()?.Length ?? 0)]})");
            await Post(admin, $"api/v1/process/step-instances/{step}/release", new { });
        }
        await RunStep(approver, "APPROVE", new { outcome = "Approved" });
        Must((await LifecycleState()) == "Approved", "APPROVE advanced the lifecycle to Approved (the package's revisions approved)");
        await RunStep(admin, "ISSUE", new { outcome = "Done", evidence = new[] { File("issue.txt", "text/plain", "Issue package — fixture", "IssuePackage") } });
        Must((await LifecycleState()) == "Issued", "ISSUE advanced the lifecycle to Issued");
        // the outage hold: held until the window opens; released by the sweep, not by a person
        var held = (await Tree())?["blocks"] as JsonArray;
        Must(held?.Any(b => b?["kind"]?.ToString() == "hold" && b?["state"]?.ToString() == "Held") == true, "AWAIT_OUTAGE is Held while the outage window is closed");
        var wait = outageStart - DateTimeOffset.Now + TimeSpan.FromSeconds(3);
        if (wait > TimeSpan.Zero) { Console.WriteLine($"  … waiting {wait.TotalSeconds:0} s for the outage window"); await Task.Delay(wait); }
        var (sws2, swb2) = await Post(admin, "api/v1/process/sweep", new { });
        Must(sws2 == HttpStatusCode.OK, $"the sweep ran ({swb2?["instances"]} instance(s), {swb2?["changes"]} change(s))");
        var afterSweep = (await Tree())?["blocks"] as JsonArray;
        Must(afterSweep?.Any(b => b?["kind"]?.ToString() == "hold" && b?["state"]?.ToString() == "Completed" && b?["outcome"]?.ToString() == "Released") == true, "the sweep released the outage hold (ReleaseBasis Condition)");
        // FIELD: per device — APPLY (the CYL as a deferred check-in with two actors), READBACK (a difference on the CYL), RESOLVE, TEST
        await RunStep(tech, "APPLY", new { outcome = "Done", capture = new { appliedAt = DateTimeOffset.Now } }, devSel);
        await RunStep(tech, "APPLY", new { outcome = "Done", capture = new { appliedAt = DateTimeOffset.Now } }, devBdd);
        await RunStep(admin, "APPLY", new { outcome = "Done", capture = new { appliedAt = DateTimeOffset.Now.AddHours(-2) }, capturedBy = techUpn, capturedAt = DateTimeOffset.Now.AddHours(-2) }, devCyl, null, true);
        Must((await LifecycleState()) == "Applied", "APPLY advanced the lifecycle to Applied (once per device; the repeats were no-ops)");
        await RunStep(tech, "READBACK", new { outcome = "Done", capture = new { differenceCount = 0 }, evidence = new[] { File("sel421-readback.rdb", "application/octet-stream", "readback", "ReadbackFile") } }, devSel);
        await RunStep(tech, "READBACK", new { outcome = "Done", capture = new { differenceCount = 0 }, evidence = new[] { File("bdd15b-readback.txt", "text/plain", "WDG1=2.9, WDG2=4.2, SLOPE=25 %, HARMONIC RESTRAINT = 20%", "ReadbackFile") } }, devBdd);
        await RunStep(tech, "READBACK", new { outcome = "Done", capture = new { differenceCount = 1 }, evidence = new[] { File("cyl-readback.txt", "text/plain", "COMPENSATOR=1.4 OHMS, INST=10 AMPS", "ReadbackFile") } }, devCyl);
        var (rds, rdb) = await RunStep(admin, "RESOLVE_DIFFERENCE", new { outcome = "ChangeRaised" }, devCyl);
        Must(rdb?["branchOutcome"]?.ToString() == "Superseded", $"RESOLVE_DIFFERENCE with ChangeRaised ends the CYL's branch as Superseded ({rdb?["branchOutcome"]})");
        await RunStep(tech, "TEST", new { outcome = "Pass", evidence = new[] { File("sel421-test.txt", "text/plain", "test sheet", "TestSheet") } }, devSel);
        await RunStep(tech, "TEST", new { outcome = "Pass", evidence = new[] { File("bdd15b-test.txt", "text/plain", "test sheet", "TestSheet") } }, devBdd);
        var t2 = (await Tree())?["blocks"] as JsonArray;
        Must(t2?.Any(b => string.Equals(b?["memberSubjectEntityId"]?.ToString(), devCyl.ToString(), StringComparison.OrdinalIgnoreCase) && b?["step"]?["stepId"]?.ToString() == "TEST" && b?["step"]?["state"]?.ToString() == "Skipped") == true, "the CYL's TEST was skipped with the branch outcome");
        // return to service, witnessed by a second person from their own session
        await RunStep(admin, "RETURN_TO_SERVICE", new { outcome = "Done" }, null, approver);
        Must((await LifecycleState()) == "Verified", "RETURN_TO_SERVICE advanced the lifecycle to Verified");
        // completion: the drawings call (DRAWING_REVISION child run) and the baseline
        var (cis, cib) = await Get(admin, $"api/v1/process/vProcedureInstance?ParentInstanceEntityId={inst}");
        var child = Id((cib?["rows"] as JsonArray)?.FirstOrDefault());
        Must(child is not null, $"the COMPLETION call started a DRAWING_REVISION child run ({child})");
        if (child is not null)
        {
            var (ct1, cb1) = await Get(admin, $"api/v1/process/procedure-instances/{child}");
            var childStep = Id((cb1?["readySteps"] as JsonArray)?.FirstOrDefault(), "stepEntityId");
            await Post(admin, $"api/v1/process/step-instances/{childStep}/claim", new { });
            var (ccs, ccb) = await Post(admin, $"api/v1/process/step-instances/{childStep}/commit", new { outcome = "Done" });
            Must(ccs == HttpStatusCode.OK, $"the child run's UPDATE_DRAWINGS committed → {(int)ccs} {Code(ccb)} {ccb?["detail"]}");
        }
        await RunStep(admin, "BASELINE", new { outcome = "Done" });
        Must((await LifecycleState()) == "InService", "BASELINE advanced the lifecycle to InService");
        var (evs, evb) = await Post(admin, $"api/v1/process/procedure-instances/{inst}/evaluate", new { });
        var (fis, fib) = await Get(admin, $"api/v1/process/vProcedureInstance?EntityId={inst}");
        var finalRow = (fib?["rows"] as JsonArray)?.FirstOrDefault();
        Must(finalRow?["State"]?.ToString() == "Completed" && finalRow?["Outcome"]?.ToString() == "Completed", $"the SETTINGS_CHANGE instance completed ({finalRow?["State"]} / {finalRow?["Outcome"]})");
        var (cls, clb) = await Post(admin, $"api/v1/process/workflow-instances/{wfReq}/transitions", new { name = "Close" });
        Must(cls == HttpStatusCode.OK && clb?["toState"]?.ToString() == "Closed", $"Close requires the procedure to have completed → {(int)cls} {clb?["toState"]} {clb?["detail"]}");

        // ---- the counts the gate asserts
        var (cfs, cfb) = await Get(admin, "api/v1/document/vConfigurationFile?take=500");
        var cf = (cfb?["rows"] as JsonArray)?.Where(r => new[] { devSel, devBdd, devCyl }.Any(d => string.Equals(d?.ToString(), r?["DeviceEntityId"]?.ToString(), StringComparison.OrdinalIgnoreCase))).ToList() ?? [];
        Must(cf.Count == 6 && cf.Count(r => r?["CaptureKind"]?.ToString() == "Designed") == 3 && cf.Count(r => r?["CaptureKind"]?.ToString() == "AsLeftReadback") == 3, $"six configuration-file revisions: three designed, three readbacks ({cf.Count})");
        Must(cf.Count(r => r?["CaptureKind"]?.ToString() == "Designed" && r?["InServiceFrom"] is not null) == 2, "two designed revisions are in service (the CYL's is not: its member left the change)");
        Must(cf.Any(r => r?["FileKind"]?.ToString() == "NativeSettings" && r?["ParseStatus"]?.ToString() == "NotParsed") && cf.Count(r => r?["FileKind"]?.ToString() == "SettingsText" && r?["ParseStatus"]?.ToString() == "Parsed") >= 2, "the native file is stored NotParsed; the text files Parsed");
        var (recs, recb) = await Get(admin, $"api/v1/record/vRecord?WorkRequestEntityId={wr}&take=200");
        var kinds = (recb?["rows"] as JsonArray)?.GroupBy(r => r?["RecordKindCode"]?.ToString()).ToDictionary(g => g.Key ?? "", g => g.Count()) ?? new();
        Must(kinds.GetValueOrDefault("ConfigurationFileRevision") == 3 && kinds.GetValueOrDefault("Readback") == 3 && kinds.GetValueOrDefault("Finding") >= 2 && kinds.GetValueOrDefault("TestSheet") == 2 && kinds.GetValueOrDefault("ReturnToService") == 1 && kinds.GetValueOrDefault("Baseline") == 1,
            $"records by kind: {string.Join(", ", kinds.OrderBy(k => k.Key).Select(k => k.Key + " " + k.Value))}");
        var (wts, wtb) = await Get(admin, $"api/v1/process/vWorkflowTransition?WorkflowInstanceEntityId={wfReq}");
        Must((wtb?["rows"] as JsonArray)?.Select(r => r?["TransitionName"]?.ToString()).SequenceEqual(new[] { "Start", "Close" }) == true, "the request's transitions: Start, Close");
        var (wis, wib) = await Get(admin, $"api/v1/process/vWorkflowInstance?SubjectKind=SettingsIssuePackage&SubjectEntityId={package}");
        var lifecycleId = Id((wib?["rows"] as JsonArray)?.FirstOrDefault());
        var (lts, ltb) = await Get(admin, $"api/v1/process/vWorkflowTransition?WorkflowInstanceEntityId={lifecycleId}");
        var lifecycleTransitions = (ltb?["rows"] as JsonArray)?.Select(r => r?["TransitionName"]?.ToString()).ToList() ?? [];
        Must(lifecycleTransitions.SequenceEqual(new[] { "Check", "Approve", "Issue", "Apply", "Verify", "Baseline" }), $"the package's transitions: {string.Join(", ", lifecycleTransitions)}");
        var (sts, stb) = await Get(admin, "api/v1/process/vStepInstance?CaptureSource=FieldPack&take=50");
        var deferredRow = (stb?["rows"] as JsonArray)?.FirstOrDefault(r => r?["StepId"]?.ToString() == "APPLY" && r?["AcceptedIntoPlatformByActorId"] is not null);
        Must(deferredRow is not null && deferredRow?["CommittedByActorId"]?.ToString() != deferredRow?["AcceptedIntoPlatformByActorId"]?.ToString(), "the deferred APPLY committed with two actors: the technician who captured, the person who checked it in");
        var (rtss, rtsb) = await Get(admin, "api/v1/process/vStepInstance?StepId=RETURN_TO_SERVICE&take=50");
        var rts = (rtsb?["rows"] as JsonArray)?.OrderByDescending(r => r?["CommittedAt"]?.ToString()).FirstOrDefault();
        Must(rts?["WitnessedByActorId"] is not null && rts?["WitnessedByActorId"]?.ToString() != rts?["CommittedByActorId"]?.ToString(), "RETURN_TO_SERVICE carries a witness other than the committer");

        // ---- version 2 and the migration list: a second, half-run instance appears; the first (completed) does not; both stay pinned to v1
        var (wr2s, wr2b) = await Post(admin, "api/v1/work/WorkRequest_Add", new { WorkTypeDefinitionVersionRowId = workType, Title = $"{tag} second change", ScopeKind = "Node", ScopeEntityId = station });
        var (sw2s, sw2b) = await Post(admin, "api/v1/process/workflows/start", new { workflowKey = "SETTINGS_CHANGE_REQUEST", subjectKind = "WorkRequest", subjectEntityId = Id(wr2b) });
        await Post(admin, $"api/v1/process/workflow-instances/{Id(sw2b, "workflowInstanceEntityId")}/transitions", new { name = "Start" });
        var (pi2s, pi2b) = await Get(admin, $"api/v1/process/vProcedureInstance?WorkflowInstanceEntityId={Id(sw2b, "workflowInstanceEntityId")}");
        var inst2 = Id((pi2b?["rows"] as JsonArray)?.FirstOrDefault());
        Must(inst2 is not null, $"a second SETTINGS_CHANGE run started ({inst2})");
        var v2 = (JsonObject)JsonNode.Parse(Example("settings-change.procedure.json"))!;
        v2["description"] = v2["description"]!.GetValue<string>() + $" v2 for the W4 migration gate ({tag}).";
        var (l2s, l2b) = await Post(admin, "api/v1/definitions/documents", new { document = v2, changeNote = "W4 gate: v2" });
        var (a2s, a2b) = await Post(approver, $"api/v1/definitions/documents/{l2b?["versionRowId"]}/approve", new { });
        Must(l2s == HttpStatusCode.OK && a2s == HttpStatusCode.OK, $"a new SETTINGS_CHANGE version approved ({l2b?["versionNumber"]} → {(int)a2s} {Code(a2b)})");
        var (mls, mlb) = await Get(admin, "api/v1/process/vMigrationList?take=500");
        var ml = (mlb?["rows"] as JsonArray) ?? new JsonArray();
        Must(ml.Any(r => string.Equals(r?["ProcedureInstanceEntityId"]?.ToString(), inst2.ToString(), StringComparison.OrdinalIgnoreCase) && r?["IsRootProcedure"]?.GetValue<bool>() == true), "the running instance is on the migration list, awaiting a ruling");
        Must(!ml.Any(r => string.Equals(r?["ProcedureInstanceEntityId"]?.ToString(), inst.ToString(), StringComparison.OrdinalIgnoreCase)), "the completed instance is not");
        var (pv2s, pv2b) = await Get(admin, $"api/v1/process/vInstanceVersionSet?ProcedureInstanceEntityId={inst2}&CalleeKey=SETTINGS_CHANGE");
        var (pv1s, pv1b) = await Get(admin, $"api/v1/process/vInstanceVersionSet?ProcedureInstanceEntityId={inst}&CalleeKey=SETTINGS_CHANGE");
        Must(string.Equals((pv2b?["rows"] as JsonArray)?[0]?["DefinitionVersionRowId"]?.ToString(), (pv1b?["rows"] as JsonArray)?[0]?["DefinitionVersionRowId"]?.ToString(), StringComparison.OrdinalIgnoreCase)
             && !string.Equals((pv2b?["rows"] as JsonArray)?[0]?["DefinitionVersionRowId"]?.ToString(), l2b?["versionRowId"]?.ToString(), StringComparison.OrdinalIgnoreCase), "both runs stay pinned to the version they started on; neither moved to v2");
        // leave the example document Effective again (the v2 above retired it), so a later run — the Windows-mode Administrator on VM02 — finds it stored and projected
        var (rls, rlb) = await Post(admin, "api/v1/definitions/documents", new { document = JsonNode.Parse(Example("settings-change.procedure.json")), changeNote = "W4 gate: the example restored after the migration check" });
        var (ras, rab) = await Post(approver, $"api/v1/definitions/documents/{rlb?["versionRowId"]}/approve", new { });
        Check(rls == HttpStatusCode.OK && (ras == HttpStatusCode.OK || AlreadyApproved(rab)), $"the example document is Effective again after the migration check (version {rlb?["versionNumber"]})");
    }
}
else Skip("W4 run (needs the Administrator, Approver, Hydro and Technician identities in one process — DEV mode)");

Console.WriteLine($"SMOKE {(failed == 0 ? "PASS" : "FAIL")}: {passed} passed, {failed} failed, {skipped} skipped");
return failed == 0 ? 0 : 1;
