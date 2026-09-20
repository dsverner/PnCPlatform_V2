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

if (args.Length < 1) { Console.Error.WriteLine("usage: PnC.Api.Smoke <api base url> [<connection string> | -] [--windows=Administrator|ReadOnly|Hydro|Approver|Technician]"); return 2; }
var baseUrl = args[0].TrimEnd('/');
var cs = args.Length > 1 && args[1] != "-" ? args[1] : null;
var windows = args.FirstOrDefault(a => a.StartsWith("--windows="))?["--windows=".Length..];
if (windows is not null and not ("Administrator" or "ReadOnly" or "Hydro" or "Approver" or "Technician")) { Console.Error.WriteLine("--windows must be Administrator, ReadOnly, Hydro, Approver or Technician"); return 2; }

var systemActor = new Guid("00000000-0000-0000-0000-000000000001");
var adminUpn = "smoke.admin@pnc.local"; var readUpn = "smoke.readonly@pnc.local"; var hydroUpn = "smoke.hydro@pnc.local"; var approverUpn = "smoke.approver@pnc.local"; var techUpn = "smoke.tech@pnc.local"; var engineerUpn = "smoke.engineer@pnc.local";
const string HydroDivision = "Generation · Hydro", TransmissionDivision = "Transmission";
int passed = 0, failed = 0, skipped = 0;
void Check(bool ok, string what) { if (ok) { passed++; Console.WriteLine("  PASS " + what); } else { failed++; Console.WriteLine("  FAIL " + what); } }
void Skip(string what) { skipped++; Console.WriteLine("  SKIP " + what); }

// ---- identities
HttpClient Client(string? upn)
{
    var h = new HttpClientHandler { UseDefaultCredentials = windows is not null && upn is not null };
    // W8: the DEV sweep walks every live instance (580 after a day of smoke fixtures and 266 migrated runs — 0.14 s each, 80 s measured); the call is DEV tooling, not a screen
    var c = new HttpClient(h) { BaseAddress = new Uri(baseUrl + "/"), Timeout = TimeSpan.FromSeconds(300) };
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
// W5 card F (#126): a PCEngineer with a Global grant authors definitions (a subtree-scoped engineer holds the code but not the subject)
HttpClient? engineer = windows is null ? Client(engineerUpn) : null;
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
    await Ensure(engineerUpn, "PCEngineer", "Engineer", "Global", null);
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
    // W8 (#153): "Generation" exists under NB Power and under each merchant owner — the name keys the first (NB Power's, seeded first)
    var divisions = (dsb?["rows"] as JsonArray)?.GroupBy(r => r?["Name"]?.ToString() ?? "").ToDictionary(g => g.Key, g => Guid.Parse(g.First()?["EntityId"]?.ToString() ?? Guid.Empty.ToString())) ?? new();
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

    var (ast, ab) = await Get(hydro, "api/v1/asset/vAsset?take=10000");
    var assetIds = Ids(ab);
    Check(ast == HttpStatusCode.OK && assetIds.Contains(hydroAsset.ToString()!.ToLowerInvariant()) && !assetIds.Contains(txAsset.ToString()!.ToLowerInvariant()),
        $"as Hydro, asset/vAsset lists the Hydro asset and not the Transmission asset ({assetIds.Count} rows)");
    var (nst, nb) = await Get(hydro, "api/v1/location/vNode?take=10000");
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

// ---- W8 (decision #136, #149): the grants screen's mechanism — a second grant widens a person's read scope, its revocation narrows it
if (admin is not null && hydro is not null && fixtureOk)
{
    var (hm, hmb) = await Get(hydro, "api/v1/me");
    var hydroUserId = hmb?["user"]?["entityId"]?.ToString();
    var (am, amb) = await Get(admin, "api/v1/me");
    var adminActor = amb?["actorId"]?.ToString();
    Check(am == HttpStatusCode.OK && !string.IsNullOrEmpty(adminActor), $"/me carries the session's own actor id (W8: who a grant is granted by) ({adminActor})");
    var (gls, glb) = await Get(admin, "api/v1/security/vGrant?take=10000");
    Check(gls == HttpStatusCode.OK && (glb?["rows"] as JsonArray)?.Any(r => string.Equals(r?["GranteeEntityId"]?.ToString(), hydroUserId, StringComparison.OrdinalIgnoreCase)) == true, "security/vGrant as the Administrator lists the Hydro engineer's grant");
    var (gls2, glb2) = await Get(hydro, "api/v1/security/vGrant?take=5");
    Check(gls2 == HttpStatusCode.Forbidden, $"security/vGrant as the Hydro engineer → 403 (Grant.Read is the Administrator's) [{(int)gls2}]");
    var (gas, gab) = await Post(admin, "api/v1/security/Grant_Add", new { GranteeKind = "User", GranteeEntityId = hydroUserId, RoleCode = "PCEngineer", ScopeKind = "NodeSubtree", ScopeNodeEntityId = txStation, GrantedByActorId = adminActor });
    var newGrant = gab?["EntityId"]?.ToString();
    Check(gas == HttpStatusCode.OK && newGrant is not null, $"Grant_Add: a second PCEngineer grant for the Hydro engineer, scoped to the Transmission station → 200 ({(int)gas} {gab?["detail"]})");
    var (wst, wb) = await Get(hydro, "api/v1/asset/vAsset?take=10000");
    var widened = Ids(wb);
    Check(wst == HttpStatusCode.OK && widened.Contains(txAsset.ToString()!.ToLowerInvariant()) && widened.Contains(hydroAsset.ToString()!.ToLowerInvariant()), $"with the second grant the Hydro engineer reads the Transmission asset too ({widened.Count} rows)");
    if (newGrant is not null)
    {
        var row = (await Get(admin, $"api/v1/security/vGrant?EntityId={newGrant}")).Item2?["rows"]?[0];
        var (rvs, rvb) = await Post(admin, "api/v1/security/Grant_Revise", new { EntityId = newGrant, GranteeKind = "User", GranteeEntityId = hydroUserId, RoleCode = "PCEngineer", ScopeKind = "NodeSubtree", ScopeNodeEntityId = txStation,
            GrantedByActorId = row?["GrantedByActorId"]?.ToString(), RevokedByActorId = adminActor, RevocationReason = "smoke: the grant was for the check" });
        Check(rvs == HttpStatusCode.OK, $"Grant_Revise revokes it with who and why → 200 ({(int)rvs} {rvb?["detail"]})");
        var (nst, nb) = await Get(hydro, "api/v1/asset/vAsset?take=10000");
        var narrowed = Ids(nb);
        Check(nst == HttpStatusCode.OK && !narrowed.Contains(txAsset.ToString()!.ToLowerInvariant()) && narrowed.Contains(hydroAsset.ToString()!.ToLowerInvariant()), $"revoked, the Hydro engineer no longer reads the Transmission asset ({narrowed.Count} rows)");
        var kept = (await Get(admin, $"api/v1/security/vGrant?EntityId={newGrant}")).Item2?["rows"]?[0];
        Check(kept?["RevokedByActorId"] is not null && kept?["RevocationReason"]?.ToString() == "smoke: the grant was for the check", "the revoked grant stays on the record with its reason (no hard delete)");
    }
}
else Skip("W8 grants (needs the Administrator and Hydro identities and the fixture)");

if (admin is not null && fixtureOk)
{
    // #206: the estate holds more assets than one page (the rule made ~3 200 instrument transformers), so each fixture asset is read by id
    var (ast, ab) = await Get(admin, $"api/v1/asset/vAsset?EntityId={hydroAsset}&take=1"); var (ast2, ab2) = await Get(admin, $"api/v1/asset/vAsset?EntityId={txAsset}&take=1");
    var ids = Ids(ab).Concat(Ids(ab2)).ToList();
    Check(ast == HttpStatusCode.OK && ast2 == HttpStatusCode.OK && ids.Contains(hydroAsset.ToString()!.ToLowerInvariant()) && ids.Contains(txAsset.ToString()!.ToLowerInvariant()), "as Administrator (Global), both assets are listed");
}
if (readOnly is not null && fixtureOk)
{
    var (ast, ab) = await Get(readOnly, $"api/v1/asset/vAsset?EntityId={hydroAsset}&take=1"); var (ast2, ab2) = await Get(readOnly, $"api/v1/asset/vAsset?EntityId={txAsset}&take=1");
    var ids = Ids(ab).Concat(Ids(ab2)).ToList();
    Check(ast == HttpStatusCode.OK && ast2 == HttpStatusCode.OK && ids.Contains(hydroAsset.ToString()!.ToLowerInvariant()) && ids.Contains(txAsset.ToString()!.ToLowerInvariant()), "as ReadOnly (Global), both assets are listed");
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
// W8 (#149): in Windows mode each gate pass is one identity, so the Approver pass also loads (existing) and approves what the
// Administrator pass authored, and either pass approves as itself — refused for its own author, else approved; two passes converge
var author = admin ?? approver;
if (author is not null)
{
    async Task<(HttpStatusCode, JsonNode?)> Load(string file) =>
        await Post(author!, "api/v1/definitions/documents", new { document = JsonNode.Parse(Example(file)), changeNote = "W3 gate" });
    async Task<(HttpStatusCode, JsonNode?)> Approve(HttpClient who, string rowId) => await Post(who, $"api/v1/definitions/documents/{rowId}/approve", new { });
    string Errors(JsonNode? b) => b?["errors"] is JsonArray ea ? string.Join(" | ", ea.Select(x => x?["path"] + ": " + x?["message"])) : "";

    // order: the lifecycle workflow (the procedure's advances need it Effective); the procedure (the request workflow names it); the request workflow
    var (ls, lb) = await Load("settings-lifecycle.workflow.json");
    Check(ls == HttpStatusCode.OK && lb?["versionRowId"] is not null, $"load SETTINGS_LIFECYCLE workflow → {(int)ls} {Code(lb)} {Errors(lb)} (version {lb?["versionNumber"]}, existing {lb?["existing"]})");
    string? lifecycleRow = lb?["versionRowId"]?.ToString();
    if (lifecycleRow is not null)
    {
        var (as1, ab1) = await Approve(author!, lifecycleRow);
        Check(as1 == HttpStatusCode.Conflict || as1 == HttpStatusCode.OK || AlreadyApproved(ab1), $"approve SETTINGS_LIFECYCLE as this pass's identity → refused for its own author, else approved ({(int)as1} {Short(ab1)})");
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
    if (rb?["versionRowId"]?.ToString() is { } reqRow)
    {
        var (as3, ab3) = await Approve(approver ?? author!, reqRow);
        Check(as3 == HttpStatusCode.OK || as3 == HttpStatusCode.Conflict || AlreadyApproved(ab3), $"approve SETTINGS_CHANGE_REQUEST as the second Administrator (or refused for its own author) → {(int)as3} {Code(ab3)}");
    }

    if (procRow is not null)
    {
        var (as4, ab4) = await Approve(author!, procRow);
        Check(as4 == HttpStatusCode.Conflict || as4 == HttpStatusCode.OK || AlreadyApproved(ab4), $"approve SETTINGS_CHANGE as this pass's identity → refused for its own author, else approved ({(int)as4} {Short(ab4)})");
        if (approver is not null)
        {
            var (as5, ab5) = await Approve(approver, procRow);
            Check(as5 == HttpStatusCode.OK || AlreadyApproved(ab5), $"approve SETTINGS_CHANGE as the second Administrator → {(int)as5} {Code(ab5)} (projected {ab5?["projectedSteps"]})");
        }
        else Skip("approve SETTINGS_CHANGE (needs the Approver identity)");
        // the projection — the design verification's counts: 14 steps, 4 advances, 1 call
        var (ss, sb) = await Get(author!, $"api/v1/process/vProcedureStep?DefinitionVersionRowId={procRow}&take=100");
        var steps = (sb?["rows"] as JsonArray) ?? new JsonArray();
        // FR-3.1's fourteen numbered steps are fifteen step blocks plus one call: [4] has two variants (BUILD_SETTINGS /
        // RECORD_SETTINGS, the electromechanical fork), RESOLVE_DIFFERENCE is unnumbered, and [14] is the call block.
        Check(ss == HttpStatusCode.OK && steps.Count == 15, $"process/vProcedureStep holds 15 rows for SETTINGS_CHANGE — the 14 FR-3.1 steps as 15 step blocks + 1 call ({steps.Count})");
        var numbered = steps.Select(r => r?["Title"]?.ToString() ?? "").Where(t => t.StartsWith('[')).Select(t => t[1..t.IndexOf(']')]).Distinct().Count();
        Check(numbered == 13 && steps.Any(r => r?["StepId"]?.ToString() == "RESOLVE_DIFFERENCE"), $"the step titles carry FR-3.1 numbers [1]–[13] ({numbered} distinct; [14] is the call) plus the unnumbered RESOLVE_DIFFERENCE");
        var advancing = steps.Count(r => r?["AdvancesTransition"] is not null);
        Check(advancing == 6, $"6 steps advance the lifecycle workflow: CHECK, APPROVE, ISSUE, APPLY, RETURN_TO_SERVICE, BASELINE ({advancing})");
        Check(steps.Count(r => r?["RequiresWitness"]?.GetValue<bool>() == true) == 1 && steps.Any(r => r?["StepId"]?.ToString() == "RETURN_TO_SERVICE" && r?["RequiresWitness"]?.GetValue<bool>() == true), "RETURN_TO_SERVICE is the one witnessed step");
        var (cs1, cb1) = await Get(author!, $"api/v1/process/vProcedureCall?DefinitionVersionRowId={procRow}");
        var calls = (cb1?["rows"] as JsonArray) ?? new JsonArray();
        Check(cs1 == HttpStatusCode.OK && calls.Count == 1 && calls[0]?["CalleeKey"]?.ToString() == "DRAWING_REVISION", $"process/vProcedureCall: 1 call, to DRAWING_REVISION ({calls.Count})");
        var (fs, fb) = await Get(author!, $"api/v1/process/vProcedureFactUse?DefinitionVersionRowId={procRow}&take=200");
        var facts = ((fb?["rows"] as JsonArray) ?? new JsonArray()).Select(r => r?["FactName"]?.ToString()).Distinct().OrderBy(x => x).ToList();
        Check(fs == HttpStatusCode.OK && facts.Contains("device.technology") && facts.Contains("step.outcome") && facts.Contains("work.outage_required") && facts.Contains("person.training_current"),
              $"process/vProcedureFactUse indexes the facts the document reads ({string.Join(", ", facts)})");
        var (rls, rlb) = await Get(author!, "api/v1/process/vProcedureStepRole?RoleCode=PCTechnician&take=100");
        Check(rls == HttpStatusCode.OK && ((rlb?["rows"] as JsonArray) ?? new JsonArray()).Any(r => r?["RequiresAst"] is not null), "process/vProcedureStepRole carries the technician's competency expression as canonical AST");
    }

    // a document the grammar refuses is refused with its path; one the structure refuses, in the rule's words
    var bad = (JsonObject)JsonNode.Parse(Example("settings-change.procedure.json"))!;
    bad["key"] = "SMOKE_BAD"; ((JsonObject)bad["roles"]!["technician"]!)["requires"] = "person.training_current = 'yes'";
    var (bs, bb) = await Post(author!, "api/v1/definitions/documents", new { document = bad });
    Check(bs == HttpStatusCode.BadRequest && Code(bb) == "document_invalid" && (bb?["errors"] as JsonArray)?.Any(e => e?["path"]?.ToString() == "$.roles.technician.requires") == true,
          $"a document whose expression fails the type check → 400 document_invalid at $.roles.technician.requires ({(bb?["errors"] as JsonArray)?[0]?["message"]})");
    var bad2 = (JsonObject)JsonNode.Parse(Example("settings-change.procedure.json"))!;
    bad2["key"] = "SMOKE_BAD2"; ((JsonObject)((JsonArray)bad2["body"]!["items"]!)[1]!)["id"] = "REQUEST";
    var (b2s, b2b) = await Post(author!, "api/v1/definitions/documents", new { document = bad2 });
    Check(b2s == HttpStatusCode.Conflict && b2b?["sqlNumber"]?.GetValue<int>() == 50121, $"a document with a duplicate block id → 409 in the rule's words ({Short(b2b)})");

    // the live expression check
    var (fcs, fcb) = await Post(author!, "api/v1/formula/check", new { expression = "value >= 0", env = new { value = new { type = "num" } } });
    Check(fcs == HttpStatusCode.OK && fcb?["ok"]?.GetValue<bool>() == true && fcb?["type"]?.ToString() == "bool", $"formula/check: value >= 0 → {fcb?["type"]}");
    var (fes, feb) = await Post(author!, "api/v1/formula/check", new { expression = "device.no_such_fact = 1" });
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
    var (gs, gb) = await Post(author!, "api/v1/definitions/documents", new { document = gateDoc, changeNote = "W3 gate" });
    Check(gs == HttpStatusCode.OK && gb?["existing"]?.GetValue<bool>() == false, $"author a fresh {GateKey} Draft as the Administrator → {(int)gs} (version {gb?["versionNumber"]})");
    if (gb?["versionRowId"]?.ToString() is { } gRow)
    {
        var (gas, gab) = await Post(author!, $"api/v1/definitions/documents/{gRow}/approve", new { });
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

// ======================================================================= W5 (part 1) — DRAWING_REVISION v2, the first procedure authored in the tool
// docs/design/examples/drawing-revision.procedure.json is the text the editor saved (decision #121). Loaded here, before the
// W4 run, so the run's version set pins v2 and the child run below is the gate's "DRAWING_REVISION completes inside a
// SETTINGS_CHANGE run". Idempotent as the W3 loads are.
string? drawingV2Row = null;
if (author is not null)
{
    var (ds, db) = await Post(engineer ?? author!, "api/v1/definitions/documents", new { document = JsonNode.Parse(Example("drawing-revision.procedure.json")), changeNote = "W5: authored in the tool" + (engineer is null ? "" : " by a Global PCEngineer (#126)") });
    drawingV2Row = db?["versionRowId"]?.ToString();
    Check(ds == HttpStatusCode.OK && drawingV2Row is not null, $"load DRAWING_REVISION (the tool-authored version) as {(engineer is null ? "the Administrator" : "a Global PCEngineer, #126")} → {(int)ds} {Code(db)} (version {db?["versionNumber"]}, existing {db?["existing"]})");
    if (hydro is not null)
    {
        var (hs, hb) = await Post(hydro, "api/v1/definitions/documents", new { document = JsonNode.Parse(Example("drawing-revision.procedure.json")) });
        Check(hs == HttpStatusCode.Forbidden, $"the subtree-scoped engineer holds Definition.Modify but not the subject (Global only) → 403 ({hb?["detail"]})");
    }
    if (drawingV2Row is not null)
    {
        var (das, dab) = await Post(approver ?? author!, $"api/v1/definitions/documents/{drawingV2Row}/approve", new { });
        Check(das == HttpStatusCode.OK || das == HttpStatusCode.Conflict || AlreadyApproved(dab), $"the tool-authored DRAWING_REVISION approved by the second Administrator → {(int)das} {Code(dab)} (projected {dab?["projectedSteps"]})");
        var (dvs, dvb) = await Get(author!, $"api/v1/config/vDefinitionVersion?RowId={drawingV2Row}");
        if (das == HttpStatusCode.OK || AlreadyApproved(dab)) Check((dvb?["rows"] as JsonArray)?.FirstOrDefault()?["Status"]?.ToString() == "Effective", "the tool-authored DRAWING_REVISION is the Effective version");
    }
}
else Skip("W5 DRAWING_REVISION v2 (needs the Administrator identity)");

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
    // W6 fixture: 87T commissioned AT each position, and the relay standing there is the scheme's member.
    // #181: the element is no longer a node of its own — the owner ruled the FLOC ends at the position, so a
    // commissioned function names the position and a scheme names the relay.
    var (afs, afb) = await Post(admin, "api/v1/ref/AnsiFunction_Upsert", new { AnsiCode = "87T", Name = "Transformer differential" });
    Must(afs == HttpStatusCode.OK, $"fixture: ANSI function 87T ({(int)afs} {Code(afb)} {afb?["detail"]})");
    var commissioned = new List<Guid?>();
    for (var i = 0; i < 3; i++)
    {
        var (cfs0, cfb0) = await Post(admin, "api/v1/scheme/CommissionedFunction_Add", new { ProtectionFunctionNodeEntityId = positions[i], AnsiCode = "87T", IsPrincipal = true });
        if (cfs0 != HttpStatusCode.OK) Must(false, $"fixture: CommissionedFunction_Add position {i + 1} → {(int)cfs0} {Code(cfb0)} {cfb0?["detail"]}");
        commissioned.Add(Id(cfb0));
        var (sms, smb) = await Post(admin, "api/v1/scheme/AddSchemeMember", new { SchemeEntityId = scheme, MemberKind = "Asset", MemberEntityId = new[] { devSel, devBdd, devCyl }[i], MemberRoleCode = "InitiatingDevice" });
        if (sms != HttpStatusCode.OK) Must(false, $"fixture: AddSchemeMember position {i + 1} → {(int)sms} {Code(smb)} {smb?["detail"]}");
    }
    Must(commissioned.All(f => f is not null), "fixture: 87T commissioned at the three positions, with their relays in the scheme");
    var stationNumber = "9" + tag[^6..];
    var (aks, akb) = await Post(admin, "api/v1/location/AlternateKey_Add", new { SubjectEntityId = station, KeyKindCode = "StationNumber", KeyValue = stationNumber, IsPrimaryLabel = true });
    Must(aks == HttpStatusCode.OK, $"fixture: station number {stationNumber} ({(int)aks} {Code(akb)} {akb?["detail"]})");
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
        // W8: the estate holds 16 000+ parsed settings, so the package's are read by revision, never from a first page
        var parsedForRun = 0;
        foreach (var item in (pkb?["rows"] as JsonArray) ?? new JsonArray())
        {
            var (pss1, psb1) = await Get(admin, $"api/v1/document/vParsedSetting?ConfigurationFileRevisionRowId={item?["ConfigurationFileRevisionRowId"]}");
            parsedForRun += (psb1?["rows"] as JsonArray)?.Count ?? 0;
        }
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
            // W5: the child runs DRAWING_REVISION v2 (two steps with required captures); every ready step is claimed and
            // committed with the captures its definition requires until the run completes. v1's single step would commit too.
            var childCaptures = new Dictionary<string, object>
            {
                ["IDENTIFY_DRAWINGS"] = new { drawingReferences = $"{tag} drawings: 1234-E-001 rev C, 1234-E-014 rev B", note = "fixture" },
                ["RECORD_REVISION"] = new { documentLink = $"drawings://issue/{tag}", revisionLabel = "C", revisedOn = DateTimeOffset.Now },
            };
            var committed = new List<string>();
            for (var round = 0; round < 6; round++)
            {
                var (ct1, cb1) = await Get(admin, $"api/v1/process/procedure-instances/{child}");
                if (cb1?["state"]?.ToString() == "Completed") break;
                var ready = (cb1?["readySteps"] as JsonArray)?.Where(r => r?["stepState"]?.ToString() == "Ready").ToList() ?? [];
                if (ready.Count == 0) { await Post(admin, $"api/v1/process/procedure-instances/{child}/evaluate", new { }); continue; }
                foreach (var r in ready)
                {
                    var stepId = r?["stepId"]?.ToString() ?? "";
                    var stepEntity = Id(r, "stepEntityId");
                    await Post(admin, $"api/v1/process/step-instances/{stepEntity}/claim", new { });
                    object body = childCaptures.TryGetValue(stepId, out var cap) ? new { outcome = "Done", capture = cap } : new { outcome = "Done" };
                    var (ccs, ccb) = await Post(admin, $"api/v1/process/step-instances/{stepEntity}/commit", body);
                    Must(ccs == HttpStatusCode.OK, $"the child run's {stepId} committed → {(int)ccs} {Code(ccb)} {ccb?["detail"]}");
                    committed.Add(stepId);
                }
            }
            var (cfs2, cfb2) = await Get(admin, $"api/v1/process/vProcedureInstance?EntityId={child}");
            var childRow = (cfb2?["rows"] as JsonArray)?.FirstOrDefault();
            Must(childRow?["State"]?.ToString() == "Completed", $"the DRAWING_REVISION child run completed inside the SETTINGS_CHANGE run ({childRow?["State"]}; steps {string.Join(", ", committed)})");
            if (drawingV2Row is not null)
                Must(string.Equals(childRow?["DefinitionVersionRowId"]?.ToString(), drawingV2Row, StringComparison.OrdinalIgnoreCase), "the child run is pinned to the DRAWING_REVISION version authored in the tool (v3 shape: 14a, then 14b only when drawings are affected)");
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
        // W7: the estate holds 11 000+ revisions, so the three devices' files are read by device, never from a first page
        var cf = new List<JsonNode?>(); HttpStatusCode cfs = HttpStatusCode.OK;
        foreach (var d in new[] { devSel, devBdd, devCyl }) { var (cfs1, cfb1) = await Get(admin, $"api/v1/document/vConfigurationFile?DeviceEntityId={d}"); if (cfs1 != HttpStatusCode.OK) cfs = cfs1; cf.AddRange(cfb1?["rows"] as JsonArray ?? new JsonArray()); }
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
        var (sts, stb) = await Get(admin, "api/v1/process/vStepInstance?CaptureSource=FieldPack&orderBy=-RowSeq&take=50");
        var deferredRow = (stb?["rows"] as JsonArray)?.FirstOrDefault(r => r?["StepId"]?.ToString() == "APPLY" && r?["AcceptedIntoPlatformByActorId"] is not null);
        Must(deferredRow is not null && deferredRow?["CommittedByActorId"]?.ToString() != deferredRow?["AcceptedIntoPlatformByActorId"]?.ToString(), "the deferred APPLY committed with two actors: the technician who captured, the person who checked it in");
        var (rtss, rtsb) = await Get(admin, "api/v1/process/vStepInstance?StepId=RETURN_TO_SERVICE&orderBy=-RowSeq&take=50"); // newest first: the landed runs hold hundreds
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
        // W8 (0.9.0): read the list for each instance by its id — on the migrated estate the whole list runs past a page (527 rows on DEV,
        // 2026-09-14: every migrated running instance pinned to an earlier SETTINGS_CHANGE version once a newer one is approved)
        var (mls, mlb) = await Get(admin, $"api/v1/process/vMigrationList?ProcedureInstanceEntityId={inst2}&take=500");
        var ml = (mlb?["rows"] as JsonArray) ?? new JsonArray();
        Must(ml.Any(r => string.Equals(r?["ProcedureInstanceEntityId"]?.ToString(), inst2.ToString(), StringComparison.OrdinalIgnoreCase) && r?["IsRootProcedure"]?.GetValue<bool>() == true), "the running instance is on the migration list, awaiting a ruling");
        var (mlcs, mlcb) = await Get(admin, $"api/v1/process/vMigrationList?ProcedureInstanceEntityId={inst}&take=500");
        Must(mlcs == HttpStatusCode.OK && ((mlcb?["rows"] as JsonArray) ?? new JsonArray()).Count == 0, "the completed instance is not");
        var (pv2s, pv2b) = await Get(admin, $"api/v1/process/vInstanceVersionSet?ProcedureInstanceEntityId={inst2}&CalleeKey=SETTINGS_CHANGE");
        var (pv1s, pv1b) = await Get(admin, $"api/v1/process/vInstanceVersionSet?ProcedureInstanceEntityId={inst}&CalleeKey=SETTINGS_CHANGE");
        Must(string.Equals((pv2b?["rows"] as JsonArray)?[0]?["DefinitionVersionRowId"]?.ToString(), (pv1b?["rows"] as JsonArray)?[0]?["DefinitionVersionRowId"]?.ToString(), StringComparison.OrdinalIgnoreCase)
             && !string.Equals((pv2b?["rows"] as JsonArray)?[0]?["DefinitionVersionRowId"]?.ToString(), l2b?["versionRowId"]?.ToString(), StringComparison.OrdinalIgnoreCase), "both runs stay pinned to the version they started on; neither moved to v2");
        // leave the example document Effective again (the v2 above retired it), so a later run — the Windows-mode Administrator on VM02 — finds it stored and projected
        var (rls, rlb) = await Post(admin, "api/v1/definitions/documents", new { document = JsonNode.Parse(Example("settings-change.procedure.json")), changeNote = "W4 gate: the example restored after the migration check" });
        var (ras, rab) = await Post(approver, $"api/v1/definitions/documents/{rlb?["versionRowId"]}/approve", new { });
        Check(rls == HttpStatusCode.OK && (ras == HttpStatusCode.OK || AlreadyApproved(rab)), $"the example document is Effective again after the migration check (version {rlb?["versionNumber"]})");

        // =================================================================== W6 — the parity read models over this run (PROCEDURE-ENGINE §10)
        Console.WriteLine("  -- W6 parity read models");
        async Task<(HttpStatusCode, JsonArray, long)> Timed(HttpClient who, string path)
        {
            await Get(who, path);   // warm-up: the plan compiles once
            var sw = System.Diagnostics.Stopwatch.StartNew();
            var (st0, b0) = await Get(who, path);
            sw.Stop();
            return (st0, (b0?["rows"] as JsonArray) ?? new JsonArray(), sw.ElapsedMilliseconds);
        }
        // §10 rows 1–3, 7: the grid — this request's three designed revisions
        var (g1s, g1rows, g1ms) = await Timed(admin, $"api/v1/document/vSettingsRecord?WorkRequestEntityId={wr}");
        JsonNode? Row(JsonArray rows, Guid? dev) => rows.FirstOrDefault(r => string.Equals(r?["DeviceEntityId"]?.ToString(), dev?.ToString(), StringComparison.OrdinalIgnoreCase));
        var gSel = Row(g1rows, devSel); var gBdd = Row(g1rows, devBdd); var gCyl = Row(g1rows, devCyl);
        Must(g1s == HttpStatusCode.OK && g1rows.Count == 3, $"vSettingsRecord: three designed revisions for the request ({g1rows.Count}, {g1ms} ms)");
        Must(gSel?["GridState"]?.ToString() == "Active" && gBdd?["GridState"]?.ToString() == "Active", $"the SEL-421 and BDD15B rows are Active (in service) ({gSel?["GridState"]}, {gBdd?["GridState"]})");
        Must(gCyl?["GridState"]?.ToString() == "Withdrawn" && gCyl?["VerifiedAt"] is null, $"the CYL row is Withdrawn with no verified date — its member left the change ({gCyl?["GridState"]}, {gCyl?["VerifiedAt"]})");
        Must(gSel?["VerifiedAt"]?.ToString() == rts?["CommittedAt"]?.ToString() && gSel?["CalculatedAt"] is not null, $"VDATE is the return-to-service commit instant and CDATE is set ({gSel?["VerifiedAt"]} / {gSel?["CalculatedAt"]})");
        Must(gSel?["Functions"]?.ToString() == "87T" && gSel?["StationName"]?.ToString() == $"{tag} station" && gSel?["PanelName"]?.ToString() == $"{tag} panel 1" && gSel?["StationNumber"]?.ToString() == stationNumber,
            $"the grid row carries location, panel, station number and the commissioned functions ({gSel?["StationName"]} / {gSel?["PanelName"]} / {gSel?["StationNumber"]} / {gSel?["Functions"]})");
        Must(gSel?["WorkTypeKey"]?.ToString() == $"{tag}_SETTINGS_CHANGE" && gSel?["ModelCode"]?.ToString() == "SEL-421" && gSel?["RtsStepState"]?.ToString() == "Committed", $"action type, model and the RTS step state on the row ({gSel?["WorkTypeKey"]}, {gSel?["ModelCode"]}, {gSel?["RtsStepState"]})");
        // W8 (#158): the grid row carries the scheme its device belongs to — through the function member here (the migration adds the asset member)
        Must(gSel?["SchemeName"]?.ToString() == $"{tag} 87T scheme" && string.Equals(gSel?["SchemeEntityId"]?.ToString(), scheme?.ToString(), StringComparison.OrdinalIgnoreCase), $"the grid row names its scheme — the settings book's group ({gSel?["SchemeName"]})");
        var (ga1s, ga1b) = await Get(admin, $"api/v1/document/vSettingsRecord?GridState=Active&DeviceEntityId={devSel}");
        Must(ga1s == HttpStatusCode.OK && (ga1b?["rows"] as JsonArray)?.Count == 1, "the Active toggle filtered to the SEL-421 → one row");
        var (gh1s, gh1b) = await Get(hydro, $"api/v1/document/vSettingsRecord?WorkRequestEntityId={wr}");
        var (gr1s, gr1b) = await Get(readOnly!, $"api/v1/document/vSettingsRecord?WorkRequestEntityId={wr}");
        Must(gh1s == HttpStatusCode.OK && (gh1b?["rows"] as JsonArray)?.Count == 3 && gr1s == HttpStatusCode.OK && (gr1b?["rows"] as JsonArray)?.Count == 3, "the Hydro engineer (subtree) and ReadOnly read the same three rows (Asset family scope)");

        // §10 row 2: Outstanding — drive the half-run second instance through REQUEST, SCOPE (the SEL only), STUDY and BUILD
        inst = inst2;   // the step helpers read the tree of `inst`
        var (r2s, r2b) = await RunStep(admin, "REQUEST", new { outcome = "Done", capture = new { trigger = "Finding", sourceReference = tag + " second" } });
        await RunStep(admin, "SCOPE", new { outcome = "Done", capture = new { scheme = scheme, philosophy = "Slope revised", devices = new[] { devSel } } });
        await RunStep(admin, "STUDY", new { outcome = "Done", capture = new { studyKind = "Coordination" }, evidence = new[] { File("study2.txt", "text/plain", "Coordination study — second change", "Study") } });
        await RunStep(admin, "BUILD_SETTINGS", new { outcome = "Done", evidence = new[] { File("sel421-v2.rdb", "application/octet-stream", "SEL-421 native settings, second change", "SettingsFile") } }, devSel);
        var (g2s, g2b) = await Get(admin, $"api/v1/document/vSettingsRecord?DeviceEntityId={devSel}&orderBy=-CalculatedAt");
        var g2 = (g2b?["rows"] as JsonArray) ?? new JsonArray();
        Must(g2.Count == 2 && g2.Count(r => r?["GridState"]?.ToString() == "Active") == 1 && g2.Count(r => r?["GridState"]?.ToString() == "Outstanding") == 1,
            $"the SEL-421 now has one Active and one Outstanding record — the legacy A + M pair ({string.Join(", ", g2.Select(r => r?["GridState"]))})");
        Must(g2.First(r => r?["GridState"]?.ToString() == "Outstanding")?["LifecycleState"]?.ToString() == "Calculated" && g2.First(r => r?["GridState"]?.ToString() == "Outstanding")?["VerifiedAt"] is null, "the Outstanding record is Calculated with no verified date yet");

        // §10 rows 4–6: the change-request status — two tracks, action type, requested by
        var (c1s, c1rows, c1ms) = await Timed(admin, $"api/v1/work/vChangeRequestStatus?WorkRequestEntityId={wr}");
        var c1 = c1rows.FirstOrDefault();
        Must(c1s == HttpStatusCode.OK && c1 is not null, $"vChangeRequestStatus: the closed request ({c1ms} ms)");
        Must(c1?["RequestState"]?.ToString() == "Closed" && c1?["DocumentationStatus"]?.ToString() == "Complete" && c1?["DatabaseStatus"]?.ToString() == "Complete",
            $"request Closed; documentation and database tracks Complete ({c1?["RequestState"]}, {c1?["DocumentationStatus"]}, {c1?["DatabaseStatus"]})");
        Must(c1?["DocumentationLink"]?.ToString() == $"drawings://issue/{tag}" && c1?["DocumentationRevisionLabel"]?.ToString() == "C" && c1?["DatabaseAt"] is not null && c1?["DeviceCount"]?.GetValue<int>() == 3,
            $"the documentation track carries the drawing link and label; the database track its date; three devices ({c1?["DocumentationLink"]}, {c1?["DocumentationRevisionLabel"]}, {c1?["DeviceCount"]})");
        Must(c1?["WorkTypeKey"]?.ToString() == $"{tag}_SETTINGS_CHANGE" && c1?["RequestedByDisplayName"]?.ToString() == "Admin Smoke" && c1?["StationName"]?.ToString() == $"{tag} station",
            $"action type, requested-by and location on the request ({c1?["WorkTypeKey"]}, {c1?["RequestedByDisplayName"]}, {c1?["StationName"]})");
        var (c2s, c2b) = await Get(admin, $"api/v1/work/vChangeRequestStatus?WorkRequestEntityId={Id(wr2b)}");
        var c2 = (c2b?["rows"] as JsonArray)?.FirstOrDefault();
        Must(c2?["RequestState"]?.ToString() == "InProgress" && c2?["DocumentationStatus"]?.ToString() == "Not Started" && c2?["LifecycleState"]?.ToString() == "Calculated",
            $"the second request is In progress with its tracks Not Started and its package Calculated ({c2?["RequestState"]}, {c2?["DocumentationStatus"]}, {c2?["LifecycleState"]})");
        // §10 row 8: Close refused while the run is half-way; Cancel with a reason on a third request
        var (cl2s, cl2b) = await Post(admin, $"api/v1/process/workflow-instances/{Id(sw2b, "workflowInstanceEntityId")}/transitions", new { name = "Close" });
        Must(cl2s == HttpStatusCode.Conflict, $"Close on the half-run request → 409 in the rule's words ({Short(cl2b)})");
        var (wr3s, wr3b) = await Post(admin, "api/v1/work/WorkRequest_Add", new { WorkTypeDefinitionVersionRowId = workType, Title = $"{tag} third change (cancelled)", ScopeKind = "Asset", ScopeEntityId = devBdd });
        var (sw3s, sw3b) = await Post(admin, "api/v1/process/workflows/start", new { workflowKey = "SETTINGS_CHANGE_REQUEST", subjectKind = "WorkRequest", subjectEntityId = Id(wr3b) });
        var (cn3s, cn3b) = await Post(admin, $"api/v1/process/workflow-instances/{Id(sw3b, "workflowInstanceEntityId")}/transitions", new { name = "Cancel", reason = "W6 smoke: raised in error" });
        var (c3s, c3b) = await Get(admin, $"api/v1/work/vChangeRequestStatus?WorkRequestEntityId={Id(wr3b)}");
        var c3 = (c3b?["rows"] as JsonArray)?.FirstOrDefault();
        Must(cn3s == HttpStatusCode.OK && c3?["RequestState"]?.ToString() == "Cancelled" && c3?["EquipmentName"]?.ToString() == $"{tag} BDD15B" && c3?["StationName"]?.ToString() == $"{tag} station",
            $"a third request on the BDD15B cancelled with a reason; its equipment and location resolved through the placement ({(int)cn3s} {c3?["RequestState"]}, {c3?["EquipmentName"]})");

        // §10 row 10: the FLOC view
        var (f1s, f1rows, f1ms) = await Timed(admin, $"api/v1/location/vFloc?StationNodeEntityId={station}");
        Must(f1s == HttpStatusCode.OK && f1rows.Count == 3 && f1rows.All(r => r?["PanelName"]?.ToString() == $"{tag} panel 1" && r?["StationNumber"]?.ToString() == stationNumber && r?["Functions"]?.ToString() == "87T" && (r?["SchemeNames"]?.ToString() ?? "").Contains("87T scheme")),
            $"vFloc by station: three positions with panel, station number, 87T and the scheme ({f1rows.Count}, {f1ms} ms)");
        Must(f1rows.Any(r => string.Equals(r?["InstalledAssetEntityId"]?.ToString(), devSel?.ToString(), StringComparison.OrdinalIgnoreCase) && r?["ModelCode"]?.ToString() == "SEL-421"), "the SEL-421 is the device installed at position 1");
        var (f2s, f2rows, f2ms) = await Timed(admin, $"api/v1/location/vFloc?PanelNodeEntityId={panel}");
        Must(f2s == HttpStatusCode.OK && f2rows.Count == 3, $"vFloc by panel: three positions ({f2ms} ms)");
        var (f3s, f3rows, f3ms) = await Timed(admin, $"api/v1/location/vFlocScheme?SchemeEntityId={scheme}");
        Must(f3s == HttpStatusCode.OK && f3rows.Count == 3 && f3rows.All(r => r?["MemberRoleCodes"]?.ToString() == "InitiatingDevice"), $"vFlocScheme by scheme: the three positions through their functions ({f3rows.Count}, {f3ms} ms)");
        var (f4s, f4b) = await Get(admin, $"api/v1/location/vFloc?ModelCode=SEL-421&take=500");
        Must(f4s == HttpStatusCode.OK && (f4b?["rows"] as JsonArray)?.Any(r => string.Equals(r?["NodeEntityId"]?.ToString(), positions[0]?.ToString(), StringComparison.OrdinalIgnoreCase)) == true, "vFloc by model: position 1 is among the SEL-421 positions");
        var (t1s, t1rows, t1ms) = await Timed(admin, $"api/v1/location/vNodeTree?ParentEntityId={panel}");
        Must(t1s == HttpStatusCode.OK && t1rows.Count == 3 && t1rows.All(r => r?["HasChildren"]?.GetValue<bool>() == false), $"vNodeTree under the panel: three positions, and the tree stops there — an element is no longer a node of its own (#181) ({t1ms} ms)");
        var (fh1s, fh1b) = await Get(hydro, $"api/v1/location/vFloc?StationNodeEntityId={station}");
        Must(fh1s == HttpStatusCode.OK && (fh1b?["rows"] as JsonArray)?.Count == 3, "the Hydro engineer reads the station's positions (Node family scope)");
        // W7 (#144): the file download — the STUDY step's evidence file comes back byte for byte, its SHA-256 as stored
        var (evr2, evb2) = await Get(admin, $"api/v1/record/vRecord?WorkRequestEntityId={wr}&RecordKindCode=Study&take=5");
        var studyRec = Id((evb2?["rows"] as JsonArray)?.FirstOrDefault());
        var (lks, lkb) = await Get(admin, $"api/v1/document/vRevisionLink?SubjectKind=Record&SubjectEntityId={studyRec}&take=5");
        var evRev = (lkb?["rows"] as JsonArray)?.FirstOrDefault()?["RevisionRowId"]?.ToString();
        var (fls, flb) = await Get(admin, $"api/v1/document/vFile?RevisionRowId={evRev}&take=5");
        var fileRow = (flb?["rows"] as JsonArray)?.FirstOrDefault();
        Must(fileRow is not null, $"the STUDY evidence file is listed ({fileRow?["FileName"]})");
        if (fileRow is not null)
        {
            var dl = await admin.GetAsync($"api/v1/files/{fileRow["RowId"]}");
            var bytes = await dl.Content.ReadAsByteArrayAsync();
            var sha = Convert.ToBase64String(System.Security.Cryptography.SHA256.HashData(bytes));
            Must(dl.StatusCode == HttpStatusCode.OK && System.Text.Encoding.UTF8.GetString(bytes) == "Fault level study — fixture" && sha == fileRow["Sha256"]?.ToString(),
                $"GET files/{{id}} → {(int)dl.StatusCode}, the bytes as uploaded, SHA-256 as the file row carries ({bytes.Length} bytes, {dl.Content.Headers.ContentType})");
            Must(dl.Content.Headers.ContentDisposition?.FileName?.Trim('"') == fileRow["FileName"]?.ToString(), $"the download names the file ({dl.Content.Headers.ContentDisposition?.FileName})");
            var dl2 = await readOnly!.GetAsync($"api/v1/files/{fileRow["RowId"]}");
            Must(dl2.StatusCode == HttpStatusCode.OK, $"ReadOnly (Document.Read, Global) may open it → {(int)dl2.StatusCode}");
            var (nfs, nfb) = await Get(admin, $"api/v1/files/{Guid.NewGuid()}");
            Must(nfs == HttpStatusCode.NotFound, $"an unknown file id → 404 ({Code(nfb)})");
        }
        // NFR-2: the list calls a screen makes, measured (warm)
        var (n1s, n1rows, n1ms) = await Timed(admin, "api/v1/document/vSettingsRecord?GridState=Active&take=500");
        var (n2s, n2rows, n2ms) = await Timed(admin, "api/v1/location/vNodeTree?ParentEntityId=null");
        Console.WriteLine($"  timings (ms, warm): grid Active {n1ms} ({n1rows.Count} rows) · request status {c1ms} · floc by station {f1ms} · by panel {f2ms} · by scheme {f3ms} · tree roots {n2ms}");
        Must(new[] { c1ms, f1ms, f2ms, f3ms, n2ms, t1ms, g1ms }.All(ms => ms < 1000), "NFR-2: every measured screen-sized list call under one second on DEV");
        // W7 (#145): the grid's Active list is the whole estate materialised before paging — 1.6–2.0 s measured; a sargable station is W8's
        Must(n1ms < 5000, $"NFR-2 (W8 round-2 item, #154): the whole-estate Active grid under five seconds — the state filter is applied in memory over the whole view ({n1ms} ms)");

        // ======== #170 (2026-09-16): the primary asset a scheme protects, and the applicability classifications recorded on it (not on the
        // relay — the owner's ruling). A line at the fixture station, the fixture scheme protects it, a CIP impact rating and an A-10 value
        // recorded by the engineer, withdrawn once, read back on the primary-asset read model; ReadOnly may not record.
        {
            var (la, lb) = await Post(admin, "api/v1/asset/Asset_Add", new { AssetTypeCode = "Line", Name = $"{tag} line 0001", Status = "InService" });
            var line = Id(lb);
            var (pa, pb) = await Post(admin, "api/v1/asset/AssetTerminal_Add", new { AssetEntityId = line, TerminalNo = 1, StationNodeEntityId = station });
            var (sa, sb) = await Post(admin, "api/v1/scheme/SchemeProtects_Add", new { SchemeEntityId = scheme, PrimaryAssetEntityId = line, ZoneRole = "Primary" });
            Must(la == HttpStatusCode.OK && line is not null && pa == HttpStatusCode.OK && sa == HttpStatusCode.OK, $"#170: a line created with the station as its terminal 1 and the scheme protects it ({(int)la} {Code(lb)} · {(int)pa} {Code(pb)} · {(int)sa} {Code(sb)})");
            var (pas, pab) = await Get(admin, $"api/v1/asset/vPrimaryAsset?EntityId={line}");
            var prow = (pab?["rows"] as JsonArray)?.FirstOrDefault();
            Must(pas == HttpStatusCode.OK && prow?["AssetTypeCode"]?.ToString() == "Line" && (prow?["TerminalNodeIds"]?.ToString() ?? "").Contains(station.ToString()!, StringComparison.OrdinalIgnoreCase) && prow?["Classifications"] is null,
                $"#170: the primary-asset read model shows the line with its terminal and no classification yet ({prow?["AssetTypeName"]}, terminals {prow?["Stations"]})");
            var (k1s, k1b) = await Post(hydro!, "api/v1/asset/RecordClassification", new { SubjectKind = "Asset", SubjectEntityId = line, ClassificationKindCode = "CipImpactRating", ClassificationValue = "Medium" });
            var (k2s, k2b) = await Post(admin, "api/v1/asset/RecordClassification", new { SubjectKind = "Asset", SubjectEntityId = line, ClassificationKindCode = "Prc023", ClassificationValue = "Listed" });   // #173: NPCC is a bus kind, so a line is listed for PRC-023 instead
            var (k3s, k3b) = await Post(admin, "api/v1/asset/RecordClassification", new { SubjectKind = "Asset", SubjectEntityId = line, ClassificationKindCode = "CipImpactRating", ClassificationValue = "High" });
            Must(k2s == HttpStatusCode.OK && k3s == HttpStatusCode.OK, $"#170: classifications recorded and revised as the Administrator ({(int)k2s} {Code(k2b)} · {(int)k3s} {Code(k3b)}); the subtree-scoped engineer → {(int)k1s} {Code(k1b)}");
            var (k4s, k4b) = await Post(readOnly!, "api/v1/asset/RecordClassification", new { SubjectKind = "Asset", SubjectEntityId = line, ClassificationKindCode = "Prc023", ClassificationValue = "Listed" });
            var (k5s, k5b) = await Post(admin, "api/v1/asset/RecordClassification", new { SubjectKind = "Asset", SubjectEntityId = line, ClassificationKindCode = "NoSuchKind", ClassificationValue = "x" });
            Must(k4s == HttpStatusCode.Forbidden && k5s == HttpStatusCode.Conflict, $"#170: ReadOnly may not record ({(int)k4s}); an unknown kind is refused in the procedure's words ({(int)k5s} {k5b?["detail"]})");
            var (k6s, _) = await Post(admin, "api/v1/asset/RecordClassification", new { SubjectKind = "Asset", SubjectEntityId = line, ClassificationKindCode = "Prc023", ClassificationValue = "" });
            var (kcls, kclb) = await Get(admin, $"api/v1/asset/vClassification?SubjectEntityId={line}");
            var crow = (kclb?["rows"] as JsonArray)?.ToDictionary(r => r?["ClassificationKindCode"]?.ToString() ?? "", r => r) ?? new();
            var (pas2, pab2) = await Get(admin, $"api/v1/asset/vPrimaryAsset?EntityId={line}");
            Must(k6s == HttpStatusCode.OK && crow.Count == 1 && crow.GetValueOrDefault("CipImpactRating")?["ClassificationValue"]?.ToString() == "High" && crow["CipImpactRating"]?["Basis"]?.ToString() == "Recorded"
                 && (pab2?["rows"] as JsonArray)?.FirstOrDefault()?["Classifications"]?.ToString() == "CipImpactRating=High",
                $"#170: one current classification after the PRC-023 listing was withdrawn — CIP High, Recorded, the read model summarises it ({(pab2?["rows"] as JsonArray)?.FirstOrDefault()?["Classifications"]})");
            var (his, hib) = await Get(admin, $"api/v1/asset/vClassificationHistory?SubjectEntityId={line}");
            Must(his == HttpStatusCode.OK && ((hib?["rows"] as JsonArray)?.Count ?? 0) >= 3, $"#170: the history keeps the revised and withdrawn values ({(hib?["rows"] as JsonArray)?.Count} rows)");
            var (sps, spb) = await Get(admin, $"api/v1/scheme/vSchemeProtects?SchemeEntityId={scheme}");
            Must(sps == HttpStatusCode.OK && (spb?["rows"] as JsonArray)?.Any(r => string.Equals(r?["PrimaryAssetEntityId"]?.ToString(), line.ToString(), StringComparison.OrdinalIgnoreCase)) == true, "#170: the scheme's protects link reads back (the device sheet's 'protects … via …' line)");
        }

        // ======== #176 (2026-09-17): attaching a protection to a panel a person has just built. The owner, having created a building and a
        // panel from the Locations screen, asked "how do I associate a protection with this panel?" — the chain is panel → device position →
        // protection function, with the relay PLACED at the position and the scheme naming that function as a member. Both writes existed as
        // procedures and had no screen; the screens are #176's work and these checks hold their behaviour: what the platform accepts, and the
        // refusals a person will actually meet, in the procedures' own words.
        {
            // a position of this fixture's own, so nothing already placed is disturbed
            var (k176_p1s, k176_p1b) = await Post(admin, "api/v1/location/AddNode", new { NodeTypeCode = "DevicePosition", ParentEntityId = panel, Name = $"{tag} spare position", Code = "POS9" });
            var k176_pos = Id(k176_p1b);
            var (k176_a1s, k176_a1b) = await Post(admin, "api/v1/asset/Asset_Add", new { AssetTypeCode = "ProtectiveRelay", Name = $"{tag} spare relay", ModelId = sel, Status = "InService" });
            var k176_relay = Id(k176_a1b);
            var (k176_d1s, _) = await Post(admin, "api/v1/device/Device_Add", new { EntityId = k176_relay, PartNumber = $"{tag} spare relay" });
            var (k176_pl1s, k176_pl1b) = await Post(admin, "api/v1/asset/PlaceAsset", new { AssetEntityId = k176_relay, NodeEntityId = k176_pos, PlacementKind = "Installed" });
            var (k176_fl1s, k176_fl1b) = await Get(admin, $"api/v1/location/vFloc?NodeEntityId={k176_pos}");
            var k176_placed = (k176_fl1b?["rows"] as JsonArray)?.FirstOrDefault();
            Must(k176_p1s == HttpStatusCode.OK && k176_a1s == HttpStatusCode.OK && k176_d1s == HttpStatusCode.OK && k176_pl1s == HttpStatusCode.OK
                 && string.Equals(k176_placed?["InstalledAssetEntityId"]?.ToString(), k176_relay.ToString(), StringComparison.OrdinalIgnoreCase),
                $"#176: a relay is placed at a position a person built, and the position then reads it back ({(int)k176_pl1s} {Code(k176_pl1b)} · {k176_placed?["InstalledAssetName"]})");

            // the refusals the screen must show in the procedure's own words
            var (k176_e1s, k176_e1b) = await Post(admin, "api/v1/asset/PlaceAsset", new { AssetEntityId = k176_relay, NodeEntityId = k176_pos, CustodyLocationEntityId = k176_pos, PlacementKind = "Installed" });
            var (k176_e2s, k176_e2b) = await Post(admin, "api/v1/asset/PlaceAsset", new { AssetEntityId = k176_relay, PlacementKind = "Installed" });
            Must(k176_e1s == HttpStatusCode.Conflict && k176_e2s == HttpStatusCode.Conflict,
                $"#176: a placement names exactly one of a node or a custody location — both refused ({(int)k176_e1s}), neither refused ({(int)k176_e2s} {k176_e2b?["detail"]})");

            // a scheme's members are functions, assets and channels, never devices: a relay swap must leave the scheme intact
            var (k176_m1s, k176_m1b) = await Post(admin, "api/v1/scheme/AddSchemeMember", new { SchemeEntityId = scheme, MemberKind = "Device", MemberEntityId = k176_relay, MemberRoleCode = "Member" });
            var (k176_m2s, k176_m2b) = await Post(admin, "api/v1/scheme/AddSchemeMember", new { SchemeEntityId = scheme, MemberKind = "ProtectionFunction", MemberEntityId = k176_relay, MemberRoleCode = "Member" });
            Must(k176_m1s != HttpStatusCode.OK && k176_m2s == HttpStatusCode.Conflict,
                $"#176: a scheme takes functions, assets and channels and never a device ({(int)k176_m1s}), and a member kind must name a thing of that kind ({(int)k176_m2s} {k176_m2b?["detail"]})");

            // the relay at the new position joins the scheme in a role, then is withdrawn again (#181: a scheme names the
            // relay, because the element is no longer a node of its own)
            var (k176_m3s, k176_m3b) = await Post(admin, "api/v1/scheme/AddSchemeMember", new { SchemeEntityId = scheme, MemberKind = "Asset", MemberEntityId = k176_relay, MemberRoleCode = "TripCircuit" });
            var k176_member = Id(k176_m3b);
            var (k176_v1s, k176_v1b) = await Get(admin, $"api/v1/scheme/vSchemeMember?SchemeEntityId={scheme}");
            var k176_before = (k176_v1b?["rows"] as JsonArray)?.Count ?? 0;
            var (k176_r1s, k176_r1b) = await Post(admin, "api/v1/scheme/SchemeMember_SoftDelete", new { EntityId = k176_member });
            var (k176_v2s, k176_v2b) = await Get(admin, $"api/v1/scheme/vSchemeMember?SchemeEntityId={scheme}");
            var k176_after = (k176_v2b?["rows"] as JsonArray)?.Count ?? 0;
            Must(k176_m3s == HttpStatusCode.OK && k176_r1s == HttpStatusCode.OK && k176_after == k176_before - 1,
                $"#176: the relay at the position joins the scheme in a role and can be withdrawn again ({(int)k176_m3s} {Code(k176_m3b)} · {k176_before} → {k176_after} members)");

            // ReadOnly may do neither
            var (k176_q1s, _) = await Post(readOnly!, "api/v1/asset/PlaceAsset", new { AssetEntityId = k176_relay, NodeEntityId = k176_pos, PlacementKind = "Installed" });
            var (k176_q2s, _) = await Post(readOnly!, "api/v1/scheme/AddSchemeMember", new { SchemeEntityId = scheme, MemberKind = "Asset", MemberEntityId = k176_relay, MemberRoleCode = "Member" });
            Must(k176_q1s == HttpStatusCode.Forbidden && k176_q2s == HttpStatusCode.Forbidden,
                $"#176: ReadOnly places nothing ({(int)k176_q1s}) and joins nothing to a scheme ({(int)k176_q2s})");

            // the chooser that finds the relay to place: a filter named with a trailing '~' searches a text column for the
            // value ANYWHERE inside it. Without it a person would have to type an asset's recorded name exactly, which
            // nobody knows — the registry holds names like "SEL-221F 3445 Z1-3". The wildcards are escaped, so a term
            // containing a per cent sign searches for that character rather than matching everything; and only a text
            // column can be searched, because "inside" means nothing to a number or an instant.
            var k176_frag = tag[^6..] + " spare";
            var (k176_s1s, k176_s1b) = await Get(admin, $"api/v1/asset/vAsset?Name~={Uri.EscapeDataString(k176_frag)}&take=50");
            var k176_hits = k176_s1b?["rows"] as JsonArray;
            var k176_found = k176_hits?.Any(r => string.Equals(r?["EntityId"]?.ToString(), k176_relay.ToString(), StringComparison.OrdinalIgnoreCase)) ?? false;
            var (k176_s2s, k176_s2b) = await Get(admin, $"api/v1/asset/vAsset?Name~={Uri.EscapeDataString("% spare relay")}&take=50");
            var k176_wild = (k176_s2b?["rows"] as JsonArray)?.Count ?? -1;
            var (k176_s3s, k176_s3b) = await Get(admin, "api/v1/asset/vAsset?EntityId~=3445&take=5");
            Must(k176_s1s == HttpStatusCode.OK && k176_found && k176_s2s == HttpStatusCode.OK && k176_wild == 0
                 && k176_s3s == HttpStatusCode.BadRequest && Code(k176_s3b) == "not_searchable",
                $"#176: the chooser finds a relay by any part of its name “{k176_frag}” ({k176_hits?.Count} of the registry), the LIKE wildcards are escaped so a per cent sign is a character and not everything ({k176_wild} rows), and only a text column may be searched ({(int)k176_s3s} {Code(k176_s3b)})");
        }

        // ======== #175 (2026-09-17): a code on every location node, and the FLOC composed from those codes. The owner's FLOC is a path of
        // short codes — TN-4403-Y230-T3 is the Transmission division, station 4403, the 230 kV yard, transformer T3 — and the last segment
        // is the tag painted on the equipment. A node carries its own Code; the platform composes FlocCode and never lets a person type it,
        // so it stays true when a node is renamed or moved. The chain is the unbroken run of coded ancestors ending at the node: a node
        // with no code has no FLOC at all, and a node whose parent has none starts a fresh chain rather than inventing the missing part.
        // (The fixture's division is a seeded node shared with other checks, so it is left uncoded here — which is exactly the case that
        // proves the chain starts at the first coded ancestor.)
        {
            async Task<JsonNode?> Floc(Guid? id) => (await Get(admin, $"api/v1/location/vNode?EntityId={id}")).body?["rows"]?[0];
            var (k175_s1s, k175_s1b) = await Post(admin, "api/v1/location/RenameNode", new { EntityId = station, Name = $"{tag} station", Code = stationNumber });
            var (k175_y1s, k175_y1b) = await Post(admin, "api/v1/location/AddNode", new { NodeTypeCode = "Yard", ParentEntityId = station, Name = "230 kV yard", Code = "Y230" });
            var k175_yard = Id(k175_y1b);
            var (k175_t1s, k175_t1b) = await Post(admin, "api/v1/location/AddNode", new { NodeTypeCode = "EquipmentPosition", ParentEntityId = k175_yard, Name = "Transformer T3", Code = "T3" });
            var k175_t3 = Id(k175_t1b);
            var k175_sRow = await Floc(station); var k175_yRow = await Floc(k175_yard); var k175_tRow = await Floc(k175_t3);
            Must(k175_s1s == HttpStatusCode.OK && k175_y1s == HttpStatusCode.OK && k175_t1s == HttpStatusCode.OK
                 && k175_sRow?["FlocCode"]?.ToString() == stationNumber && k175_yRow?["FlocCode"]?.ToString() == $"{stationNumber}-Y230" && k175_tRow?["FlocCode"]?.ToString() == $"{stationNumber}-Y230-T3"
                 && k175_tRow?["Name"]?.ToString() == "Transformer T3" && k175_tRow?["Code"]?.ToString() == "T3",
                $"#175: the FLOC composes down the tree from the first coded ancestor — station {k175_sRow?["FlocCode"]}, yard {k175_yRow?["FlocCode"]}, transformer {k175_tRow?["FlocCode"]}, whose name stays descriptive ({k175_tRow?["Name"]})");

            // a code is one segment: the separator and whitespace are refused, and one parent's children may not share a code
            var (k175_e1s, k175_e1b) = await Post(admin, "api/v1/location/AddNode", new { NodeTypeCode = "EquipmentPosition", ParentEntityId = k175_yard, Name = "bad", Code = "T-4" });
            var (k175_e2s, _) = await Post(admin, "api/v1/location/AddNode", new { NodeTypeCode = "EquipmentPosition", ParentEntityId = k175_yard, Name = "bad", Code = "T 4" });
            var (k175_e3s, _) = await Post(admin, "api/v1/location/AddNode", new { NodeTypeCode = "EquipmentPosition", ParentEntityId = k175_yard, Name = "another T3", Code = "T3" });
            Must(k175_e1s == HttpStatusCode.Conflict && k175_e2s == HttpStatusCode.Conflict && k175_e3s != HttpStatusCode.OK,
                $"#175: a code is one segment — the separator is refused ({(int)k175_e1s} {k175_e1b?["detail"]}), so is a space ({(int)k175_e2s}), and a sibling may not repeat one ({(int)k175_e3s})");
            // #177 (2026-09-17): a duplicate code is refused in the platform's words, naming the node that holds it. The
            // owner met SQL Server's instead — "Cannot insert duplicate key row ... unique index 'UX_Node_ParentCode'.
            // The duplicate key value is (20d4c714-..., 4416)" — which names neither the code nor the station holding it.
            var (k177_d1s, k177_d1b) = await Post(admin, "api/v1/location/AddNode", new { NodeTypeCode = "EquipmentPosition", ParentEntityId = k175_yard, Name = "another T3", Code = "T3" });
            var k177_msg = k177_d1b?["detail"]?.ToString() ?? "";
            // and saving a node without changing its code is not a collision with itself
            var (k177_s1s, _) = await Post(admin, "api/v1/location/RenameNode", new { EntityId = k175_t3, Name = "Transformer T3", Code = "T3" });
            Must(k177_d1s == HttpStatusCode.Conflict && k177_msg.Contains("already used by") && k177_msg.Contains("Transformer T3")
                 && !k177_msg.Contains("UX_Node_") && k177_s1s == HttpStatusCode.OK,
                $"#177: a duplicate code names the node that holds it ({(int)k177_d1s} {k177_msg}), and a node keeping its own code is not a collision with itself ({(int)k177_s1s})");

            // ======== #179 (2026-09-17): the settings book lists BUILDINGS, not stations. The owner, having found that the legacy
            // LOCATION was a building all along (#178): "It would be helpful for the engineers and techs if the 'Locations' list
            // box at the left, actually displayed the BDGx Names and filtered the data on those." So document.vSettingsRecord
            // carries the building the device stands in, read off the same ancestors the station is read off, and the screen
            // filters on it. A station with one building answers the same either way — which is what keeps every other
            // location reading as it always did.
            var (k179_a1s, k179_a1b) = await Get(admin, $"api/v1/document/vSettingsRecord?GridState=Active&StationNodeEntityId={station}&take=500");
            var k179_byStation = (k179_a1b?["rows"] as JsonArray) ?? [];
            var k179_bld = k179_byStation.FirstOrDefault()?["BuildingNodeEntityId"]?.ToString();
            var (k179_a2s, k179_a2b) = await Get(admin, $"api/v1/document/vSettingsRecord?GridState=Active&BuildingNodeEntityId={k179_bld}&take=500");
            var k179_byBuilding = (k179_a2b?["rows"] as JsonArray) ?? [];
            var k179_named = k179_byBuilding.All(r => !string.IsNullOrWhiteSpace(r?["BuildingName"]?.ToString()));
            Must(k179_a1s == HttpStatusCode.OK && k179_a2s == HttpStatusCode.OK && k179_bld is not null
                 && k179_byBuilding.Count == k179_byStation.Count && k179_byStation.Count > 0 && k179_named,
                $"#179: a settings record names the building it stands in, and a station with one building answers the same by either ({k179_byStation.Count} by station, {k179_byBuilding.Count} by building, named {k179_named})");

            // ======== #180 (2026-09-17): the FLOC stops at the position the device stands in. The owner: "I believe that the
            // device FLOC should stop at TN-4134-BDG1-PNL12-21A and that FLOC position should be assigned to the device
            // (SEL-411L etc.)". His client shortened the tag on purpose so schematic drawings would not get busy, and everyone
            // there knows a 21 element covers more than distance. The elements are still recorded — a scheme's members ARE
            // protection functions, which is what lets a relay be swapped without touching the scheme — they simply carry no
            // code and so appear in no tag. Refused by the platform, not merely hidden on a screen.
            var (k180_p0s, k180_p0b) = await Post(admin, "api/v1/location/AddNode", new { NodeTypeCode = "DevicePosition", ParentEntityId = panel, Name = $"{tag} 21A", Code = "21A" });
            var k180_pos = Id(k180_p0b);
            // #181: a protection function is no longer a node at all, so nothing below the position can be built to carry
            // a tag. The element is recorded AT the position instead, by the checklist below.
            var (k180_e1s, k180_e1b) = await Post(admin, "api/v1/location/AddNode", new { NodeTypeCode = "ProtectionFunction", ParentEntityId = k180_pos, Name = "21 distance" });
            var (k180_p1s, k180_p1b) = await Get(admin, $"api/v1/location/vNode?EntityId={k180_pos}");
            var k180_posFloc = (k180_p1b?["rows"] as JsonArray)?.FirstOrDefault()?["FlocCode"]?.ToString();
            var (k180_t1s, k180_t1b) = await Get(admin, "api/v1/ref/vLocationNodeTypeParent?ParentNodeTypeCode=DevicePosition&take=20");
            var k180_offered = ((k180_t1b?["rows"] as JsonArray) ?? []).Where(r => r?["IsActive"]?.ToString() is "true" or "True" or "1").Select(r => r?["ChildNodeTypeCode"]?.ToString()).ToList();
            Must(k180_p0s == HttpStatusCode.OK && k180_e1s != HttpStatusCode.OK && !k180_offered.Contains("ProtectionFunction")
                 && !string.IsNullOrWhiteSpace(k180_posFloc),
                $"#180/#181: the tag ends at the position ({k180_posFloc}) and nothing may be built below it to extend one — a protection function is refused ({(int)k180_e1s}) and is not offered ({string.Join(", ", k180_offered)})");

            // ======== #181 (2026-09-17): what a relay CAN do comes from its model, from the manual; what it DOES here is
            // ticked at the position. The owner: "lets build the checklist on the device instead, you can build the list
            // from the devices manual... an admin would create an SEL-221F device template with all the possible
            // capabilities so that when the user selects the device to add to a panel it will populate". Nothing had ever
            // written a scheme.FunctionCapability row; the table was designed for exactly this (SCHEMA-DESIGN 7.3).
            // The owner also ruled what a newly placed relay starts with: "If a new device is added, none ticked".
            // the model is looked up by code, not by a fixed id: the migration may already have created the row, in which
            // case the template seed binds to that one rather than to the id it would otherwise use
            var (k181_m0s, k181_m0b) = await Get(admin, "api/v1/ref/vModel?ModelCode=SEL-221F&take=5");
            var k181_model = (k181_m0b?["rows"] as JsonArray)?.FirstOrDefault()?["ModelId"]?.ToString();
            var (k181_c1s, k181_c1b) = await Get(admin, $"api/v1/scheme/vFunctionCapability?ModelId={k181_model}&take=50");
            var k181_caps = ((k181_c1b?["rows"] as JsonArray) ?? []).Select(r => r?["AnsiCode"]?.ToString()).OrderBy(x => x).ToList();
            var k181_want = new[] { "21", "25", "27", "32Q", "50", "50BF", "50N", "51N", "59", "67N", "79", "FAULTLOC", "LOP", "REJO", "SOTF" }.OrderBy(x => x).ToList();
            Must(k181_m0s == HttpStatusCode.OK && k181_model is not null && k181_c1s == HttpStatusCode.OK && k181_caps.SequenceEqual(k181_want),
                $"#181/#182: the SEL-221F's capability list is the manual's fifteen elements, five of them named in words because the manual prints no device number ({string.Join(", ", k181_caps)})");

            // none ticked at a position until someone ticks one, then it reads back with the element's name
            var (k181_n0s, k181_n0b) = await Get(admin, $"api/v1/scheme/vPositionFunction?PositionNodeEntityId={k180_pos}&take=20");
            var k181_before = (k181_n0b?["rows"] as JsonArray)?.Count ?? -1;
            var (k181_t1s, k181_t1b) = await Post(admin, "api/v1/scheme/CommissionedFunction_Add", new { ProtectionFunctionNodeEntityId = k180_pos, AnsiCode = "21", IsPrincipal = true });
            var k181_row1 = Id(k181_t1b);
            var (k181_t2s, _) = await Post(admin, "api/v1/scheme/CommissionedFunction_Add", new { ProtectionFunctionNodeEntityId = k180_pos, AnsiCode = "51N" });
            var (k181_d1s, k181_d1b) = await Post(admin, "api/v1/scheme/CommissionedFunction_Add", new { ProtectionFunctionNodeEntityId = k180_pos, AnsiCode = "21" });
            var (k181_n1s, k181_n1b) = await Get(admin, $"api/v1/scheme/vPositionFunction?PositionNodeEntityId={k180_pos}&take=20");
            var k181_now = (k181_n1b?["rows"] as JsonArray) ?? [];
            var k181_named = k181_now.FirstOrDefault(r => r?["AnsiCode"]?.ToString() == "21")?["AnsiName"]?.ToString();
            Must(k181_before == 0 && k181_t1s == HttpStatusCode.OK && k181_t2s == HttpStatusCode.OK
                 && k181_d1s != HttpStatusCode.OK && k181_now.Count == 2 && k181_named == "Distance relay",
                $"#181: a new position starts with nothing ticked ({k181_before}), ticking records the element by name ({k181_named}), and one element is ticked once ({(int)k181_d1s})");

            // untick, and ReadOnly may tick nothing
            var (k181_u1s, _) = await Post(admin, "api/v1/scheme/CommissionedFunction_SoftDelete", new { EntityId = k181_row1 });
            var (k181_n2s, k181_n2b) = await Get(admin, $"api/v1/scheme/vPositionFunction?PositionNodeEntityId={k180_pos}&take=20");
            var k181_after = (k181_n2b?["rows"] as JsonArray)?.Count ?? -1;
            var (k181_q1s, _) = await Post(readOnly!, "api/v1/scheme/CommissionedFunction_Add", new { ProtectionFunctionNodeEntityId = k180_pos, AnsiCode = "79" });
            Must(k181_u1s == HttpStatusCode.OK && k181_after == 1 && k181_q1s == HttpStatusCode.Forbidden,
                $"#181: unticking withdraws the element (2 — 1 = {k181_after}) and ReadOnly ticks nothing ({(int)k181_q1s})");

            // the migrated estate moved with it: every commissioned element names a position, not a node of its own.
            // (A protection-function node an earlier smoke run left inside a fixture scheme is left standing on purpose:
            // the repoint never retires a node a scheme member still names.)
            var (k181_m1s, k181_m1b) = await Get(admin, "api/v1/location/vNode?NodeTypeCode=ProtectionFunction&take=5000");
            var k181_nodes = ((k181_m1b?["rows"] as JsonArray) ?? []).Select(r => r?["EntityId"]?.ToString()?.ToLowerInvariant()).ToHashSet();
            var (k181_m2s, k181_m2b) = await Get(admin, "api/v1/scheme/vPositionFunction?take=5000");
            var k181_onNode = ((k181_m2b?["rows"] as JsonArray) ?? []).Count(r => k181_nodes.Contains(r?["PositionNodeEntityId"]?.ToString()?.ToLowerInvariant()));
            Must(k181_m1s == HttpStatusCode.OK && k181_m2s == HttpStatusCode.OK && k181_onNode == 0,
                $"#181: every commissioned element in the estate names a position, none a node of its own ({k181_onNode} on a node)");

            // ======== #185 (2026-09-18): reachable from the nav, and compliance out of the template. The owner: "we must always
            // build in an intuitive way for the users to find this functionality... I was expecting to see a Templates tab on
            // the left hand side"; and "compliance is really a function of it's own, outside of the template". So a Templates
            // menu lists the templates and a Compliance menu lists the standards and the rules, and the template carries neither.
            var (k185_t1s, k185_t1b) = await Get(readOnly!, "api/v1/config/vAssetTemplate?DefinitionKey=SEL221F_Template&take=10");
            var k185_tmpl = (k185_t1b?["rows"] as JsonArray) ?? [];
            var (k185_r1s, k185_r1b) = await Get(readOnly!, "api/v1/compliance/vRequirementDetail?StandardCode=NPCC-D4&take=100");
            // #194 (2026-09-19): the eight legacy classification fields are gone — the template's Effective version has no Classification
            // group and a migrated record's summary no longer carries CLASS=
            var (k194_ds, k194_db) = await Get(readOnly!, "api/v1/config/vDefinition?DefinitionKind=CharacteristicSchema.RecordTemplate&DefinitionKey=SETTINGS_RECORD&take=1");
            var (k194_rs, k194_rb) = await Get(admin, "api/v1/record/vRecord?RecordKindCode=ConfigurationFileRevision&take=200");
            var k194_class = (k194_rb?["rows"] as JsonArray)?.Count(r => (r?["Summary"]?.ToString() ?? "").Contains("CLASS=")) ?? -1;
            // #206 (2026-09-20): the SETTINGS_RECORD schema itself is retired — the CT/PT strings became the scheme's transformers
            Must(k194_ds == HttpStatusCode.OK && ((k194_db?["rows"] as JsonArray)?.Count ?? -1) == 0 && k194_rs == HttpStatusCode.OK && k194_class == 0,
                $"#194/#206: the SETTINGS_RECORD characteristic schema is retired ({(k194_db?["rows"] as JsonArray)?.Count} readable); no migrated summary carries CLASS= ({k194_class} of {(k194_rb?["rows"] as JsonArray)?.Count})");
            // 2026-09-19: the schema smoke withdraws its own standards; none of its "smoke" subjects is on the Standards list
            var (k193_ss, k193_sb) = await Get(readOnly!, "api/v1/compliance/vRequirementDetail?Subject=smoke&take=10");
            Must(k193_ss == HttpStatusCode.OK && ((k193_sb?["rows"] as JsonArray)?.Count ?? -1) == 0, $"the Standards list carries no smoke-fixture standard ({(k193_sb?["rows"] as JsonArray)?.Count})");
            var k185_d4 = (k185_r1b?["rows"] as JsonArray)?.Count ?? -1;
            var k185_menus = new Dictionary<string, string>();
            foreach (var key in new[] { "DEVICE_TEMPLATES", "STANDARDS", "OBLIGATION_RULES" })
            {
                var (ds, db) = await Get(admin, $"api/v1/config/vDefinition?DefinitionKind=Program.Screen&DefinitionKey={key}&take=1");
                var d = (db?["rows"] as JsonArray)?.FirstOrDefault();
                var (vs, vb) = await Get(admin, $"api/v1/config/vDefinitionVersion?DefinitionEntityId={d?["EntityId"]}&Status=Effective&take=1");
                var payload = (vb?["rows"] as JsonArray)?.FirstOrDefault()?["PayloadText"]?.ToString() ?? "";
                var m = System.Text.RegularExpressions.Regex.Match(payload, "\"group\":\"([^\"]+)\"");
                k185_menus[key] = ds == HttpStatusCode.OK && d is not null && vs == HttpStatusCode.OK && m.Success ? m.Groups[1].Value : "(no menu)";
            }
            Must(k185_t1s == HttpStatusCode.OK && k185_tmpl.Count == 2 && k185_tmpl.All(r => r?["ModelCode"]?.ToString()?.Contains("221F") == true)
                 && k185_r1s == HttpStatusCode.OK && k185_d4 == 23
                 && k185_menus["DEVICE_TEMPLATES"] == "Templates" && k185_menus["STANDARDS"] == "Compliance" && k185_menus["OBLIGATION_RULES"] == "Compliance",
                $"#185: the Templates menu lists SEL221F_Template for both its models ({k185_tmpl.Count}), the Compliance menu lists Directory 4's {k185_d4} criteria, and the three screens carry their menus ({string.Join(", ", k185_menus.Select(x => x.Key + "=" + x.Value))})");


            // the FLOC follows a code change, for the node and everything beneath it
            var (k175_r1s, k175_r1b) = await Post(admin, "api/v1/location/RenameNode", new { EntityId = k175_yard, Name = "230 kV yard (HQ side)", Code = "Y230HQ" });
            var k175_tRow2 = await Floc(k175_t3);
            Must(k175_r1s == HttpStatusCode.OK && k175_tRow2?["FlocCode"]?.ToString() == $"{stationNumber}-Y230HQ-T3",
                $"#175: changing the yard's code rewrites the FLOC of everything beneath it — the transformer is now {k175_tRow2?["FlocCode"]} ({(int)k175_r1s} {Code(k175_r1b)})");

            // an untagged node has no FLOC at all; a node whose parent loses its code starts a fresh chain, never inventing the missing part
            var (k175_u1s, k175_u1b) = await Post(admin, "api/v1/location/AddNode", new { NodeTypeCode = "EquipmentPosition", ParentEntityId = k175_yard, Name = "not yet tagged" });
            var k175_uRow = await Floc(Id(k175_u1b));
            var (k175_c1s, _) = await Post(admin, "api/v1/location/RenameNode", new { EntityId = k175_yard, Name = "230 kV yard (HQ side)", Code = "" });
            var k175_yRow3 = await Floc(k175_yard); var k175_tRow3 = await Floc(k175_t3);
            Must(k175_u1s == HttpStatusCode.OK && k175_uRow?["FlocCode"] is null && k175_c1s == HttpStatusCode.OK
                 && k175_yRow3?["FlocCode"] is null && k175_tRow3?["FlocCode"]?.ToString() == "T3",
                $"#175: an untagged node has no FLOC ({k175_uRow?["FlocCode"] ?? "none"}); withdrawing the yard's code leaves the yard with none ({k175_yRow3?["FlocCode"] ?? "none"}) and restarts the chain below it ({k175_tRow3?["FlocCode"]}) rather than inventing the missing segment");

            // the migrated stations carry their station number as their code (Seed_location_StationCodes)
            var (k175_m1s, k175_m1b) = await Get(admin, "api/v1/location/vNode?NodeTypeCode=Station&take=500");
            var k175_rows = k175_m1b?["rows"] as JsonArray;
            var k175_coded = k175_rows?.Count(r => !string.IsNullOrWhiteSpace(r?["Code"]?.ToString())) ?? 0;
            Must(k175_m1s == HttpStatusCode.OK && k175_coded >= 240,
                $"#175: the migrated stations carry their station number as their code ({k175_coded} of {k175_rows?.Count} stations)");
        }

        // ======== #171 (2026-09-16) and #173 (2026-09-17): classifications and compliance, as the owner corrected them on seeing it.
        // Applicability is the asset type's: a bus is not PRC-023 applicable and carries no rating. The BES Cyber Asset flag is not a
        // person's entry but a derivation — a programmable device (Microprocessor or IEC61850) protecting a BES element — so the
        // SEL-421 becomes a BCA and the electromechanical BDD15B does not, and no CIP standard binds the BDD15B at all. The CIP impact
        // rating is the location's: recorded on the building the device is in, and the nearest classified ancestor rules, so a value on
        // the building beats one on the station. PRC-023 R1 opens on the 230 kV terminal with its criterion recorded.
        {
            var k173_line = Id((await Get(admin, $"api/v1/asset/vPrimaryAsset?Name={Uri.EscapeDataString($"{tag} line 0001")}")).body?["rows"]?[0]);
            var (k173_bas, k173_bab) = await Post(admin, "api/v1/asset/Asset_Add", new { AssetTypeCode = "Bus", Name = $"{tag} 230 kV bus", Status = "InService" });
            var k173_bus = Id(k173_bab);

            // (a) a rating belongs to a circuit: the line carries one, the bus does not, ReadOnly may not enter one
            var (k173_r1s, k173_r1b) = await Post(admin, "api/v1/asset/RecordAssetRating", new { AssetEntityId = k173_line, RatingKind = "FourHour", Season = "Summer", Amperes = 1000, Source = "smoke fixture" });
            var (k173_r2s, k173_r2b) = await Post(admin, "api/v1/asset/RecordAssetRating", new { AssetEntityId = k173_line, RatingKind = "FourHour", Season = "Winter", Amperes = 1200, Source = "smoke fixture" });
            var (k173_r3s, _) = await Post(readOnly!, "api/v1/asset/RecordAssetRating", new { AssetEntityId = k173_line, RatingKind = "FifteenMinute", Season = "All", Amperes = 1500 });
            var (k173_r4s, k173_r4b) = await Post(admin, "api/v1/asset/RecordAssetRating", new { AssetEntityId = k173_bus, RatingKind = "FourHour", Season = "Summer", Amperes = 1000 });
            var (k173_rvs, k173_rvb) = await Get(admin, $"api/v1/asset/vAssetRatingDetail?AssetEntityId={k173_line}");
            Must(k173_bas == HttpStatusCode.OK && k173_r1s == HttpStatusCode.OK && k173_r2s == HttpStatusCode.OK && k173_r3s == HttpStatusCode.Forbidden
                 && k173_r4s == HttpStatusCode.Conflict && (k173_rvb?["rows"] as JsonArray)?.Count == 2,
                $"#173: the line carries two seasonal 4-hour ratings, a bus carries none ({(int)k173_r4s} {k173_r4b?["detail"]}), ReadOnly is refused ({(int)k173_r3s}); {(k173_rvb?["rows"] as JsonArray)?.Count} read back");

            // (b) PRC-023 is a circuit's standard: the line may be listed, the bus may not
            var (k173_p1s, k173_p1b) = await Post(admin, "api/v1/asset/RecordClassification", new { SubjectKind = "Asset", SubjectEntityId = k173_bus, ClassificationKindCode = "Prc023", ClassificationValue = "Listed" });
            var (k173_p2s, k173_p2b) = await Post(admin, "api/v1/asset/RecordClassification", new { SubjectKind = "Asset", SubjectEntityId = k173_line, ClassificationKindCode = "Prc023", ClassificationValue = "Listed" });
            Must(k173_p1s == HttpStatusCode.Conflict && k173_p2s == HttpStatusCode.OK,
                $"#173: PRC-023 does not apply to a bus ({(int)k173_p1s} {k173_p1b?["detail"]}) and does to a line ({(int)k173_p2s} {Code(k173_p2b)})");

            // (c) the BES Cyber Asset flag is derived, never recorded; its inputs are recorded instead
            var (k173_h1s, k173_h1b) = await Post(admin, "api/v1/asset/RecordClassification", new { SubjectKind = "Asset", SubjectEntityId = devSel, ClassificationKindCode = "BesCyberAsset", ClassificationValue = "BCA" });
            var (k173_b1s, _) = await Post(admin, "api/v1/asset/RecordClassification", new { SubjectKind = "Asset", SubjectEntityId = k173_line, ClassificationKindCode = "BesStatus", ClassificationValue = "BES" });
            var (k173_c1s, _) = await Post(admin, "api/v1/asset/RecordClassification", new { SubjectKind = "Node", SubjectEntityId = building, ClassificationKindCode = "CipImpactRating", ClassificationValue = "Medium" });
            var (k173_v1s, k173_v1b) = await Post(admin, "api/v1/compliance/evaluate", new { subjectEntityId = devSel, mode = "Preview" });
            var k173_d1 = (k173_v1b?["derivations"] as JsonArray)?.FirstOrDefault(d => d?["kind"]?.ToString() == "BesCyberAsset");
            var (k173_cl0s, k173_cl0b) = await Get(admin, $"api/v1/asset/vClassification?SubjectEntityId={devSel}");
            Must(k173_h1s == HttpStatusCode.Conflict && k173_b1s == HttpStatusCode.OK && k173_c1s == HttpStatusCode.OK && k173_v1s == HttpStatusCode.OK
                 && k173_d1?["value"]?.ToString() == "BCA" && ((k173_cl0b?["rows"] as JsonArray)?.Count ?? -1) == 0,
                $"#173: a person may not record the BES Cyber Asset flag ({(int)k173_h1s} {k173_h1b?["detail"]}); the preview derives it BCA for the microprocessor relay and writes nothing ({k173_d1?["value"]} · {k173_d1?["reason"]} · {(k173_cl0b?["rows"] as JsonArray)?.Count} rows)");

            // #197: from here the SEL-421 also carries a phase-distance element in service (21) beside its 87T — PRC-023 binds a relay
            // only through a load-responsive element (Attachment A); the grid and FLOC checks above saw the position as the fixture placed it
            var (k197_cfs, k197_cfb) = await Post(admin, "api/v1/scheme/CommissionedFunction_Add", new { ProtectionFunctionNodeEntityId = positions[0], AnsiCode = "21" });
            Must(k197_cfs == HttpStatusCode.OK, $"#197: 21 commissioned beside 87T at position 1 ({(int)k197_cfs} {Code(k197_cfb)} {k197_cfb?["detail"]})");
            // (d) committed: the derived flag is written with Basis Derived, and the standards that bind open
            var k173_term = Id((await Get(admin, $"api/v1/asset/vAssetTerminalDetail?AssetEntityId={k173_line}")).body?["rows"]?[0], "TerminalEntityId");
            var (k173_t1s, _) = await Post(admin, "api/v1/asset/AssetTerminal_Revise", new { EntityId = k173_term, AssetEntityId = k173_line, TerminalNo = 1, StationNodeEntityId = station, VoltageClassCode = "230kV" });
            var (k173_e1s, k173_e1b) = await Post(admin, "api/v1/compliance/evaluate", new { subjectEntityId = devSel, mode = "Effective" });
            var (k173_cl1s, k173_cl1b) = await Get(admin, $"api/v1/asset/vClassification?SubjectEntityId={devSel}");
            var k173_bca = (k173_cl1b?["rows"] as JsonArray)?.FirstOrDefault(r => r?["ClassificationKindCode"]?.ToString() == "BesCyberAsset");
            var (k173_o1s, k173_o1b) = await Get(admin, $"api/v1/compliance/vObligationSubject?SubjectEntityId={devSel}");
            var k173_open = (k173_o1b?["rows"] as JsonArray)?.Where(r => r?["Status"]?.ToString() == "Open").ToList() ?? new();
            var k173_prc = k173_open.FirstOrDefault(r => r?["RuleDefinitionKey"]?.ToString() == "prc023_r1");
            Must(k173_t1s == HttpStatusCode.OK && k173_e1s == HttpStatusCode.OK && k173_bca?["ClassificationValue"]?.ToString() == "BCA" && k173_bca?["Basis"]?.ToString() == "Derived"
                 && k173_open.Count == 13 && k173_prc is not null,
                $"#173: the commit writes the derived BCA (Basis {k173_bca?["Basis"]}) and opens the 13 standards that bind the SEL-421 — 12 CIP and PRC-023 R1 ({k173_open.Count} open; rule errors: {k173_e1b?["ruleErrors"]})");

            // (e) the owner's rule: a standard a device is not bound by does not appear against it. An electromechanical relay holds no
            // cyber asset, so the derivation says Not BCA and not one CIP obligation stands against the BDD15B.
            var (k173_e2s, k173_e2b) = await Post(admin, "api/v1/compliance/evaluate", new { subjectEntityId = devBdd, mode = "Effective" });
            var k173_d2 = (k173_e2b?["derivations"] as JsonArray)?.FirstOrDefault(d => d?["kind"]?.ToString() == "BesCyberAsset");
            var (k173_o2s, k173_o2b) = await Get(admin, $"api/v1/compliance/vObligationSubject?SubjectEntityId={devBdd}");
            var k173_cipRows = (k173_o2b?["rows"] as JsonArray)?.Count(r => (r?["StandardCode"]?.ToString() ?? "").StartsWith("CIP", StringComparison.Ordinal)) ?? -1;
            Must(k173_e2s == HttpStatusCode.OK && k173_d2?["value"]?.ToString() == "Not BCA" && k173_cipRows == 0,
                $"#173: the electromechanical relay is derived Not BCA ({k173_d2?["reason"]}) and no CIP standard appears against it ({k173_cipRows} CIP rows)");

            // (f) #195: the rating is the building's — a station is refused (50235); the building's Medium is what the device reads
            var (k173_c2s, k173_c2b) = await Post(admin, "api/v1/asset/RecordClassification", new { SubjectKind = "Node", SubjectEntityId = station, ClassificationKindCode = "CipImpactRating", ClassificationValue = "Low" });
            var (k173_v2s, k173_v2b) = await Post(admin, "api/v1/compliance/evaluate", new { subjectEntityId = devSel, mode = "Preview" });
            var k173_cipV = (k173_v2b?["verdicts"] as JsonArray)?.FirstOrDefault(v => v?["ruleKey"]?.ToString() == "cip007_r1");
            var k173_read = (k173_cipV?["reads"] as JsonArray)?.FirstOrDefault(r => r?["name"]?.ToString() == "device.location.classification.CipImpactRating");
            Must(k173_c2s == HttpStatusCode.Conflict && (k173_c2b?["detail"]?.ToString() ?? "").Contains("not on a Station") && k173_v2s == HttpStatusCode.OK && k173_read?["value"]?.ToString() == "Medium" && k173_cipV?["result"]?.ToString() == "true",
                $"#173/#195: a station is not rated ({(int)k173_c2s} {k173_c2b?["detail"]}); the building's Medium is what the device reads ({k173_read?["value"]}) and CIP-007 R1 still binds ({k173_cipV?["result"]})");
            // #195: the fixture building's rating is withdrawn at the end — no smoke run leaves a rating behind
            var (k195_ws, _) = await Post(admin, "api/v1/asset/RecordClassification", new { SubjectKind = "Node", SubjectEntityId = building, ClassificationKindCode = "CipImpactRating", ClassificationValue = "" });
            var (k195_ls, k195_lb) = await Get(admin, "api/v1/asset/vClassification?SubjectKind=Node&ClassificationKindCode=CipImpactRating&take=500");
            var k195_left = 0; foreach (var c in (k195_lb?["rows"] as JsonArray) ?? new JsonArray()) { var (_, nb) = await Get(admin, $"api/v1/location/vNode?EntityId={c?["SubjectEntityId"]}&take=1"); if ((((nb?["rows"] as JsonArray)?.FirstOrDefault())?["Name"]?.ToString() ?? "").StartsWith("W4_")) k195_left++; }
            Must(k195_ws == HttpStatusCode.OK && k195_ls == HttpStatusCode.OK && k195_left == 0, $"#195: the fixture building's rating withdrawn ({(int)k195_ws}); no smoke-fixture node carries a CIP rating ({k195_left} of {(k195_lb?["rows"] as JsonArray)?.Count})");

            // (g) a second pass changes nothing; ReadOnly may preview but not commit; the runs are on record
            var (k173_e3s, k173_e3b) = await Post(admin, "api/v1/compliance/evaluate", new { subjectEntityId = devSel, mode = "Effective" });
            var (k173_q1s, _) = await Post(readOnly!, "api/v1/compliance/evaluate", new { subjectEntityId = devSel, mode = "Preview" });
            var (k173_q2s, _) = await Post(readOnly!, "api/v1/compliance/evaluate", new { subjectEntityId = devSel, mode = "Effective" });
            var (k173_rns, k173_rnb) = await Get(admin, "api/v1/compliance/vRuleEvaluationRun?Mode=Effective&take=5");
            Must(k173_e3s == HttpStatusCode.OK && (k173_e3b?["opened"]?.GetValue<int>() ?? -1) == 0 && (k173_e3b?["closed"]?.GetValue<int>() ?? -1) == 0
                 && k173_q1s == HttpStatusCode.OK && k173_q2s == HttpStatusCode.Forbidden && ((k173_rnb?["rows"] as JsonArray)?.Count ?? 0) >= 1,
                $"#173: a second pass changes nothing (opened {k173_e3b?["opened"]}, closed {k173_e3b?["closed"]}); ReadOnly previews ({(int)k173_q1s}) but does not commit ({(int)k173_q2s}); the runs are on record");

            // (h) the evidence trail of the PRC-023 obligation: the settings, the derived quantities, the ratings and the criterion
            var (k173_f1s, k173_f1b) = await Get(admin, $"api/v1/compliance/vObligationInstanceFact?ObligationInstanceRowId={k173_prc?["RowId"]}");
            var k173_facts = (k173_f1b?["rows"] as JsonArray)?.GroupBy(r => r?["FactName"]?.ToString() ?? "").ToDictionary(g => g.Key, g => g.Last()?["ValueAsRead"]?.ToString() ?? "") ?? new();
            Must(k173_f1s == HttpStatusCode.OK && k173_facts.ContainsKey("asset.formula.prc023_criterion")
                 && k173_facts.GetValueOrDefault("device.protects.terminal.voltage", "").StartsWith("230", StringComparison.Ordinal)
                 && k173_facts.ContainsKey("device.protects.rating[kind=FourHour]"),
                $"#173: the obligation's evidence trail names the terminal's voltage, the ratings read and the criterion chosen ({k173_facts.Count} facts, criterion {k173_facts.GetValueOrDefault("asset.formula.prc023_criterion")})");

            // ======== #184 (2026-09-18): the device template, and PRC-023 + NPCC A-10 / Directory 4 as its compliance. The owner:
            // a template is one per device type, one level below a scheme, named "SEL221F_Template"; compliance in it is
            // CALCULATED from study values recorded on the primary elements, "not something that an admin can turn on or off";
            // and NPCC A-10 "has no impact on settings but a huge impact on the physical design of the protection (Directory 4
            // compliance)" — a documentation-awareness case. Directory 4 and A-10 are seeded from the documents at npcc.org.
            var (k184_d1s, k184_d1b) = await Get(admin, "api/v1/config/vDefinition?DefinitionKind=CharacteristicSchema.AssetTemplate&DefinitionKey=SEL221F_Template&take=1");
            var k184_def = (k184_d1b?["rows"] as JsonArray)?.FirstOrDefault();
            var (k184_v1s, k184_v1b) = await Get(admin, $"api/v1/config/vDefinitionVersion?DefinitionEntityId={k184_def?["EntityId"]}&Status=Effective&take=5");
            var k184_ver = (k184_v1b?["rows"] as JsonArray)?.FirstOrDefault();
            var (k184_a1s, k184_a1b) = await Get(admin, $"api/v1/config/vDefinitionAppliesTo?DefinitionVersionRowId={k184_ver?["RowId"]}&DimensionCode=Model&take=10");
            var k184_bound = (k184_a1b?["rows"] as JsonArray)?.Count ?? -1;
            var (k184_c1s, k184_c1b) = await Get(readOnly!, $"api/v1/config/vCharacteristicDefinition?DefinitionVersionRowId={k184_ver?["RowId"]}&take=50");
            var k184_facts = (k184_c1b?["rows"] as JsonArray)?.Count ?? -1;
            Must(k184_d1s == HttpStatusCode.OK && k184_def is not null && k184_ver is not null && k184_bound == 2 && k184_c1s == HttpStatusCode.OK && k184_facts == 7,   // #185: the two compliance facts left the template
                $"#184: SEL221F_Template is an Effective AssetTemplate bound to both SEL-221F model codes ({k184_bound}), and ReadOnly reads its {k184_facts} facts");

            // Directory 4 and A-10 are seeded from the documents, page-cited, and the screen definition is Effective
            var (k184_s1s, k184_s1b) = await Get(admin, "api/v1/compliance/vStandardVersion?StandardCode=NPCC-D4&take=5");
            var k184_sv = (k184_s1b?["rows"] as JsonArray)?.FirstOrDefault();
            var (k184_r1s, k184_r1b) = await Get(admin, $"api/v1/compliance/vRequirement?StandardVersionRowId={k184_sv?["RowId"]}&take=100");
            var k184_reqs = (k184_r1b?["rows"] as JsonArray)?.Count ?? -1;
            var (k184_s2s, k184_s2b) = await Get(admin, "api/v1/compliance/vStandardVersion?StandardCode=NPCC-A10&take=5");
            var (k184_sc1s, k184_sc1b) = await Get(admin, "api/v1/config/vDefinition?DefinitionKind=Program.Screen&DefinitionKey=DEVICE_TEMPLATE&take=1");
            Must(k184_s1s == HttpStatusCode.OK && k184_sv?["VersionLabel"]?.ToString() == "D4 (2025-12-18)" && k184_reqs == 23
                 && k184_s2s == HttpStatusCode.OK && ((k184_s2b?["rows"] as JsonArray)?.Count ?? 0) == 1
                 && k184_sc1s == HttpStatusCode.OK && ((k184_sc1b?["rows"] as JsonArray)?.Count ?? 0) == 1,
                $"#184: NPCC Directory 4 ({k184_sv?["VersionLabel"]}) carries its {k184_reqs} criteria R5.1 — R6.3, A-10 is seeded beside it, and the DEVICE_TEMPLATE screen is defined");

            // the awareness case, end to end: the A-10 outcome on the bus the relay's scheme protects from decides Directory 4.
            // The fixture bus is tied to the line's terminal at this station (the terminal the scheme protects from), declared
            // BPS, and the relay's next pass opens npcc_d4; declared Not BPS, the next pass closes it. Nobody switched anything on.
            var (k184_t1s, k184_t1b) = await Post(admin, "api/v1/asset/AssetTerminal_Revise", new { EntityId = k173_term, AssetEntityId = k173_line, TerminalNo = 1, StationNodeEntityId = station, VoltageClassCode = "230kV", BusAssetEntityId = k173_bus });
            var (k184_b1s, k184_b1b) = await Post(admin, "api/v1/asset/RecordClassification", new { SubjectKind = "Asset", SubjectEntityId = k173_bus, ClassificationKindCode = "NpccBulkPowerSystem", ClassificationValue = "BPS" });
            var (k184_e1s, k184_e1b) = await Post(admin, "api/v1/compliance/evaluate", new { subjectEntityId = devSel, mode = "Effective" });
            var (k184_o1s, k184_o1b) = await Get(admin, $"api/v1/compliance/vObligationSubject?SubjectEntityId={devSel}");
            var k184_openBps = (k184_o1b?["rows"] as JsonArray)?.Where(r => r?["Status"]?.ToString() == "Open").Select(r => r?["RuleDefinitionKey"]?.ToString()).ToList() ?? new();
            var (k184_b2s, _) = await Post(admin, "api/v1/asset/RecordClassification", new { SubjectKind = "Asset", SubjectEntityId = k173_bus, ClassificationKindCode = "NpccBulkPowerSystem", ClassificationValue = "Not BPS" });
            var (k184_e2s, k184_e2b) = await Post(admin, "api/v1/compliance/evaluate", new { subjectEntityId = devSel, mode = "Effective" });
            var (k184_o2s, k184_o2b) = await Get(admin, $"api/v1/compliance/vObligationSubject?SubjectEntityId={devSel}");
            var k184_openNot = (k184_o2b?["rows"] as JsonArray)?.Where(r => r?["Status"]?.ToString() == "Open").Select(r => r?["RuleDefinitionKey"]?.ToString()).ToList() ?? new();
            var (k184_q1s, _) = await Post(readOnly!, "api/v1/asset/RecordClassification", new { SubjectKind = "Asset", SubjectEntityId = k173_bus, ClassificationKindCode = "NpccBulkPowerSystem", ClassificationValue = "BPS" });
            // #196 (owner, 2026-09-19): the A-10 declaration is entered on the protected ELEMENT; the bus's stands in when the element has none
            var (k196_l1s, k196_l1b) = await Post(admin, "api/v1/asset/RecordClassification", new { SubjectKind = "Asset", SubjectEntityId = k173_line, ClassificationKindCode = "NpccBulkPowerSystem", ClassificationValue = "BPS" });
            var (k196_e1s, _) = await Post(admin, "api/v1/compliance/evaluate", new { subjectEntityId = devSel, mode = "Effective" });
            var (_, k196_o1b) = await Get(admin, $"api/v1/compliance/vObligationSubject?SubjectEntityId={devSel}");
            var k196_openLine = (k196_o1b?["rows"] as JsonArray)?.Where(r => r?["Status"]?.ToString() == "Open").Select(r => r?["RuleDefinitionKey"]?.ToString()).ToList() ?? new();
            var (k196_l2s, _) = await Post(admin, "api/v1/asset/RecordClassification", new { SubjectKind = "Asset", SubjectEntityId = k173_line, ClassificationKindCode = "NpccBulkPowerSystem", ClassificationValue = "" });
            var (k196_e2s, _) = await Post(admin, "api/v1/compliance/evaluate", new { subjectEntityId = devSel, mode = "Effective" });
            var (_, k196_o2b) = await Get(admin, $"api/v1/compliance/vObligationSubject?SubjectEntityId={devSel}");
            var k196_openBack = (k196_o2b?["rows"] as JsonArray)?.Where(r => r?["Status"]?.ToString() == "Open").Select(r => r?["RuleDefinitionKey"]?.ToString()).ToList() ?? new();
            Must(k196_l1s == HttpStatusCode.OK && k196_e1s == HttpStatusCode.OK && k196_openLine.Contains("npcc_d4") && k196_l2s == HttpStatusCode.OK && k196_e2s == HttpStatusCode.OK && !k196_openBack.Contains("npcc_d4"),
                $"#196: the line declared BPS (the bus Not BPS) opens npcc_d4 on its relay ({(int)k196_l1s} {Code(k196_l1b)}; open: {string.Join(", ", k196_openLine)}); the declaration withdrawn, the bus's Not BPS stands in and it closes ({string.Join(", ", k196_openBack)})");
            Must(k184_t1s == HttpStatusCode.OK && k184_b1s == HttpStatusCode.OK && k184_e1s == HttpStatusCode.OK && k184_openBps.Contains("npcc_d4")
                 && k184_b2s == HttpStatusCode.OK && k184_e2s == HttpStatusCode.OK && !k184_openNot.Contains("npcc_d4") && k184_q1s == HttpStatusCode.Forbidden,
                $"#184: the A-10 outcome on the protected bus decides Directory 4 — BPS opens npcc_d4 on the relay ({string.Join(", ", k184_openBps)}), Not BPS closes it ({string.Join(", ", k184_openNot)}), and ReadOnly records nothing ({(int)k184_q1s})");
        }

        // ======== #197 (2026-09-19): PRC-023 applies only where an element in service is load-responsive (Attachment A), and the
        // reason it does not apply is read from the facts. The owner: "a device is only applicable if it has a load responsive
        // element... in service"; "there must be a reason". The fixture's SEL-421 carries 87T and 21 at its position; the BDD15B
        // carries 87T alone — differential is not listed in Attachment A 1, so R1 does not bind it, and the note says why.
        {
            var (k197_a1s, k197_a1b) = await Get(admin, "api/v1/ref/vAnsiFunction?AnsiCode=51N&take=1");
            var k197_51n = (k197_a1b?["rows"] as JsonArray)?.FirstOrDefault();
            var (k197_pfs, k197_pfb) = await Get(admin, $"api/v1/scheme/vPositionFunction?PositionNodeEntityId={positions[1]}&take=10");
            var k197_pf = (k197_pfb?["rows"] as JsonArray)?.FirstOrDefault(r => r?["AnsiCode"]?.ToString() == "87T");
            Must(k197_a1s == HttpStatusCode.OK && k197_51n?["LoadResponsive"]?.GetValue<bool>() == false && (k197_51n?["LoadResponsiveBasis"]?.ToString() ?? "").Contains("2.2")
                 && k197_pfs == HttpStatusCode.OK && k197_pf?["LoadResponsive"]?.GetValue<bool>() == false,
                $"#197: 51N is ruled not load-responsive ({k197_51n?["LoadResponsiveBasis"]}); the position's 87T reads the ruling ({k197_pf?["LoadResponsive"]} — {k197_pf?["LoadResponsiveBasis"]})");
            var (k197_v1s, k197_v1b) = await Post(admin, "api/v1/compliance/evaluate", new { subjectEntityId = devBdd, mode = "Preview" });
            var k197_prc = (k197_v1b?["verdicts"] as JsonArray)?.FirstOrDefault(v => v?["ruleKey"]?.ToString() == "prc023_r1");
            var k197_reads = (k197_prc?["reads"] as JsonArray) ?? new JsonArray();
            var k197_fn = k197_reads.FirstOrDefault(r => r?["name"]?.ToString() == "device.functions" && r?["params"] is null)?["value"]?.ToString();
            var k197_note = k197_reads.FirstOrDefault(r => r?["name"]?.ToString() == "device.functions.note")?["value"]?.ToString() ?? "";
            Must(k197_v1s == HttpStatusCode.OK && k197_prc?["result"]?.ToString() == "false" && k197_fn == "{87T}" && k197_note.Contains("not load-responsive") && k197_note.Contains("Attachment A"),
                $"#197: PRC-023 R1 does not bind the 87T-only relay ({k197_prc?["result"]}); the reason is in the reads — device.functions {k197_fn}; {k197_note}");
            var (k197_v2s, k197_v2b) = await Post(admin, "api/v1/compliance/evaluate", new { subjectEntityId = devSel, mode = "Preview" });
            var k197_prc2 = (k197_v2b?["verdicts"] as JsonArray)?.FirstOrDefault(v => v?["ruleKey"]?.ToString() == "prc023_r1");
            var k197_lr = (k197_prc2?["reads"] as JsonArray)?.FirstOrDefault(r => r?["name"]?.ToString() == "device.functions" && (r?["params"]?.ToString() ?? "").Contains("load_responsive"))?["value"]?.ToString();
            Must(k197_v2s == HttpStatusCode.OK && k197_prc2?["result"]?.ToString() == "true" && k197_lr == "{21}",
                $"#197: the relay with 21 in service is bound ({k197_prc2?["result"]}; load-responsive elements {k197_lr})");
        }

        // ======== #201 (2026-09-19): instrument transformers as equipment in their own right (the vision §4.3 / §10.1, the owner:
        // "Instrument transformers should be first class devices in their own right with testing"). The types the predecessor
        // held as INTERFACE are here as Hybrid (CT, VT …) or Secondary (CT_AUX, METER — the vision's rule); a CT made at a bay
        // with its nameplate ratio feeds the fixture scheme as CT source; the read models give the ratio as a number.
        {
            var (k201_t1s, k201_t1b) = await Get(admin, "api/v1/ref/vAssetType?AssetClassCode=Hybrid&take=50");
            var k201_hybrid = ((k201_t1b?["rows"] as JsonArray) ?? []).Select(r => r?["AssetTypeCode"]?.ToString()).ToList();
            var (_, k201_t2b) = await Get(admin, "api/v1/ref/vAssetType?AssetTypeCode=CT_AUX&take=1");
            var k201_aux = (k201_t2b?["rows"] as JsonArray)?.FirstOrDefault();
            Must(k201_t1s == HttpStatusCode.OK && k201_hybrid.Contains("CT") && k201_hybrid.Contains("VT") && k201_hybrid.Contains("COUPLING_CAPACITOR_VT") && k201_hybrid.Contains("WAVE_TRAP")
                 && k201_aux?["AssetClassCode"]?.ToString() == "Secondary" && k201_aux?["DefaultTemplateDefinitionEntityId"] is not null,
                $"#201: the instrument-transformer types are Hybrid ({k201_hybrid.Count}: {string.Join(", ", k201_hybrid)}); an auxiliary CT is Secondary by the vision's rule and carries the CT nameplate template");
            // #202 (the owner, 2026-09-19): on the transmission network an instrument transformer is a child of the Yard — not a bay,
            // not an equipment position; asset.PlaceAsset refuses anything else (50218). The yard is made as #175 makes one.
            var (k201_ys, k201_yb) = await Post(admin, "api/v1/location/AddNode", new { NodeTypeCode = "Yard", ParentEntityId = station, Name = $"{tag} 230 kV yard", Code = "Y230" });
            var k201_bay = Id(k201_yb); var k201_bs = k201_ys; var k201_bb = k201_yb;
            var (k201_as, k201_ab) = await Post(admin, "api/v1/asset/Asset_Add", new { AssetTypeCode = "CT", Name = $"{tag} line CT", Status = "InService" });
            var k201_ct = Id(k201_ab);
            // #203 (the owner, 2026-09-19): "bays will be children of a building" — the rule is a row of ref.LocationNodeTypeParent
            var (k203_bs, k203_bb) = await Post(admin, "api/v1/location/AddNode", new { NodeTypeCode = "Bay", ParentEntityId = building, Name = $"{tag} bay 1", Code = "BAY1" });
            var (k203_ys, k203_yb) = await Post(admin, "api/v1/location/AddNode", new { NodeTypeCode = "Bay", ParentEntityId = Id(k201_yb), Name = $"{tag} yard bay", Code = "BAY9" });
            Must(k203_bs == HttpStatusCode.OK && k203_ys == HttpStatusCode.Conflict, $"#203: a bay is a child of a building ({(int)k203_bs} {Code(k203_bb)} {k203_bb?["detail"]}) and not of a yard ({(int)k203_ys} {k203_yb?["detail"]})");
            var (k201_xs, k201_xb) = await Post(admin, "api/v1/asset/PlaceAsset", new { AssetEntityId = k201_ct, NodeEntityId = panel, PlacementKind = "Installed" });
            Must(k201_xs == HttpStatusCode.Conflict && (k201_xb?["detail"]?.ToString() ?? "").Contains("stands in a Yard"), $"#202: a CT at a panel is refused in the owner's words ({(int)k201_xs} {k201_xb?["detail"]})");
            var (k201_ps, k201_pb) = await Post(admin, "api/v1/asset/PlaceAsset", new { AssetEntityId = k201_ct, NodeEntityId = k201_bay, PlacementKind = "Installed" });
            var (_, k201_defsb) = await Get(admin, $"api/v1/config/vDefinitionVersion?DefinitionEntityId={k201_aux?["DefaultTemplateDefinitionEntityId"]}&Status=Effective&take=1");
            var k201_ver = (k201_defsb?["rows"] as JsonArray)?.FirstOrDefault()?["RowId"]?.ToString();
            var (_, k201_cdb) = await Get(admin, $"api/v1/config/vCharacteristicDefinition?DefinitionVersionRowId={k201_ver}&CharacteristicKey=RatioInUse&take=1");
            var k201_def = (k201_cdb?["rows"] as JsonArray)?.FirstOrDefault()?["RowId"]?.ToString();
            var (k201_cvs, k201_cvb) = await Post(admin, "api/v1/asset/CharacteristicValue_Add", new { HostEntityId = k201_ct, CharacteristicDefinitionRowId = k201_def, TextValue = "1200:5" });
            var (k201_ms, k201_mb) = await Post(admin, "api/v1/scheme/AddSchemeMember", new { SchemeEntityId = scheme, MemberKind = "Asset", MemberEntityId = k201_ct, MemberRoleCode = "CtSource", IsInService = true });
            Must(k201_ys == HttpStatusCode.OK && k201_bs == HttpStatusCode.OK && k201_as == HttpStatusCode.OK && k201_ps == HttpStatusCode.OK && k201_def is not null && k201_cvs == HttpStatusCode.OK && k201_ms == HttpStatusCode.OK,
                $"#201: a CT made in the fixture's yard with its ratio in use and named the scheme's CT source ({(int)k201_ys} {Code(k201_yb)}; {(int)k201_bs} {Code(k201_bb)}; {(int)k201_as} {Code(k201_ab)}; {(int)k201_ps} {Code(k201_pb)}; def {k201_def?[..8]}; {(int)k201_cvs} {Code(k201_cvb)}; {(int)k201_ms} {Code(k201_mb)} {k201_mb?["detail"]})");
            var (k201_its, k201_itb) = await Get(admin, $"api/v1/asset/vInstrumentTransformer?EntityId={k201_ct}&take=1");
            var k201_it = (k201_itb?["rows"] as JsonArray)?.FirstOrDefault();
            var (k201_ss, k201_sb) = await Get(admin, $"api/v1/scheme/vSchemeSource?SchemeEntityId={scheme}&take=10");
            var k201_src = (k201_sb?["rows"] as JsonArray)?.FirstOrDefault(x => x?["AssetEntityId"]?.ToString()?.Equals(k201_ct?.ToString(), StringComparison.OrdinalIgnoreCase) == true);
            Must(k201_its == HttpStatusCode.OK && k201_it?["RatioInUse"]?.ToString() == "1200:5" && k201_it?["StationName"]?.ToString() == $"{tag} station" && (k201_it?["FeedsCount"]?.GetValue<int>() ?? 0) == 1
                 && k201_ss == HttpStatusCode.OK && k201_src?["MemberRoleCode"]?.ToString() == "CtSource" && Math.Abs((k201_src?["Ratio"]?.GetValue<decimal>() ?? 0) - 240m) < 0.001m,
                $"#201: the transformer reads back with its station, ratio and the scheme it feeds ({k201_it?["StationName"]} · {k201_it?["RatioInUse"]} · feeds {k201_it?["FeedsCount"]}); the scheme's source reads 1200:5 as {k201_src?["Ratio"]}");
            var (k201_rs, _) = await Post(readOnly!, "api/v1/asset/Asset_Add", new { AssetTypeCode = "VT", Name = $"{tag} stray VT", Status = "InService" });
            Must(k201_rs == HttpStatusCode.Forbidden, $"#201: ReadOnly may not make a transformer ({(int)k201_rs})");

            // ======== #204 (2026-09-19): the transformer's tests — the CT_TEST procedure (ratio, polarity, excitation, review) run
            // under a request scoped to the CT; each step's captures are the readings, each commit a TestSheet record against
            // the CT; a required capture missing is refused; the engineer's review is an Attestation; the request closes.
            var (k204_wts, k204_wtb) = await Get(admin, "api/v1/config/vDefinition?DefinitionKind=Program.WorkType&DefinitionKey=CT_TEST&take=1");
            var k204_wt = Id((k204_wtb?["rows"] as JsonArray)?.FirstOrDefault());
            var (_, k204_vb) = await Get(admin, $"api/v1/config/vDefinitionVersion?DefinitionEntityId={k204_wt}&Status=Effective&take=1");
            var k204_wtv = (k204_vb?["rows"] as JsonArray)?.FirstOrDefault()?["RowId"]?.ToString();
            var (k204_ws, k204_wb) = await Post(admin, "api/v1/work/WorkRequest_Add", new { WorkTypeDefinitionVersionRowId = k204_wtv, Title = $"{tag} line CT test", ScopeKind = "Asset", ScopeEntityId = k201_ct });
            var k204_wr = Id(k204_wb);
            var (k204_ss, k204_sb) = await Post(admin, "api/v1/process/workflows/start", new { workflowKey = "CT_TEST_REQUEST", subjectKind = "WorkRequest", subjectEntityId = k204_wr });
            var k204_wf = Id(k204_sb, "workflowInstanceEntityId");
            var (k204_ts, k204_tb) = await Post(admin, $"api/v1/process/workflow-instances/{k204_wf}/transitions", new { name = "Start" });
            var (_, k204_pib) = await Get(admin, $"api/v1/process/vProcedureInstance?WorkRequestEntityId={k204_wr}&take=5");
            var k204_inst = Id((k204_pib?["rows"] as JsonArray)?.FirstOrDefault(x => x?["ParentInstanceEntityId"] is null));
            Must(k204_wts == HttpStatusCode.OK && k204_wtv is not null && k204_ws == HttpStatusCode.OK && k204_ss == HttpStatusCode.OK && k204_ts == HttpStatusCode.OK && k204_inst is not null,
                $"#204: a CT test request on the transformer starts CT_TEST ({(int)k204_ws} {Code(k204_wb)}; {(int)k204_ss} {Code(k204_sb)} {k204_sb?["detail"]}; {(int)k204_ts} {k204_tb?["toState"]}; instance {k204_inst?.ToString()[..8]})");
            var k204_saved = inst; inst = k204_inst;
            var k204_r = await ReadyStep("RATIO", null, 2);
            var (k204_c1s, k204_c1b) = await Post(tech, $"api/v1/process/step-instances/{k204_r}/claim", new { });
            var (k204_x1s, k204_x1b) = await Post(tech, $"api/v1/process/step-instances/{k204_r}/commit", new { outcome = "Pass", capture = new { ratioMeasured = 240 } });
            var (k204_x2s, k204_x2b) = await Post(tech, $"api/v1/process/step-instances/{k204_r}/commit", new { outcome = "Pass", capture = new { tap = "1200:5", appliedPrimaryA = 600, measuredSecondaryA = 2.5, ratioMeasured = 240, ratioErrorPercent = 0, method = "Primary injection" } });
            Must(k204_r is not null && k204_c1s == HttpStatusCode.OK && k204_x1s == HttpStatusCode.Conflict && (k204_x1b?["detail"]?.ToString() ?? "").Contains("required captures are missing")
                 && k204_x2s == HttpStatusCode.OK,
                $"#204: the ratio sheet — a commit without the tap is refused in the procedure's words ({(int)k204_x1s} {k204_x1b?["detail"]}); with the readings it commits ({(int)k204_x2s} {Code(k204_x2b)} {k204_x2b?["detail"]})");
            await RunStep(tech, "POLARITY", new { outcome = "Pass", capture = new { polarity = "Correct", method = "DC kick" } });
            await RunStep(tech, "EXCITATION", new { outcome = "Pass", capture = new { kneePointVoltageV = 410, kneePointCurrentA = 0.1, points = "100, 0.02\n200, 0.04\n410, 0.1\n450, 0.5", method = "Test set" } });
            await RunStep(admin, "REVIEW", new { outcome = "Accepted", capture = new { remarks = "ratio and knee point agree with the nameplate" } });
            await Post(admin, $"api/v1/process/procedure-instances/{inst}/evaluate", new { });
            var (_, k204_recb) = await Get(admin, $"api/v1/record/vRecord?SubjectKind=Asset&SubjectEntityId={k201_ct}&take=20");
            var k204_kinds = ((k204_recb?["rows"] as JsonArray) ?? []).GroupBy(x => x?["RecordKindCode"]?.ToString() ?? "").ToDictionary(g => g.Key, g => g.Count());
            var (k204_cls, k204_clb) = await Post(admin, $"api/v1/process/workflow-instances/{k204_wf}/transitions", new { name = "Close" });
            Must(k204_kinds.GetValueOrDefault("TestSheet") == 3 && k204_kinds.GetValueOrDefault("Attestation") == 1 && k204_cls == HttpStatusCode.OK,
                $"#204: three test sheets and the engineer's attestation stand against the CT ({string.Join(", ", k204_kinds.Select(kv => kv.Key + " " + kv.Value))}); the request closes on the completed procedure ({(int)k204_cls} {k204_clb?["toState"]} {k204_clb?["detail"]})");
            var (k204_rs, _) = await Post(readOnly!, "api/v1/work/WorkRequest_Add", new { WorkTypeDefinitionVersionRowId = k204_wtv, Title = $"{tag} stray test", ScopeKind = "Asset", ScopeEntityId = k201_ct });
            Must(k204_rs == HttpStatusCode.Forbidden, $"#204: ReadOnly may not raise a test ({(int)k204_rs})");
            inst = k204_saved;
        }

        // ======== #206 (2026-09-20): the instrument transformers a protection needs exist — made by the migration rule from the
        // legacy record's CT/PT strings and the devices' functions (Seed_asset_InstrumentTransformersFromLegacy), and edited,
        // placed, connected, retired and deleted by a person. The owner: "when a particular device indicates that it has CT and
        // PT inputs, it is reasonable to assume that they exist because without them, the protection is useless."
        {
            // the rule on the migrated estate: 2103 B-PROT at BATHURST TERMINAL (an in-service SEL-221F declaring CT_MAIN1 = 1200-5,
            // PT_MAIN = 2000-1 on DEV) has a CT set of ratio 240 and a PT set of ratio 2000, three-phase, unplaced, with the rule's key
            var (k206_rs, k206_rb) = await Get(admin, $"api/v1/document/vSettingsRecord?GridState=Active&SchemeName={Uri.EscapeDataString("2103 B-PROT")}&StationName={Uri.EscapeDataString("BATHURST TERMINAL")}&take=5");
            var k206_scheme = (k206_rb?["rows"] as JsonArray)?.FirstOrDefault()?["SchemeEntityId"]?.ToString();
            var (k206_ss, k206_sb) = await Get(admin, $"api/v1/scheme/vSchemeSource?SchemeEntityId={k206_scheme}&take=20");
            var k206_src = (k206_sb?["rows"] as JsonArray) ?? [];
            var k206_ct = k206_src.FirstOrDefault(x => x?["MemberRoleCode"]?.ToString() == "CtSource" && Math.Abs((x?["Ratio"]?.GetValue<decimal>() ?? 0) - 240m) < 0.01m);
            var k206_pt = k206_src.FirstOrDefault(x => x?["MemberRoleCode"]?.ToString() == "VtSource" && Math.Abs((x?["Ratio"]?.GetValue<decimal>() ?? 0) - 2000m) < 0.01m);
            var (_, k206_itb) = await Get(admin, $"api/v1/asset/vInstrumentTransformer?EntityId={k206_ct?["AssetEntityId"]}&take=1");
            var k206_it = (k206_itb?["rows"] as JsonArray)?.FirstOrDefault();
            Must(k206_rs == HttpStatusCode.OK && k206_scheme is not null && k206_ss == HttpStatusCode.OK && k206_ct is not null && k206_pt is not null
                 && k206_ct?["Phases"]?.GetValue<int>() == 3 && k206_ct?["IsPlaced"]?.GetValue<bool>() == false
                 && k206_it?["MigrationSource"]?.ToString()?.EndsWith("/CtSource/1200:5") == true && k206_it?["StationSource"]?.ToString() == "scheme" && k206_it?["StationName"]?.ToString() == "BATHURST TERMINAL",
                $"#206: the rule made 2103 B-PROT (BATHURST TERMINAL) its CT set ({k206_ct?["AssetName"]} · {k206_ct?["RatioInUse"]} = {k206_ct?["Ratio"]} · {k206_ct?["Phases"]}-phase · placed {k206_ct?["IsPlaced"]}) and PT set ({k206_pt?["AssetName"]} = {k206_pt?["Ratio"]}); the set knows its station through the scheme ({k206_it?["StationName"]} by {k206_it?["StationSource"]}) and carries the rule's key ({k206_it?["MigrationSource"]})");
            // never a duplicate: the #201 fixture scheme keeps exactly one CtSource (its fixture CT); a scheme with a 25 device has its sync PT
            var (_, k206_fb) = await Get(admin, $"api/v1/scheme/vSchemeSource?SchemeEntityId={scheme}&MemberRoleCode=CtSource&take=10");
            var k206_fix = ((k206_fb?["rows"] as JsonArray) ?? []).Count;
            var (_, k206_syb) = await Get(admin, "api/v1/scheme/vSchemeSource?MemberRoleCode=SyncVtSource&take=1");
            var k206_sync = (k206_syb?["rows"] as JsonArray)?.FirstOrDefault();
            var (_, k206_ab) = await Get(admin, "api/v1/ref/vAnsiFunction?AnsiCode=21&take=1");
            var k206_21 = (k206_ab?["rows"] as JsonArray)?.FirstOrDefault();
            var (_, k206_db) = await Get(admin, "api/v1/config/vDefinition?DefinitionKind=CharacteristicSchema.RecordTemplate&DefinitionKey=SETTINGS_RECORD&take=1");
            Must(k206_fix == 1 && k206_sync is not null && k206_sync?["Phases"]?.GetValue<int>() == 1 && k206_21?["AnalogInputs"]?.ToString() == "IV" && ((k206_db?["rows"] as JsonArray) ?? []).Count == 0,
                $"#206: the fixture scheme keeps one CT source ({k206_fix}); a 25 scheme has its single-phase sync PT ({k206_sync?["AssetName"]} · {k206_sync?["Phases"]}-phase); 21 needs {k206_21?["AnalogInputs"]}; the legacy SETTINGS_RECORD characteristic schema is retired");
            // a person corrects: rename the fixture CT, make a PT, a new yard for it, place it, name it the sync VT source, set it not in service with a note, remove it, delete it
            var (_, k206_ctb) = await Get(admin, $"api/v1/asset/vInstrumentTransformer?Name={Uri.EscapeDataString($"{tag} line CT")}&take=1");   // the #201 fixture CT (that block's scope has closed)
            var k201_ct = Id((k206_ctb?["rows"] as JsonArray)?.FirstOrDefault());
            var (k206_es, k206_eb) = await Post(admin, "api/v1/asset/Asset_Revise", new { EntityId = k201_ct, AssetTypeCode = "CT", Name = $"{tag} line CT (S2 winding)", Status = "InService", Notes = "the B protection is on the S2 winding" });
            var (_, k206_e2b) = await Get(admin, $"api/v1/asset/vInstrumentTransformer?EntityId={k201_ct}&take=1");
            var k206_renamed = (k206_e2b?["rows"] as JsonArray)?.FirstOrDefault()?["Name"]?.ToString();
            var (k206_vs, k206_vb) = await Post(admin, "api/v1/asset/Asset_Add", new { AssetTypeCode = "VT", Name = $"{tag} sync PT", Status = "InService" });
            var k206_vt = Id(k206_vb);
            var (k206_ys, k206_yb) = await Post(admin, "api/v1/location/AddNode", new { NodeTypeCode = "Yard", ParentEntityId = station, Name = $"{tag} 138 kV yard", Code = "Y138" });
            var (k206_ps, k206_pb) = await Post(admin, "api/v1/asset/PlaceAsset", new { AssetEntityId = k206_vt, NodeEntityId = Id(k206_yb), PlacementKind = "Installed" });
            var (k206_ms, k206_mb) = await Post(admin, "api/v1/scheme/AddSchemeMember", new { SchemeEntityId = scheme, MemberKind = "Asset", MemberEntityId = k206_vt, MemberRoleCode = "SyncVtSource", IsInService = true });
            var (_, k206_s2b) = await Get(admin, $"api/v1/scheme/vSchemeSource?AssetEntityId={k206_vt}&take=1");
            var k206_mem = (k206_s2b?["rows"] as JsonArray)?.FirstOrDefault();
            var (k206_rvs, k206_rvb) = await Post(admin, "api/v1/scheme/SchemeMember_Revise", new { EntityId = k206_mem?["MemberEntityId"], SchemeEntityId = scheme, MemberKind = "Asset", MemberEntityId = k206_vt, MemberRoleCode = "SyncVtSource", IsInService = false, Notes = "a winding of the A protection's PT set" });
            var (_, k206_s3b) = await Get(admin, $"api/v1/scheme/vSchemeSource?AssetEntityId={k206_vt}&take=1");
            var k206_mem2 = (k206_s3b?["rows"] as JsonArray)?.FirstOrDefault();
            var (_, k206_i2b) = await Get(admin, $"api/v1/asset/vInstrumentTransformer?EntityId={k206_vt}&take=1");
            var k206_it2 = (k206_i2b?["rows"] as JsonArray)?.FirstOrDefault();
            Must(k206_es == HttpStatusCode.OK && k206_renamed == $"{tag} line CT (S2 winding)" && k206_vs == HttpStatusCode.OK && k206_ys == HttpStatusCode.OK && k206_ps == HttpStatusCode.OK && k206_ms == HttpStatusCode.OK
                 && k206_rvs == HttpStatusCode.OK && k206_mem2?["IsInService"]?.GetValue<bool>() == false && k206_mem2?["Notes"]?.ToString() == "a winding of the A protection's PT set"
                 && k206_it2?["IsPlaced"]?.GetValue<bool>() == true && k206_it2?["StationSource"]?.ToString() == "placement",
                $"#206: the fixture CT renamed ({(int)k206_es} {Code(k206_eb)} → {k206_renamed}); a sync PT made ({(int)k206_vs}), a new yard ({(int)k206_ys} {Code(k206_yb)}), placed there ({(int)k206_ps} {Code(k206_pb)}; placed {k206_it2?["IsPlaced"]} by {k206_it2?["StationSource"]}), named the scheme's sync VT source ({(int)k206_ms} {Code(k206_mb)}), set not in service with its connection note ({(int)k206_rvs} {Code(k206_rvb)}: {k206_mem2?["Notes"]})");
            var (k206_ds, k206_dbb) = await Post(admin, "api/v1/scheme/SchemeMember_SoftDelete", new { EntityId = k206_mem?["MemberEntityId"] });
            var (_, k206_s4b) = await Get(admin, $"api/v1/scheme/vSchemeSource?AssetEntityId={k206_vt}&take=1");
            var (k206_xs, k206_xb) = await Post(admin, "api/v1/asset/Asset_SoftDelete", new { EntityId = k206_vt });
            var (_, k206_i3b) = await Get(admin, $"api/v1/asset/vInstrumentTransformer?EntityId={k206_vt}&take=1");
            var (k206_ros, _) = await Post(readOnly!, "api/v1/asset/Asset_Revise", new { EntityId = k201_ct, AssetTypeCode = "CT", Name = $"{tag} stray rename", Status = "InService" });
            var (k206_ro2, _) = await Post(readOnly!, "api/v1/scheme/SchemeMember_SoftDelete", new { EntityId = k201_ct });
            Must(k206_ds == HttpStatusCode.OK && ((k206_s4b?["rows"] as JsonArray) ?? []).Count == 0 && k206_xs == HttpStatusCode.OK && ((k206_i3b?["rows"] as JsonArray) ?? []).Count == 0 && k206_ros == HttpStatusCode.Forbidden && k206_ro2 == HttpStatusCode.Forbidden,
                $"#206: removed from the scheme ({(int)k206_ds} {Code(k206_dbb)}; sources left {((k206_s4b?["rows"] as JsonArray) ?? []).Count}) and deleted ({(int)k206_xs} {Code(k206_xb)}; listed {((k206_i3b?["rows"] as JsonArray) ?? []).Count}); ReadOnly may neither edit ({(int)k206_ros}) nor remove ({(int)k206_ro2})");
        }

        // ======== #208 (2026-09-20): a protection's analog input is a thing — "Current 1", "Voltage", "Sync voltage" — and the CTs
        // paralleled into it (line 2103 fed breaker-and-a-half from E2103 and E2103-TC4: "the two sets of CTs will be paralleled
        // before being brought in to the device"). AddSchemeMember lands every source on an input (found or made); a second CT
        // on the same input is paralleled; an input of another scheme is refused; the tests stay per transformer.
        {
            var (_, k208_ctb) = await Get(admin, $"api/v1/asset/vInstrumentTransformer?Name={Uri.EscapeDataString($"{tag} line CT (S2 winding)")}&take=1");
            var k208_ct = Id((k208_ctb?["rows"] as JsonArray)?.FirstOrDefault());
            var (k208_ss, k208_sb) = await Get(admin, $"api/v1/scheme/vSchemeSource?AssetEntityId={k208_ct}&take=1");
            var k208_src = (k208_sb?["rows"] as JsonArray)?.FirstOrDefault();
            var k208_input = k208_src?["AnalogInputEntityId"]?.ToString();
            Must(k208_ss == HttpStatusCode.OK && k208_src?["InputCode"]?.ToString() == "Current 1" && k208_src?["InputKind"]?.ToString() == "Current" && k208_src?["ParallelCount"]?.GetValue<int>() == 1,
                $"#208: the fixture CT, named a source before inputs existed, feeds an input made for it ({k208_src?["InputCode"]} · {k208_src?["InputKind"]} · {k208_src?["ParallelCount"]} on it)");
            // the second breaker's CT set, paralleled into the same input
            var (k208_as, k208_ab) = await Post(admin, "api/v1/asset/Asset_Add", new { AssetTypeCode = "CT", Name = $"{tag} line CT (TC4 side)", Status = "InService" });
            var k208_ct2 = Id(k208_ab);
            var (_, k208_tb) = await Get(admin, "api/v1/ref/vAssetType?AssetTypeCode=CT&take=1");
            var (_, k208_vb) = await Get(admin, $"api/v1/config/vDefinitionVersion?DefinitionEntityId={(k208_tb?["rows"] as JsonArray)?.FirstOrDefault()?["DefaultTemplateDefinitionEntityId"]}&Status=Effective&take=1");
            var (_, k208_cdb) = await Get(admin, $"api/v1/config/vCharacteristicDefinition?DefinitionVersionRowId={(k208_vb?["rows"] as JsonArray)?.FirstOrDefault()?["RowId"]}&CharacteristicKey=RatioInUse&take=1");
            var (k208_cvs, _) = await Post(admin, "api/v1/asset/CharacteristicValue_Add", new { HostEntityId = k208_ct2, CharacteristicDefinitionRowId = (k208_cdb?["rows"] as JsonArray)?.FirstOrDefault()?["RowId"]?.ToString(), TextValue = "1200:5" });
            var (k208_ms, k208_mb) = await Post(admin, "api/v1/scheme/AddSchemeMember", new { SchemeEntityId = scheme, MemberKind = "Asset", MemberEntityId = k208_ct2, MemberRoleCode = "CtSource", IsInService = true, AnalogInputEntityId = k208_input, Notes = "the E2103-TC4 breaker side" });
            var (_, k208_s2b) = await Get(admin, $"api/v1/scheme/vSchemeSource?AnalogInputEntityId={k208_input}&take=10");
            var k208_on = (k208_s2b?["rows"] as JsonArray) ?? [];
            var (_, k208_ib) = await Get(admin, $"api/v1/scheme/vSchemeInput?EntityId={k208_input}&take=1");
            var k208_in = (k208_ib?["rows"] as JsonArray)?.FirstOrDefault();
            Must(k208_as == HttpStatusCode.OK && k208_cvs == HttpStatusCode.OK && k208_ms == HttpStatusCode.OK && k208_on.Count == 2 && k208_on.All(x => x?["ParallelCount"]?.GetValue<int>() == 2)
                 && k208_in?["IsParallel"]?.GetValue<bool>() == true && k208_in?["SourceCount"]?.GetValue<int>() == 2 && k208_in?["DistinctRatios"]?.GetValue<int>() == 1,
                $"#208: the TC4-side CT paralleled into {k208_src?["InputCode"]} ({(int)k208_ms} {Code(k208_mb)} {k208_mb?["detail"]}): {k208_on.Count} CTs on it, each reading {k208_on.FirstOrDefault()?["ParallelCount"]} in parallel; the input reads parallel {k208_in?["IsParallel"]}, {k208_in?["SourceCount"]} sources, {k208_in?["DistinctRatios"]} distinct ratio ({k208_in?["Ratios"]})");
            // an input of another scheme is refused; ReadOnly may not make an input
            var (_, k208_ob) = await Get(admin, $"api/v1/document/vSettingsRecord?GridState=Active&SchemeName={Uri.EscapeDataString("2103 B-PROT")}&StationName={Uri.EscapeDataString("BATHURST TERMINAL")}&take=1");
            var (_, k208_oib) = await Get(admin, $"api/v1/scheme/vSchemeInput?SchemeEntityId={(k208_ob?["rows"] as JsonArray)?.FirstOrDefault()?["SchemeEntityId"]}&take=1");
            var k208_other = (k208_oib?["rows"] as JsonArray)?.FirstOrDefault()?["EntityId"]?.ToString();
            var (k208_xs, k208_xb) = await Post(admin, "api/v1/scheme/AddSchemeMember", new { SchemeEntityId = scheme, MemberKind = "Asset", MemberEntityId = k208_ct2, MemberRoleCode = "CtSource", IsInService = true, AnalogInputEntityId = k208_other });
            var (k208_rs, _) = await Post(readOnly!, "api/v1/scheme/AnalogInput_Add", new { SchemeEntityId = scheme, InputCode = "Current 9", InputKind = "Current" });
            Must(k208_other is not null && k208_xs == HttpStatusCode.Conflict && (k208_xb?["detail"]?.ToString() ?? "").Contains("not a current input of this scheme") && k208_rs == HttpStatusCode.Forbidden,
                $"#208: another scheme's input is refused in the rule's words ({(int)k208_xs} {k208_xb?["detail"]}); ReadOnly may not make an input ({(int)k208_rs})");
        }

        // ======== #210 (2026-09-20): reference data kept from a screen — the voltage classes added, corrected and retired through the
        // reference procedures the API exposes under the Definition class (ref → Definition): Upsert needs Definition.Modify,
        // Deactivate needs Definition.Archive. A retired code added again is reinstated.
        {
            var k210_code = $"{tag[^6..]}kV";
            var (k210_as, k210_ab) = await Post(admin, "api/v1/ref/VoltageClass_Upsert", new { VoltageClassCode = k210_code, NominalKv = 500, IsTransmission = true, DisplayOrder = 99 });
            var (_, k210_lb) = await Get(admin, $"api/v1/ref/vVoltageClass?VoltageClassCode={k210_code}&take=1");
            var k210_row = (k210_lb?["rows"] as JsonArray)?.FirstOrDefault();
            var (k210_us, _) = await Post(admin, "api/v1/ref/VoltageClass_Upsert", new { VoltageClassCode = k210_code, NominalKv = 515, IsTransmission = true, DisplayOrder = 99 });
            var (_, k210_l2b) = await Get(admin, $"api/v1/ref/vVoltageClass?VoltageClassCode={k210_code}&take=1");
            var k210_kv2 = (k210_l2b?["rows"] as JsonArray)?.FirstOrDefault()?["NominalKv"]?.GetValue<decimal>();
            var (k210_ds, k210_db) = await Post(admin, "api/v1/ref/VoltageClass_Deactivate", new { VoltageClassCode = k210_code });
            var (_, k210_l3b) = await Get(admin, $"api/v1/ref/vVoltageClass?VoltageClassCode={k210_code}&take=1");
            var k210_gone = ((k210_l3b?["rows"] as JsonArray) ?? []).Count == 0;
            var (k210_rs, _) = await Post(admin, "api/v1/ref/VoltageClass_Upsert", new { VoltageClassCode = k210_code, NominalKv = 515, IsTransmission = true, DisplayOrder = 99 });
            var (_, k210_l4b) = await Get(admin, $"api/v1/ref/vVoltageClass?VoltageClassCode={k210_code}&take=1");
            var k210_back = ((k210_l4b?["rows"] as JsonArray) ?? []).Count == 1;
            Must(k210_as == HttpStatusCode.OK && k210_row?["NominalKv"]?.GetValue<decimal>() == 500m && k210_us == HttpStatusCode.OK && k210_kv2 == 515m && k210_ds == HttpStatusCode.OK && k210_gone && k210_rs == HttpStatusCode.OK && k210_back,
                $"#210: a voltage class added ({(int)k210_as} {Code(k210_ab)}: {k210_code} = {k210_row?["NominalKv"]} kV), corrected ({k210_kv2} kV), retired ({(int)k210_ds} {Code(k210_db)}; listed {!k210_gone}) and reinstated by adding it again (listed {k210_back})");
            var (k210_ros, _) = await Post(readOnly!, "api/v1/ref/VoltageClass_Upsert", new { VoltageClassCode = k210_code + "x", NominalKv = 1, IsTransmission = false, DisplayOrder = 0 });
            var (k210_ts, _) = await Post(tech!, "api/v1/ref/VoltageClass_Upsert", new { VoltageClassCode = k210_code + "x", NominalKv = 1, IsTransmission = false, DisplayOrder = 0 });
            var (k210_tds, _) = await Post(tech!, "api/v1/ref/VoltageClass_Deactivate", new { VoltageClassCode = k210_code });
            Must(k210_ros == HttpStatusCode.Forbidden && k210_ts == HttpStatusCode.Forbidden && k210_tds == HttpStatusCode.Forbidden,
                $"#210: ReadOnly ({(int)k210_ros}) and a technician ({(int)k210_ts} add, {(int)k210_tds} retire) may not keep the reference lists");
            await Post(admin, "api/v1/ref/VoltageClass_Deactivate", new { VoltageClassCode = k210_code });   // cleanup
        }

        // ======== #187 (2026-09-18): a new relay from its position, its first settings from the template, and the record that
        // says where it is and what it wears. The owner went the intuitive way — building, panel, record — and read "no FLOC" as
        // "not placed" and could not tell whether the relay "had a template applied". No screen created a relay; "New setting
        // here" needed a settings-book row; CopyRevisionAsDraft made nothing for a device with no in-service revision.
        {
            var (k187_ps, k187_pb) = await Post(admin, "api/v1/location/AddNode", new { NodeTypeCode = "DevicePosition", ParentEntityId = panel, Name = $"{tag} 187 position", Code = "K187" });
            var k187_pos = Id(k187_pb);
            var (k187_ms, k187_mb) = await Get(admin, "api/v1/ref/vModel?ModelCode=SEL-221F&take=1");
            var k187_model = Id((k187_mb?["rows"] as JsonArray)?.FirstOrDefault(), "ModelId");
            // (1) the four writes of the New relay form, in its order; ReadOnly refused at the first
            var (k187_r0s, _) = await Post(readOnly!, "api/v1/asset/Asset_Add", new { AssetTypeCode = "ProtectiveRelay", Name = $"{tag} 187 refused", ModelId = k187_model, Status = "InService" });
            var (k187_a1s, k187_a1b) = await Post(admin, "api/v1/asset/Asset_Add", new { AssetTypeCode = "ProtectiveRelay", Name = $"{tag} 187 SEL-221F", ModelId = k187_model, Status = "InService" });
            var k187_relay = Id(k187_a1b);
            var (k187_d1s, _) = await Post(admin, "api/v1/device/Device_Add", new { EntityId = k187_relay, PartNumber = "SEL-221F" });
            var (k187_k1s, _) = await Post(admin, "api/v1/asset/AlternateKey_Add", new { SubjectEntityId = k187_relay, KeyKindCode = "SerialNumber", KeyValue = $"SN-{tag}", IsPrimaryLabel = true });
            var (k187_l1s, k187_l1b) = await Post(admin, "api/v1/asset/PlaceAsset", new { AssetEntityId = k187_relay, NodeEntityId = k187_pos, PlacementKind = "Installed" });
            var (k187_g1s, k187_g1b) = await Get(admin, $"api/v1/asset/vPlacedAsset?NodeEntityId={k187_pos}&take=5");
            var k187_placed = (k187_g1b?["rows"] as JsonArray)?.FirstOrDefault();
            Must(k187_ps == HttpStatusCode.OK && k187_model is not null && k187_r0s == HttpStatusCode.Forbidden && k187_a1s == HttpStatusCode.OK && k187_d1s == HttpStatusCode.OK && k187_k1s == HttpStatusCode.OK
                 && k187_l1s == HttpStatusCode.OK && k187_placed?["AssetEntityId"]?.ToString().Equals(k187_relay?.ToString(), StringComparison.OrdinalIgnoreCase) == true,
                $"#187: a new SEL-221F is created, given its device row and serial, and installed at a fresh position in four writes ({(int)k187_a1s} {(int)k187_d1s} {(int)k187_k1s} {(int)k187_l1s} {Code(k187_l1b)}); ReadOnly is refused ({(int)k187_r0s})");
            // (2) New setting from the position: SETTINGS_ADD raised, [1] committed with the trigger, [2] drafted with the relay,
            //     then [2] committed the way the engineer will — the empty first draft appears Outstanding, parsed to no rows,
            //     with the model's template behind it
            var (k187_w0s, k187_w0b) = await Get(admin, "api/v1/config/vDefinition?DefinitionKind=Program.WorkType&DefinitionKey=SETTINGS_ADD&take=1");
            var (k187_w1s, k187_w1b) = await Get(admin, $"api/v1/config/vDefinitionVersion?DefinitionEntityId={Id((k187_w0b?["rows"] as JsonArray)?.FirstOrDefault())}&Status=Effective&take=1");
            var k187_wt = Id((k187_w1b?["rows"] as JsonArray)?.FirstOrDefault(), "RowId");
            var (k187_wrs, k187_wrb) = await Post(admin, "api/v1/work/WorkRequest_Add", new { WorkTypeDefinitionVersionRowId = k187_wt, Title = $"{tag} new setting (#187)", ScopeKind = "Node", ScopeEntityId = k187_pos });
            var k187_wr = Id(k187_wrb);
            var (k187_sws, k187_swb) = await Post(admin, "api/v1/process/workflows/start", new { workflowKey = "SETTINGS_CHANGE_REQUEST", subjectKind = "WorkRequest", subjectEntityId = k187_wr });
            var k187_wf = Id(k187_swb, "workflowInstanceEntityId");
            var (k187_trs, _) = await Post(admin, $"api/v1/process/workflow-instances/{k187_wf}/transitions", new { name = "Start" });
            var (_, k187_pib) = await Get(admin, $"api/v1/process/vProcedureInstance?WorkRequestEntityId={k187_wr}");
            var k187_inst = Id((k187_pib?["rows"] as JsonArray)?.FirstOrDefault(r => r?["ParentInstanceEntityId"] is null));
            var k187_saved = inst; inst = k187_inst;   // RunStep and ReadyStep read this instance now
            var (k187_s1s, _) = await RunStep(admin, "REQUEST", new { outcome = "Done", capture = new { trigger = "Project", sourceReference = $"first settings for {tag} 187 SEL-221F" } });
            var k187_scope = await ReadyStep("SCOPE", null, 2);
            var (k187_cls, _) = await Post(admin, $"api/v1/process/step-instances/{k187_scope}/claim", new { });
            var (k187_drs, _) = await Post(admin, $"api/v1/process/step-instances/{k187_scope}/draft", new { draft = new { devices = new[] { k187_relay } } });
            var (_, k187_rdb) = await Get(admin, $"api/v1/process/step-instances/{k187_scope}");
            var k187_drafted = (k187_rdb?["draft"]?["devices"] as JsonArray)?.FirstOrDefault()?.ToString();
            var (k187_s2s, k187_s2b) = await Post(admin, $"api/v1/process/step-instances/{k187_scope}/commit", new { outcome = "Done", capture = new { scheme = scheme, philosophy = "first settings (#187 smoke)", devices = new[] { k187_relay } } });
            inst = k187_saved;
            var (_, k187_recb) = await Get(admin, $"api/v1/document/vSettingsRecord?DeviceEntityId={k187_relay}&take=5");
            var k187_rec = (k187_recb?["rows"] as JsonArray)?.FirstOrDefault();
            var (k187_prs, k187_prb) = await Get(admin, $"api/v1/document/vParsedSettingNamed?ConfigurationFileRevisionRowId={k187_rec?["RevisionRowId"]}&take=5");
            var k187_parsed = (k187_prb?["rows"] as JsonArray)?.Count ?? -1;
            Must(k187_wt is not null && k187_wrs == HttpStatusCode.OK && k187_sws == HttpStatusCode.OK && k187_trs == HttpStatusCode.OK && k187_inst is not null && k187_s1s == HttpStatusCode.OK
                 && k187_cls == HttpStatusCode.OK && k187_drs == HttpStatusCode.OK && string.Equals(k187_drafted, k187_relay?.ToString(), StringComparison.OrdinalIgnoreCase) && k187_s2s == HttpStatusCode.OK,
                $"#187: SETTINGS_ADD from the position — [1] committed with its trigger, [2] claimed and drafted with the relay (draft reads back {k187_drafted?[..8]}), [2] committed ({(int)k187_s2s} {Code(k187_s2b)})");
            Must(k187_rec is not null && k187_rec["GridState"]?.ToString() == "Outstanding" && k187_rec["RevisionStatus"]?.ToString() == "Draft" && k187_rec["FileKind"]?.ToString() == "SettingsText" && k187_prs == HttpStatusCode.OK && k187_parsed == 0
                 && k187_rec["TemplateKey"]?.ToString() == "SEL221F_Template" && k187_rec["PlacedFrom"] is not null && k187_rec["SerialNumber"]?.ToString() == $"SN-{tag}",
                $"#187: the relay's first record is an Outstanding Draft SettingsText with no parsed rows ({k187_parsed}) — every template setting \"not set\" — and the record says PlacedFrom {k187_rec?["PlacedFrom"]?.ToString()[..10]}, serial {k187_rec?["SerialNumber"]}, template {k187_rec?["TemplateKey"]} v{k187_rec?["TemplateVersion"]}");
            // (3) the fixture's SEL-421 has no template: TemplateKey NULL, PlacedFrom set; the two are different facts
            var (_, k187_selb) = await Get(admin, $"api/v1/document/vSettingsRecord?DeviceEntityId={devSel}&GridState=Active&take=1");
            var k187_sel = (k187_selb?["rows"] as JsonArray)?.FirstOrDefault();
            Must(k187_sel is not null && k187_sel["TemplateKey"] is null && k187_sel["PlacedFrom"] is not null && k187_sel["PositionNodeEntityId"] is not null,
                $"#187: the SEL-421 record carries its placement (since {k187_sel?["PlacedFrom"]?.ToString()[..10]}) and no template — the model has none");
        }

        // ======== #168 increment 2 (2026-09-16): the settings edited in the platform, the file written by it — the owner's four-step
        // procedure on the BDD15B that the run above left in service. REQUEST copies the in-service revision as the change's outstanding
        // revision (the legacy M from the A); a value is edited through SetParsedSetting; the settings step commits with no file and
        // the platform writes the file from the rows; the file re-read is the rows (the round trip, in place); install and complete:
        // the copy goes in service and the previous revision is archived.
        {
            async Task<bool> LoadApprove(string file, string what)
            {
                var (ls9, lb9) = await Post(author!, "api/v1/definitions/documents", new { document = JsonNode.Parse(Example(file)), changeNote = "#168 smoke" });
                var row9 = lb9?["versionRowId"]?.ToString();
                if (ls9 != HttpStatusCode.OK || row9 is null) { Must(false, $"#168: load {what} → {(int)ls9} {Code(lb9)} {lb9?["detail"]}"); return false; }
                var (as9, ab9) = await Post(approver, $"api/v1/definitions/documents/{row9}/approve", new { });
                var ok9 = as9 == HttpStatusCode.OK || AlreadyApproved(ab9);
                Must(ok9, $"#168: {what} Effective ({(int)as9} {Code(ab9)})");
                return ok9;
            }
            var okL = await LoadApprove("settings-lifecycle-simple.workflow.json", "SETTINGS_LIFECYCLE_SIMPLE");
            var okP = await LoadApprove("settings-change-simple.procedure.json", "SETTINGS_CHANGE_SIMPLE");
            var okW = await LoadApprove("settings-change-simple.workflow.json", "SETTINGS_CHANGE_REQUEST_SIMPLE");
            var simpleType = await Definition("Program.WorkType", $"{tag}_SETTINGS_CHANGE_SIMPLE", "Settings change, four steps (#168 smoke)", new { g = 1, workflow = "SETTINGS_CHANGE_REQUEST_SIMPLE", requiredRecordKinds = Array.Empty<string>() });
            async Task<string> Rendered(Guid? rev) { var r = await admin.GetAsync($"api/v1/settings/{rev}/rendered"); return r.StatusCode == HttpStatusCode.OK ? await r.Content.ReadAsStringAsync() : $"<{(int)r.StatusCode}>"; }
            async Task<JsonNode?> Record(Guid? dev, string state) { var (_, b) = await Get(admin, $"api/v1/document/vSettingsRecord?DeviceEntityId={dev}&GridState={state}"); return (b?["rows"] as JsonArray)?.OrderByDescending(r => r?["RowSeq"]?.GetValue<long>()).FirstOrDefault(); }
            async Task<Dictionary<string, string>> Parsed(Guid? rev) { var (_, b) = await Get(admin, $"api/v1/document/vParsedSettingNamed?ConfigurationFileRevisionRowId={rev}"); return (b?["rows"] as JsonArray)?.ToDictionary(r => r?["SettingCode"]?.ToString() ?? "", r => r?["RawValue"]?.ToString() ?? "") ?? new(); }
            var aRow = await Record(devBdd, "Active"); var aRev = Id(aRow, "RevisionRowId");
            Must(okL && okP && okW && simpleType is not null && aRev is not null, $"#168 fixture: the four-step documents Effective, a work type bound, the BDD15B in service (revision {aRow?["RevisionLabel"]})");
            if (okL && okP && okW && simpleType is not null && aRev is not null)
            {
                var aText = await Rendered(aRev); var aParsed = await Parsed(aRev);
                var (wr9s, wr9b) = await Post(admin, "api/v1/work/WorkRequest_Add", new { WorkTypeDefinitionVersionRowId = simpleType, Title = $"{tag} slope change (#168)", ScopeKind = "Node", ScopeEntityId = station, OutageRequired = false });
                var wr9 = Id(wr9b);
                var (sw9s, sw9b) = await Post(admin, "api/v1/process/workflows/start", new { workflowKey = "SETTINGS_CHANGE_REQUEST_SIMPLE", subjectKind = "WorkRequest", subjectEntityId = wr9 });
                var wf9 = Id(sw9b, "workflowInstanceEntityId");
                var (tr9s, tr9b) = await Post(admin, $"api/v1/process/workflow-instances/{wf9}/transitions", new { name = "Start" });
                var (pi9s, pi9b) = await Get(admin, $"api/v1/process/vProcedureInstance?WorkflowInstanceEntityId={wf9}");
                var inst9 = Id((pi9b?["rows"] as JsonArray)?.FirstOrDefault(r => r?["ParentInstanceEntityId"] is null));
                Must(wr9s == HttpStatusCode.OK && sw9s == HttpStatusCode.OK && tr9s == HttpStatusCode.OK && inst9 is not null, $"#168: a request under the four-step work type started ({(int)wr9s} {Code(wr9b)} · {(int)sw9s} {Code(sw9b)} · {(int)tr9s} {Code(tr9b)} · instance {inst9})");
                if (inst9 is not null)
                {
                    inst = inst9;   // RunStep and ReadyStep read this instance now
                    // [1] request: the copy appears as the outstanding revision, its rows the in-service rows
                    var (q1s, q1b) = await RunStep(admin, "REQUEST", new { outcome = "Done", capture = new { reason = "#168 smoke: SLOPE 25 → 30 %", devices = new[] { devBdd } } });
                    var pkg9 = Id(q1b, "producedEntityId");
                    var mRow = await Record(devBdd, "Outstanding"); var mRev = Id(mRow, "RevisionRowId");
                    var (it9s, it9b) = await Get(admin, $"api/v1/document/vSettingsIssuePackageItem?PackageRevisionRowId={pkg9}");
                    var items9 = (it9b?["rows"] as JsonArray)?.Select(r => r?["ConfigurationFileRevisionRowId"]?.ToString()?.ToLowerInvariant()).ToList() ?? [];
                    Must(pkg9 is not null && mRev is not null && mRev != aRev && items9.Count == 1 && items9[0] == mRev.ToString()!.ToLowerInvariant(),
                        $"#168 [1]: REQUEST copied the in-service revision {aRow?["RevisionLabel"]} as outstanding revision {mRow?["RevisionLabel"]}, the package's one item ({items9.Count} item(s))");
                    var mParsed = await Parsed(mRev); var mText = await Rendered(mRev);
                    Must(mRev is not null && mParsed.Count == aParsed.Count && mParsed.All(kv => aParsed.TryGetValue(kv.Key, out var v) && v == kv.Value) && mText == aText,
                        $"#168 [1]: the copy's parsed rows are the in-service rows ({mParsed.Count} of {aParsed.Count}), rendered alike ({mText.Length} chars)");
                    // the edit: read as the parser reads it; the refusals in the procedure's words
                    var (e1s, e1b) = await Post(admin, "api/v1/process/SetParsedSetting", new { ConfigurationFileRevisionRowId = mRev, DeviceEntityId = devBdd, SettingCode = "SLOPE", RawValue = "30 %" });
                    Must(e1s == HttpStatusCode.OK && e1b?["RangeCheck"]?.ToString() == "Ok", $"#168 edit: SLOPE=30 % on the outstanding revision → {(int)e1s} {Code(e1b)} {e1b?["detail"]} (range {e1b?["RangeCheck"]})");
                    var (e2s, e2b) = await Post(admin, "api/v1/process/SetParsedSetting", new { ConfigurationFileRevisionRowId = mRev, DeviceEntityId = devBdd, SettingCode = "SLOPE", RawValue = "steep" });
                    Must(e2s == HttpStatusCode.Conflict && (e2b?["detail"]?.ToString() ?? "").Contains("takes a number"), $"#168 edit: a word where a number is due → 409 rule in the procedure's words ({(int)e2s} {Code(e2b)} {e2b?["detail"]})");
                    var (e3s, e3b) = await Post(admin, "api/v1/process/SetParsedSetting", new { ConfigurationFileRevisionRowId = mRev, DeviceEntityId = devBdd, SettingCode = "NOSUCH", RawValue = "1" });
                    Must(e3s == HttpStatusCode.Conflict && (e3b?["detail"]?.ToString() ?? "").Contains("does not know"), $"#168 edit: a code the template does not know → 409 rule ({(int)e3s} {e3b?["detail"]})");
                    var (e4s, e4b) = await Post(admin, "api/v1/process/SetParsedSetting", new { ConfigurationFileRevisionRowId = aRev, DeviceEntityId = devBdd, SettingCode = "SLOPE", RawValue = "30 %" });
                    Must(e4s == HttpStatusCode.Conflict && (e4b?["detail"]?.ToString() ?? "").Contains("outstanding"), $"#168 edit: the in-service revision is the record, not edited → 409 rule ({(int)e4s} {e4b?["detail"]})");
                    var (e5s, e5b) = await Post(admin, "api/v1/process/SetParsedSetting", new { ConfigurationFileRevisionRowId = mRev, DeviceEntityId = devBdd, SettingCode = "SLOPE", RawValue = "55" });
                    Must(e5s == HttpStatusCode.OK && e5b?["RangeCheck"]?.ToString() == "OutOfRange", $"#168 edit: 55 % is outside 15–40: saved and flagged, not refused ({(int)e5s} range {e5b?["RangeCheck"]}: {e5b?["RangeCheckNote"]})");
                    var (e6s, _) = await Post(admin, "api/v1/process/SetParsedSetting", new { ConfigurationFileRevisionRowId = mRev, DeviceEntityId = devBdd, SettingCode = "SLOPE", RawValue = "30 %" });
                    var (e7s, e7b) = await Post(readOnly!, "api/v1/process/SetParsedSetting", new { ConfigurationFileRevisionRowId = mRev, DeviceEntityId = devBdd, SettingCode = "SLOPE", RawValue = "31 %" });
                    Must(e6s == HttpStatusCode.OK && e7s == HttpStatusCode.Forbidden, $"#168 edit: back to 30 % ({(int)e6s}); ReadOnly may not edit ({(int)e7s} {Code(e7b)})");
                    var afterEdit = await Parsed(mRev);
                    var (al9s, al9b) = await Get(admin, $"api/v1/audit/vActionLog?SubjectRowId={mRev}&take=50");
                    var edits9 = (al9b?["rows"] as JsonArray)?.Count(r => (r?["Detail"]?.ToString() ?? "").Contains("setting-edited")) ?? 0;
                    Must(afterEdit.GetValueOrDefault("SLOPE") == "30 %" && edits9 >= 3, $"#168 edit: the row reads 30 % as typed; {edits9} edits in the audit log with code, from and to");
                    // [2] rationale and settings side by side: the settings step commits with NO file — the platform writes it
                    await RunStep(admin, "WRITE_RATIONALE", new { outcome = "Done", evidence = new[] { File("rationale.txt", "text/plain", "#168 smoke: slope raised to 30 % after the CT saturation study", "Rationale") } });
                    var (c9s, c9b) = await RunStep(admin, "RECORD_SETTINGS", new { outcome = "Done" }, devBdd);
                    var (rc9s, rc9b) = await Get(admin, $"api/v1/record/vRecord?WorkRequestEntityId={wr9}&RecordKindCode=ConfigurationFileRevision");
                    var rec9 = (rc9b?["rows"] as JsonArray)?.FirstOrDefault();
                    Must(c9s == HttpStatusCode.OK && (rec9?["Summary"]?.ToString() ?? "").Contains("written by the platform") && rec9?["SecondSubjectEntityId"]?.ToString()?.ToLowerInvariant() == mRev.ToString()!.ToLowerInvariant(),
                        $"#168 [2]: the settings step committed with no file; the record says the platform wrote it and points at the outstanding revision ({rec9?["Summary"]})");
                    var (f9s, f9b) = await Get(admin, $"api/v1/document/vFile?RevisionRowId={mRev}&FileRole=Native");
                    var files9 = (f9b?["rows"] as JsonArray) ?? new JsonArray();
                    var mText2 = await Rendered(mRev);
                    string filedText = "";
                    if (files9.Count == 1) { var dl9 = await admin.GetAsync($"api/v1/files/{files9[0]?["RowId"]}"); filedText = System.Text.Encoding.UTF8.GetString(await dl9.Content.ReadAsByteArrayAsync()); }
                    var mRow2 = await Record(devBdd, "Outstanding"); var reread = await Parsed(mRev);
                    Must(files9.Count == 1 && filedText == mText2 && mText2.Contains("SLOPE=30 %") && mRow2?["ParseStatus"]?.ToString() == "Parsed" && reread.GetValueOrDefault("SLOPE") == "30 %" && reread.Count == afterEdit.Count,
                        $"#168 [2]: one Native file on the revision ({files9[0]?["FileName"]}), byte-identical to the rendered text, re-read Parsed with the same rows — the round trip ({mText2})");
                    var (it9s2, it9b2) = await Get(admin, $"api/v1/document/vSettingsIssuePackageItem?PackageRevisionRowId={pkg9}");
                    Must((it9b2?["rows"] as JsonArray)?.Count == 1, "#168 [2]: still one item in the package (the copy took the file; no second revision)");
                    // [3] the outage hold releases on evaluate (no outage required); [4] install as the technician, complete as the engineer
                    await Post(admin, $"api/v1/process/procedure-instances/{inst9}/evaluate", new { }); await Post(admin, $"api/v1/process/procedure-instances/{inst9}/evaluate", new { });
                    var (i9s, _) = await RunStep(tech, "INSTALL", new { outcome = "Done", capture = new { installedAt = DateTime.UtcNow.ToString("o"), commissioningNote = "#168 smoke" } }, devBdd);
                    var (k9s, _) = await RunStep(admin, "COMPLETE", new { outcome = "Done" });
                    var aAfter = await Record(devBdd, "Active"); var pAfter = await Record(devBdd, "Archived");
                    var (cl9s, cl9b) = await Post(admin, $"api/v1/process/workflow-instances/{wf9}/transitions", new { name = "Close" });
                    Must(i9s == HttpStatusCode.OK && k9s == HttpStatusCode.OK && Id(aAfter, "RevisionRowId") == mRev && Id(pAfter, "RevisionRowId") == aRev && cl9s == HttpStatusCode.OK,
                        $"#168 [4]: the copy is in service (revision {aAfter?["RevisionLabel"]}), the previous revision archived (revision {pAfter?["RevisionLabel"]}), the request Closed ({(int)cl9s} {Code(cl9b)})");
                    var final9 = await Rendered(mRev);
                    Must(final9 == filedText, "#168: the in-service revision's rendered text is still its filed file, byte for byte");

                    // ======== #191 (2026-09-18): a second change while one is open — based on the first's current settings, and
                    // not in service before it. The owner: the second "took the existing work request data as the starting point
                    // and could only be completed after the completion of the first".
                    async Task<(Guid? wr, Guid? wf, Guid? inst)> Raise(string title)
                    {
                        var (ws, wb) = await Post(admin, "api/v1/work/WorkRequest_Add", new { WorkTypeDefinitionVersionRowId = simpleType, Title = title, ScopeKind = "Asset", ScopeEntityId = devBdd, OutageRequired = false });
                        var (ss, sb) = await Post(admin, "api/v1/process/workflows/start", new { workflowKey = "SETTINGS_CHANGE_REQUEST_SIMPLE", subjectKind = "WorkRequest", subjectEntityId = Id(wb) });
                        await Post(admin, $"api/v1/process/workflow-instances/{Id(sb, "workflowInstanceEntityId")}/transitions", new { name = "Start" });
                        var (_, pb) = await Get(admin, $"api/v1/process/vProcedureInstance?WorkflowInstanceEntityId={Id(sb, "workflowInstanceEntityId")}");
                        return (ws == HttpStatusCode.OK && ss == HttpStatusCode.OK ? Id(wb) : null, Id(sb, "workflowInstanceEntityId"), Id((pb?["rows"] as JsonArray)?.FirstOrDefault(r => r?["ParentInstanceEntityId"] is null)));
                    }
                    var (wrA, wfA, instA) = await Raise($"{tag} A: slope 35 (#191)");
                    inst = instA;
                    var (a1s, _) = await RunStep(admin, "REQUEST", new { outcome = "Done", capture = new { reason = "#191 A", devices = new[] { devBdd } } });
                    var draftA = Id(await Record(devBdd, "Outstanding"), "RevisionRowId");
                    var (ea, _) = await Post(admin, "api/v1/process/SetParsedSetting", new { ConfigurationFileRevisionRowId = draftA, DeviceEntityId = devBdd, SettingCode = "SLOPE", RawValue = "35 %" });
                    var (wrB, wfB, instB) = await Raise($"{tag} B: based on A (#191)");
                    inst = instB;
                    var (b1s, _) = await RunStep(admin, "REQUEST", new { outcome = "Done", capture = new { reason = "#191 B", devices = new[] { devBdd } } });
                    var (_, outB) = await Get(admin, $"api/v1/document/vSettingsRecord?DeviceEntityId={devBdd}&GridState=Outstanding");
                    var outRows = (outB?["rows"] as JsonArray) ?? new JsonArray();
                    var rowB = outRows.FirstOrDefault(r => string.Equals(r?["WorkRequestEntityId"]?.ToString(), wrB?.ToString(), StringComparison.OrdinalIgnoreCase));
                    var draftB = Id(rowB, "RevisionRowId"); var parsedB = await Parsed(draftB);
                    Must(a1s == HttpStatusCode.OK && ea == HttpStatusCode.OK && b1s == HttpStatusCode.OK && outRows.Count == 2 && draftB is not null && draftB != draftA
                         && parsedB.GetValueOrDefault("SLOPE") == "35 %" && string.Equals(rowB?["BasedOnWorkRequestEntityId"]?.ToString(), wrA?.ToString(), StringComparison.OrdinalIgnoreCase) && rowB?["BasedOnGridState"]?.ToString() == "Outstanding",
                        $"#191: B's draft starts from A's current settings (SLOPE {parsedB.GetValueOrDefault("SLOPE")}, not the in-service 30 %), two outstanding records, B based on A ({rowB?["BasedOnWorkRequestTitle"]}, {rowB?["BasedOnGridState"]})");
                    // B runs ahead to its completion — refused while A is a draft
                    await RunStep(admin, "WRITE_RATIONALE", new { outcome = "Done", evidence = new[] { File("rationale.txt", "text/plain", "#191 B", "Rationale") } });
                    await RunStep(admin, "RECORD_SETTINGS", new { outcome = "Done" }, devBdd);
                    await Post(admin, $"api/v1/process/procedure-instances/{instB}/evaluate", new { }); await Post(admin, $"api/v1/process/procedure-instances/{instB}/evaluate", new { });
                    await RunStep(tech, "INSTALL", new { outcome = "Done", capture = new { installedAt = DateTime.UtcNow.ToString("o"), commissioningNote = "#191 B" } }, devBdd);
                    var stepB = await ReadyStep("COMPLETE", null, 2);
                    var (cbs, _) = await Post(admin, $"api/v1/process/step-instances/{stepB}/claim", new { });
                    // ======== #192 (2026-09-18): A changes after B was taken from it — B is flagged, blocked, and re-based
                    async Task<(JsonArray rows, JsonNode? head)> Drift(Guid? rev) { var (_, b) = await Post(admin, "api/v1/process/BasisDrift", new { RevisionRowId = rev, DeviceEntityId = devBdd }); var rs = b?["results"] as JsonArray; var attention = new JsonArray(); foreach (var x in (rs?[0] as JsonArray) ?? new JsonArray()) if (x?["Outcome"]?.ToString() is "take" or "agree" or "conflict") attention.Add(x?.DeepClone()); return (attention, (rs?[1] as JsonArray)?.FirstOrDefault()); }   // only the rows that need attention: a row where only mine moved is not drift
                    var (ea2, _) = await Post(admin, "api/v1/process/SetParsedSetting", new { ConfigurationFileRevisionRowId = draftA, DeviceEntityId = devBdd, SettingCode = "SLOPE", RawValue = "38 %" });
                    var (dr1, dh1) = await Drift(draftB); var d1 = dr1.FirstOrDefault();
                    Must(ea2 == HttpStatusCode.OK && dr1.Count == 1 && d1?["SettingCode"]?.ToString() == "SLOPE" && d1?["ThenValue"]?.ToString() == "35 %" && d1?["NowValue"]?.ToString() == "38 %" && d1?["MineValue"]?.ToString() == "35 %" && d1?["Outcome"]?.ToString() == "take" && dh1?["HasFrozenBasis"]?.ToString() == "1",
                        $"#192: A moved SLOPE to 38 % after B was taken — B's drift is one row: then {d1?["ThenValue"]}, theirs {d1?["NowValue"]}, mine {d1?["MineValue"]}, outcome {d1?["Outcome"]}; a frozen basis exists ({dh1?["HasFrozenBasis"]})");
                    var (bl1s, bl1b) = await Post(admin, $"api/v1/process/step-instances/{stepB}/commit", new { outcome = "Done" });
                    Must(bl1s != HttpStatusCode.OK && (bl1b?["detail"]?.ToString() ?? "").Contains("changed since") && (bl1b?["detail"]?.ToString() ?? "").Contains("SLOPE"),
                        $"#192: B's baseline is refused while its basis has changed ({(int)bl1s} {Code(bl1b)}: {bl1b?["detail"]})");
                    var (rb1s, rb1b) = await Post(admin, "api/v1/process/RebaseDraft", new { RevisionRowId = draftB, DeviceEntityId = devBdd });
                    var afterRb1 = await Parsed(draftB); var (dr2, _) = await Drift(draftB);
                    Must(rb1s == HttpStatusCode.OK && rb1b?["Applied"]?.ToString() == "1" && afterRb1.GetValueOrDefault("SLOPE") == "38 %" && dr2.Count == 0,
                        $"#192: re-based — theirs applied ({rb1b?["Applied"]}), B reads SLOPE {afterRb1.GetValueOrDefault("SLOPE")}, no drift left ({dr2.Count})");
                    // a conflict: both moved, differently — decided by the engineer, never merged silently
                    await Post(admin, "api/v1/process/SetParsedSetting", new { ConfigurationFileRevisionRowId = draftA, DeviceEntityId = devBdd, SettingCode = "SLOPE", RawValue = "40 %" });
                    await Post(admin, "api/v1/process/SetParsedSetting", new { ConfigurationFileRevisionRowId = draftB, DeviceEntityId = devBdd, SettingCode = "SLOPE", RawValue = "39 %" });
                    var (dr3, _) = await Drift(draftB); var d3 = dr3.FirstOrDefault();
                    var (rb2s, rb2b) = await Post(admin, "api/v1/process/RebaseDraft", new { RevisionRowId = draftB, DeviceEntityId = devBdd });
                    var (rb3s, _) = await Post(readOnly!, "api/v1/process/RebaseDraft", new { RevisionRowId = draftB, DeviceEntityId = devBdd, Decisions = "{\"SLOPE\":\"mine\"}" });
                    var (rb4s, rb4b) = await Post(admin, "api/v1/process/RebaseDraft", new { RevisionRowId = draftB, DeviceEntityId = devBdd, Decisions = "{\"SLOPE\":\"mine\"}" });
                    var afterRb4 = await Parsed(draftB); var (dr4, _) = await Drift(draftB);
                    Must(d3?["Outcome"]?.ToString() == "conflict" && rb2s != HttpStatusCode.OK && (rb2b?["detail"]?.ToString() ?? "").Contains("SLOPE") && rb3s == HttpStatusCode.Forbidden
                         && rb4s == HttpStatusCode.OK && rb4b?["Kept"]?.ToString() == "1" && afterRb4.GetValueOrDefault("SLOPE") == "39 %" && dr4.Count == 0,
                        $"#192: A 40 % vs B 39 % is a conflict ({d3?["Outcome"]}); a re-base without a decision is refused ({(int)rb2s}: {rb2b?["detail"]}); ReadOnly refused ({(int)rb3s}); decided \"mine\" → kept ({rb4b?["Kept"]}), B reads {afterRb4.GetValueOrDefault("SLOPE")}, no drift ({dr4.Count})");
                    // and now the #191 ordering rule is what stands between B and service
                    var (rbs, rbb) = await Post(admin, $"api/v1/process/step-instances/{stepB}/commit", new { outcome = "Done" });
                    Must(cbs == HttpStatusCode.OK && rbs != HttpStatusCode.OK && (rbb?["detail"]?.ToString() ?? "").Contains("not yet in service"),
                        $"#191: B cannot go in service before A — refused ({(int)rbs} {Code(rbb)}: {rbb?["detail"]})");
                    // A completes; then B can
                    inst = instA;
                    await RunStep(admin, "WRITE_RATIONALE", new { outcome = "Done", evidence = new[] { File("rationale.txt", "text/plain", "#191 A", "Rationale") } });
                    await RunStep(admin, "RECORD_SETTINGS", new { outcome = "Done" }, devBdd);
                    await Post(admin, $"api/v1/process/procedure-instances/{instA}/evaluate", new { }); await Post(admin, $"api/v1/process/procedure-instances/{instA}/evaluate", new { });
                    await RunStep(tech, "INSTALL", new { outcome = "Done", capture = new { installedAt = DateTime.UtcNow.ToString("o"), commissioningNote = "#191 A" } }, devBdd);
                    var (kas, _) = await RunStep(admin, "COMPLETE", new { outcome = "Done" });
                    var activeAfterA = Id(await Record(devBdd, "Active"), "RevisionRowId");
                    var (rbs2, rbb2) = await Post(admin, $"api/v1/process/step-instances/{stepB}/commit", new { outcome = "Done" });
                    var activeAfterB = Id(await Record(devBdd, "Active"), "RevisionRowId");
                    var (_, archB) = await Get(admin, $"api/v1/document/vSettingsRecord?DeviceEntityId={devBdd}&GridState=Archived");
                    var aArchived = (archB?["rows"] as JsonArray)?.Any(r => Id(r, "RevisionRowId") == draftA) == true;
                    Must(kas == HttpStatusCode.OK && activeAfterA == draftA && rbs2 == HttpStatusCode.OK && activeAfterB == draftB && aArchived,
                        $"#191: A in service first ({(int)kas}), then B ({(int)rbs2} {Code(rbb2)} {rbb2?["detail"]}) — B is the Active record, A archived");
                    await Post(admin, $"api/v1/process/workflow-instances/{wfA}/transitions", new { name = "Close" }); await Post(admin, $"api/v1/process/workflow-instances/{wfB}/transitions", new { name = "Close" });
                }
            }
        }
    }
}
else Skip("W4 run (needs the Administrator, Approver, Hydro and Technician identities in one process — DEV mode)");

// ======================================================================= W5 (part 2) — the authoring screen's surface and the dry run
// The screen itself is observed in Chrome (the gate record); here: the files the shell serves under the CSP, the dry run
// (schema, grammar, the database's rules — nothing stored), the read-back with expressions as text, /me's permissions.
{
    var who = admin ?? readOnly ?? approver ?? hydro ?? tech;
    if (who is not null)
    {
        foreach (var path in new[] { "", "definitions.html", "definitions.js", "pnc.js", "app.js", "styles.css", "sw.js", "floc.html", "floc.js", "app/", "app/s/SETTINGS_BOOK", "app/s/REQUEST_QUEUE" })
        {
            var r = await who.GetAsync(path);
            var csp = r.Headers.TryGetValues("Content-Security-Policy", out var v) ? string.Join("", v) : "";
            var bodyText = await r.Content.ReadAsStringAsync();
            var ok = r.StatusCode == HttpStatusCode.OK && csp.Contains("script-src 'self'") && !bodyText.Contains("<script>") && !bodyText.Contains("style=\"");
            if (path == "sw.js") ok = ok && bodyText.Contains("\"/definitions.js\"") && bodyText.Contains("\"/pnc.js\"") && bodyText.Contains("\"/floc.js\"") && !bodyText.Contains("\"/settings.js\"") && bodyText.Contains("shell-11");
            Check(ok, $"GET /{path} → {(int)r.StatusCode}, CSP script-src 'self', no inline script or style{(path == "sw.js" ? ", the editor files in the shell list" : "")}");
        }
        // #190: the React app is the PWA - the manifest starts it at /app/ and carries PNG icons (Chrome install criteria)
        var mf = await who.GetAsync("manifest.webmanifest"); var mfText = await mf.Content.ReadAsStringAsync();
        var ic = await who.GetAsync("icon-192.png"); var ic2 = await who.GetAsync("icon-512.png");
        Check(mf.StatusCode == HttpStatusCode.OK && (mf.Content.Headers.ContentType?.MediaType ?? "").Contains("manifest") && mfText.Contains("\"start_url\": \"/app/\"") && mfText.Contains("\"display\": \"standalone\"")
              && ic.StatusCode == HttpStatusCode.OK && ic.Content.Headers.ContentType?.MediaType == "image/png" && ic2.StatusCode == HttpStatusCode.OK,
            $"#190: the manifest ({mf.Content.Headers.ContentType?.MediaType}) starts the PWA at /app/ standalone, with PNG icons 192 ({(int)ic.StatusCode}) and 512 ({(int)ic2.StatusCode})");
        var (ms, mb) = await Get(who, "api/v1/me");
        Check(ms == HttpStatusCode.OK && mb?["permissions"] is JsonArray, "/me carries the permission codes of the roles in force");
        // W6: the parity read models are catalogued with the subject column that scopes them (decision #127)
        var (cts, ctb) = await Get(who, "api/v1/catalog");
        string? Scope(string schema, string name) => (ctb?["views"] as JsonArray)?.FirstOrDefault(v => v?["schema"]?.ToString() == schema && v?["name"]?.ToString() == name)?["scope"]?.ToString();
        string? Perm(string schema, string name) => (ctb?["views"] as JsonArray)?.FirstOrDefault(v => v?["schema"]?.ToString() == schema && v?["name"]?.ToString() == name)?["permission"]?.ToString();
        Check(Scope("document", "vSettingsRecord") == "DeviceEntityId as Asset" && Perm("document", "vSettingsRecord") == "ConfigurationFile.Read", $"catalog: document.vSettingsRecord scoped by device, ConfigurationFile.Read ({Scope("document", "vSettingsRecord")}, {Perm("document", "vSettingsRecord")})");
        Check(Scope("work", "vChangeRequestStatus") == "WorkRequestEntityId as WorkRequest" && Scope("location", "vFloc") == "NodeEntityId as Node" && Scope("location", "vFlocScheme") == "NodeEntityId as Node" && Scope("document", "vParsedSettingNamed") == "DeviceEntityId as Asset",
            "catalog: vChangeRequestStatus by work request, vFloc and vFlocScheme by node, vParsedSettingNamed by device");
        // definitions and reference data read class-wide by any role carrying Definition.Read, whatever the grant's scope (owner, W6 card H, #134):
        // the subtree-scoped Hydro engineer was refused 403 here by the 0.6.0 gate run, and the action-type list was empty for them
        var (wts, wtb) = await Get(who, "api/v1/config/vDefinition?DefinitionKind=Program.WorkType&take=500");
        var wtKeys = (wtb?["rows"] as JsonArray)?.Select(r => r?["DefinitionKey"]?.ToString()).ToHashSet() ?? new HashSet<string?>();
        Check(wts == HttpStatusCode.OK && new[] { "SETTINGS_CHANGE", "SETTINGS_ADD", "SETTINGS_DELETE", "SETTINGS_VERIFY" }.All(wtKeys.Contains), $"the four legacy action types are seeded as Program.WorkType definitions and readable by this identity whatever its scope (#131, #134) → {(int)wts}");
        var (gws, gwb) = await Get(who, "api/v1/document/vSettingsRecord?GridState=Active&take=5");
        Check(gws == HttpStatusCode.OK, $"the settings grid answers this identity ({(int)gws}, {(gwb?["rows"] as JsonArray)?.Count} of up to 5 rows)");
    }
    if (readOnly is not null)
    {
        var (mrs, mrb) = await Get(readOnly, "api/v1/me");
        var perms = (mrb?["permissions"] as JsonArray)?.Select(x => x?.ToString()).ToList() ?? [];
        Check(perms.Contains("Definition.Read") && !perms.Contains("Definition.Modify"), $"ReadOnly's /me: Definition.Read held, Definition.Modify not ({perms.Count} codes)");
        var (vcs, vcb) = await Get(readOnly, "api/v1/config/vDefinitionVersion?take=500");
        var before = (vcb?["rows"] as JsonArray)?.Count ?? -1;
        var good = JsonNode.Parse(Example("drawing-revision.procedure.json"));
        var (g1s, g1b) = await Post(readOnly, "api/v1/definitions/documents?dryRun=true", new { document = good });
        Check(g1s == HttpStatusCode.OK && g1b?["ok"]?.GetValue<bool>() == true && g1b?["canonical"] is JsonObject, $"dry run of a good document as ReadOnly → 200 ok, canonical returned, nothing stored ({(int)g1s} {Code(g1b)})");
        var bad = (JsonObject)JsonNode.Parse(Example("drawing-revision.procedure.json"))!;
        ((JsonObject)((JsonArray)bad["body"]!["items"]!)[0]!)["precondition"] = "device.nonsense > 1";
        var (b1s, b1b) = await Post(readOnly, "api/v1/definitions/documents?dryRun=true", new { document = bad });
        var errs = b1b?["errors"] as JsonArray;
        Check(b1s == HttpStatusCode.BadRequest && Code(b1b) == "document_invalid" && errs?.Any(e => e?["path"]?.ToString() == "$.body.items[0].precondition" && e?["code"]?.ToString() == "unknown_fact") == true,
            $"dry run of a bad expression → 400 document_invalid with the JSON path ({errs?.FirstOrDefault()?["path"]} {errs?.FirstOrDefault()?["code"]})");
        var dup = (JsonObject)JsonNode.Parse(Example("drawing-revision.procedure.json"))!;
        ((JsonObject)((JsonArray)dup["body"]!["items"]!)[1]!)["id"] = "IDENTIFY_DRAWINGS";
        var (b2s, b2b) = await Post(readOnly, "api/v1/definitions/documents?dryRun=true", new { document = dup });
        var errs2 = b2b?["errors"] as JsonArray;
        Check(b2s == HttpStatusCode.BadRequest && errs2?.Any(e => e?["code"]?.ToString() == "rule 50121") == true, $"dry run of duplicate block ids → the database's rule 50121 in its words ({errs2?.FirstOrDefault()?["message"]})");
        var (s1s, s1b) = await Post(readOnly, "api/v1/definitions/documents", new { document = good });
        Check(s1s == HttpStatusCode.Forbidden, $"storing as ReadOnly → 403 ({Code(s1b)})");
        var (vcs2, vcb2) = await Get(readOnly, "api/v1/config/vDefinitionVersion?take=500");
        Check(((vcb2?["rows"] as JsonArray)?.Count ?? -2) == before, $"the version count is unchanged by the dry runs and the refusal ({before})");
        if (drawingV2Row is not null)
        {
            var (rbs, rbb) = await Get(readOnly, $"api/v1/definitions/documents/{drawingV2Row}");
            var pre = rbb?["document"]?["body"]?["items"]?[1]?["cases"]?[0]?["when"];
            Check(rbs == HttpStatusCode.OK && pre is JsonValue && pre.ToString().Contains("step.outcome[id='IDENTIFY_DRAWINGS']"), $"read-back of DRAWING_REVISION prints the choice's when as grammar text ({pre})");
        }
    }
    else Skip("W5 dry run (needs the ReadOnly identity)");
}

// ======================================================================= W7 — the migrated estate (PHASE-1-WORKFLOW W7 gate)
// The importer (docs/schema/migration/legacy_import.py) has run against this database when these hold; they read what it
// wrote through the parity views. Numbers are the legacy database's (LEGACY-SYSTEM §3, §5): 5 641 A, 357 M, 5 850 P rows, 17 chains.
{
    var who = admin ?? readOnly ?? approver ?? hydro ?? tech;
    if (who is not null)
    {
        var (m1s, m1b) = await Get(who, "api/v1/migration/vRun?SourceSystem=dbRelayManagement_Legacy&take=50");
        var runs = (m1b?["rows"] as JsonArray) ?? new JsonArray();
        if (m1s == HttpStatusCode.OK && runs.Count > 0)
        {
            Check(true, $"migration runs of dbRelayManagement_Legacy on this database: {runs.Count}");
            async Task<int> CountAll(string path) { var n = 0; var skip = 0; for (;;) { var (_, b) = await Get(who, $"{path}&take=500&skip={skip}"); var c = (b?["rows"] as JsonArray)?.Count ?? 0; n += c; if (c < 500) break; skip += 500; } return n; }
            var active = await CountAll("api/v1/document/vSettingsRecord?GridState=Active");
            var archived = await CountAll("api/v1/document/vSettingsRecord?GridState=Archived");
            var outstanding = await CountAll("api/v1/document/vSettingsRecord?GridState=Outstanding");
            // the legacy rows that become configuration-file revisions: A 5 641, P 5 850, M 357, less the 277 control-switch rows (no file, R-06)
            // and the 9 rows of the 3 bases with no LOCATION (RECONCILIATION-2026-09-12.md); the fixtures add a few of each
            Check(active >= 5500 && active < 5700, $"the grid's Active rows: {active} (the legacy A rows that carry a settings file, plus the fixtures')");
            Check(archived >= 5650 && archived < 5900, $"the grid's Archived rows: {archived} (the legacy P rows that carry a settings file, plus the fixtures')");
            Check(outstanding >= 340 && outstanding < 500, $"the grid's Outstanding rows: {outstanding} (the legacy M rows that carry a settings file, plus the fixtures')");
            var (fnd, fndb) = await Get(who, "api/v1/record/vFinding?FindingCategoryCode=MigrationReconciliation&take=100");
            Check(fnd == HttpStatusCode.OK && (fndb?["rows"] as JsonArray)?.Count >= 19, $"the 17 ordering violations and the 2 duplicate station numbers are findings (#59, card C), plus any the cutover rehearsal planted ({(fndb?["rows"] as JsonArray)?.Count})");
            var sw = System.Diagnostics.Stopwatch.StartNew();
            var (g1, g1b) = await Get(who, "api/v1/document/vSettingsRecord?GridState=Active&take=500");
            sw.Stop();
            Check(g1 == HttpStatusCode.OK && (g1b?["rows"] as JsonArray)?.Count == 500 && sw.ElapsedMilliseconds < 5000, $"the grid's first page of 500 Active rows over the migrated estate (the state filter in memory over the whole view, #154; W8 round-2 item) in {sw.ElapsedMilliseconds} ms (NFR-2)");
            var (st1, st1b) = await Get(who, "api/v1/location/vNode?NodeTypeCode=Station&take=500");
            Check((st1b?["rows"] as JsonArray)?.Count >= 227, $"stations: {(st1b?["rows"] as JsonArray)?.Count} (227 legacy locations plus the fixtures')");
            var sw2 = System.Diagnostics.Stopwatch.StartNew();
            var (fl1, fl1b) = await Get(who, "api/v1/location/vFloc?take=500");
            sw2.Stop();
            Check(fl1 == HttpStatusCode.OK && (fl1b?["rows"] as JsonArray)?.Count == 500 && sw2.ElapsedMilliseconds < 5000, $"the FLOC view's first page of 500 positions (the whole view materialised, #145; W8 round-2 item) in {sw2.ElapsedMilliseconds} ms");
        }
        else Skip("W7 migrated estate (no migration run of dbRelayManagement_Legacy on this database)");
    }
}

Console.WriteLine($"SMOKE {(failed == 0 ? "PASS" : "FAIL")}: {passed} passed, {failed} failed, {skipped} skipped");
return failed == 0 ? 0 : 1;
