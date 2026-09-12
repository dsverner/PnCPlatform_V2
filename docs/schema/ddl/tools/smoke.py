"""
Smoke test after deploy (CONVENTIONS.md, plan "Verification"). Read-mostly; the writes it makes
are tagged with a throwaway definition key and soft-deleted at the end.

Checks:
  - every non-registry table carries PnC.TemporalClass; every non-AppendOnly table is
    system-versioned; every AppendOnly table is not
  - every generated view/proc exists for every table of each class
  - one table per class exercised through its generated procedures, with view assertions
  - the definition procedures (AddDefinition → version → characteristic → approve; segregation)
  - the applies-to resolver: default, specific match, overlay, tie → error
"""
import argparse, os, shutil, subprocess, sys, uuid, datetime, json, random, time
import pyodbc

DOTNET = shutil.which("dotnet") or r"C:\Program Files\dotnet\dotnet.exe"

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "grammar"))   # FORMULA-GRAMMAR.md §12: the conformance suite
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
SYSTEM_ACTOR = "00000000-0000-0000-0000-000000000001"
fails = []


def check(cond, msg):
    print(("PASS " if cond else "FAIL ") + msg)
    if not cond:
        fails.append(msg)


def password():
    if os.environ.get("PNC_DEV_PWD"):
        return os.environ["PNC_DEV_PWD"]
    p = os.path.join(ROOT, "dev.local")
    for line in open(p, encoding="utf-8"):
        if line.startswith("PNC_DEV_PWD="):
            return line.split("=", 1)[1].strip()
    sys.exit("no password")


def expect_error(cur, sql, *params, contains=""):
    try:
        cur.execute(sql, *params)
        return False
    except pyodbc.Error as e:
        return contains in str(e)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default="10.10.70.25")
    ap.add_argument("--database", default="PnCPlatform_DEV")
    a = ap.parse_args()
    con = pyodbc.connect(f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={a.server};DATABASE={a.database};UID=dev_pnc;PWD={password()};TrustServerCertificate=yes", autocommit=True, timeout=15)
    # pyodbc cannot read DATETIMEOFFSET (SQL type -155): decode it (the temporal views return it)
    import struct
    def _dto(raw):
        y, mo, d, h, mi, sec, ns, oh, om = struct.unpack("<6hI2h", raw)
        return datetime.datetime(y, mo, d, h, mi, sec, ns // 1000, datetime.timezone(datetime.timedelta(hours=oh, minutes=om)))
    con.add_output_converter(-155, _dto)
    cur = con.cursor()
    q = lambda s, *p: cur.execute(s, *p).fetchall()
    import formula as FG          # FORMULA-GRAMMAR.md: the canonical form the engine is given

    # The compliance engine left the database on 2026-09-10 (.planning/CALCULATION-ENGINE-DESIGN.md §6),
    # so the checks below drive it through src/PnC.Engine.Cli instead of EXEC-ing a procedure. Every
    # fixture and every assertion is unchanged; only the call is. Grammar conformance is no longer
    # checked here at all — there is one implementation now, and src/PnC.Formula.Conformance is its suite.
    ENGINE_CS = f"Server={a.server};Database={a.database};User ID=dev_pnc;Password={password()};TrustServerCertificate=true;Encrypt=true"
    # V2 W0: the repository has no engine until W4 (decision #64 rewrites the application), so the gate
    # names the predecessor's built PnC.Engine.Cli through PNC_ENGINE_DIR until then (decision #79).
    ENGINE_DIR = os.environ.get("PNC_ENGINE_DIR") or os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "src", "PnC.Engine.Cli"))

    def engine(verb, argument, *rest):
        """One engine call. Returns the parsed JSON; raises with the engine's own words on refusal."""
        r = subprocess.run([DOTNET, "run", "--project", ENGINE_DIR, "-c", "Release", "--no-build", "--",
                            ENGINE_CS, verb, str(argument), *rest],
                           capture_output=True, text=True, env=dict(os.environ, DOTNET_ROLL_FORWARD="Major"))
        out = (r.stdout or "").strip().splitlines()
        doc = json.loads(out[-1]) if out else None
        if r.returncode != 0:
            why = (doc or {}).get("detail") or r.stderr.strip() or f"engine exit {r.returncode}"
            raise RuntimeError("engine " + verb + " " + str(argument)[:120] + " " + " ".join(str(x)[:60] for x in rest) + " -> " + why)
        return doc

    def evaluate(text, subj, env=None):
        """One expression, as compliance.fEvalNode answered it — the grammar's typed value JSON."""
        return engine("eval", FG.canonical(FG.parse(text), root=False), str(subj) if subj else "-", env or "-")
    ev = evaluate          # a later wave rebinds `ev` to a query result; `evaluate` is never rebound

    # The procedures' result-set shape, so r[3], r[5], r[6], r[10] still mean what they meant.
    EFFECTIVE = ["RunId", "RuleDefinitionVersionRowId", "SubjectKind", "SubjectEntityId", "SubjectName",
                 "Outcome", "Status", "PeriodStartAt", "PeriodEndAt", "DueAt", "ObligationInstanceEntityId", "Reason"]
    PREVIEW = ["RunId", "RuleDefinitionVersionRowId", "SubjectKind", "SubjectEntityId", "SubjectName",
               "Status", "Reason"]
    def engine_rows(verb, key):
        cols = PREVIEW if verb == "preview" else EFFECTIVE
        return [tuple(r.get(c) for c in cols) for r in engine(verb, key)]

    # ---- catalog invariants
    missing = q("""SELECT s.name + '.' + t.name FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
                   WHERE t.temporal_type <> 1 AND NOT EXISTS (SELECT 1 FROM sys.extended_properties ep WHERE ep.major_id = t.object_id AND ep.minor_id = 0 AND ep.name = 'PnC.TemporalClass')""")
    check(not missing, f"every table carries PnC.TemporalClass ({len(missing)} missing: {[m[0] for m in missing][:5]})")
    bad = q("""SELECT s.name + '.' + t.name, CONVERT(NVARCHAR(40), ep.value), t.temporal_type
               FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
               JOIN sys.extended_properties ep ON ep.major_id = t.object_id AND ep.minor_id = 0 AND ep.name = 'PnC.TemporalClass'
               WHERE (CONVERT(NVARCHAR(40), ep.value) IN ('ValidTime','BiTemporal','Versioned','Reference','Subclass') AND t.temporal_type <> 2)
                  OR (CONVERT(NVARCHAR(40), ep.value) IN ('AppendOnly','Registry','FileTable') AND t.temporal_type <> 0)""")
    check(not bad, f"system versioning matches temporal class ({[b[0] for b in bad][:5]})")
    classes = q("""SELECT s.name, t.name, CONVERT(NVARCHAR(40), ep.value) FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
                   JOIN sys.extended_properties ep ON ep.major_id = t.object_id AND ep.minor_id = 0 AND ep.name = 'PnC.TemporalClass' WHERE t.temporal_type <> 1""")
    objs = {r[0] for r in q("SELECT s.name + '.' + o.name FROM sys.objects o JOIN sys.schemas s ON s.schema_id = o.schema_id WHERE o.type IN ('V','P','IF','FN')")}
    expected = []
    for s, t, c in classes:
        if c == "Registry":
            continue
        expected.append(f"{s}.v{t}")
        if c != "AppendOnly":
            expected.append(f"{s}.v{t}History")
        if c == "BiTemporal":
            expected += [f"{s}.f{t}AsOf", f"{s}.{t}_Add", f"{s}.{t}_Revise", f"{s}.{t}_SoftDelete"]
        elif c == "ValidTime":
            expected += [f"{s}.{t}_Add", f"{s}.{t}_Revise", f"{s}.{t}_SoftDelete"]
        elif c == "Versioned":
            expected += [f"{s}.{t}_Add", f"{s}.{t}_Update", f"{s}.{t}_SoftDelete"]
        elif c == "Subclass":
            expected += [f"{s}.{t}_Add", f"{s}.{t}_Update", f"{s}.{t}_SoftDelete"]
        elif c == "FileTable":
            expected = [e for e in expected if e != f"{s}.v{t}History"]
        elif c == "Reference":
            expected += [f"{s}.{t}_Upsert", f"{s}.{t}_Deactivate"]
        elif c == "AppendOnly":
            expected += [f"{s}.{t}_Append"]
    miss = [e for e in expected if e not in objs]
    check(not miss, f"generated objects present for {len(classes)} tables ({len(miss)} missing: {miss[:6]})")
    print(f"     classes: { {c: sum(1 for x in classes if x[2] == c) for c in sorted({x[2] for x in classes})} }")

    # ---- pre-clean leftovers from an aborted earlier run (soft delete only)
    cur.execute("""UPDATE config.DefinitionVersion SET IsDeleted = 1, DeletedBy = ?, DeletedAt = SYSDATETIMEOFFSET()
                   WHERE IsDeleted = 0 AND DefinitionEntityId IN (SELECT EntityId FROM config.Definition WHERE DefinitionKey LIKE N'smoke[_]%')""", SYSTEM_ACTOR)
    cur.execute("""UPDATE config.Definition SET IsDeleted = 1, DeletedBy = ?, DeletedAt = SYSDATETIMEOFFSET()
                   WHERE IsDeleted = 0 AND DefinitionKey LIKE N'smoke[_]%'""", SYSTEM_ACTOR)

    # ---- actor resolution
    a1 = q("DECLARE @a UNIQUEIDENTIFIER; EXEC personnel.ResolveActor @ActorId = @a OUTPUT; SELECT @a")[0][0]
    a2 = q("DECLARE @a UNIQUEIDENTIFIER; EXEC personnel.ResolveActor @ActorId = @a OUTPUT; SELECT @a")[0][0]
    check(a1 == a2 and a1 is not None, "ResolveActor returns one immutable actor per session identity")

    # ---- definitions: Versioned class through the definition procedures
    key = "smoke_" + uuid.uuid4().hex[:8]
    ent = q("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'CharacteristicSchema.AssetTemplate', ?, N'smoke template', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", key, SYSTEM_ACTOR)[0][0]
    ver = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @ChangeNote=N'v1', @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r, @n", key, SYSTEM_ACTOR)[0]
    check(ver[1] == 1, "first version numbered 1")
    check(expect_error(cur, "DECLARE @r UNIQUEIDENTIFIER; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=N'{}', @ActorId=?, @VersionRowId=@r OUTPUT", key, SYSTEM_ACTOR, contains="Only program"),
          "schema definition refuses PayloadText (decision 78)")
    cd = q("DECLARE @r UNIQUEIDENTIFIER; EXEC config.AddCharacteristic @DefinitionVersionRowId=?, @CharacteristicKey=N'k1', @Name=N'k1', @DataType=N'Decimal', @UnitCode=N'kV', @Base=N'Primary', @IsCatalogueFact=1, @ActorId=?, @RowId=@r OUTPUT; SELECT @r", ver[0], SYSTEM_ACTOR)[0][0]
    check(cd is not None, "characteristic added to Draft version")
    check(expect_error(cur, "EXEC config.ApproveDefinitionVersion @VersionRowId=?, @ActorId=?", ver[0], SYSTEM_ACTOR, contains="segregation"),
          "approval by the author is refused (segregation)")
    cur.execute("EXEC config.ApproveDefinitionVersion @VersionRowId=?, @ActorId=?", ver[0], a1)
    st = q("SELECT Status, ApprovedBy FROM config.vDefinitionVersion WHERE RowId = ?", ver[0])[0]
    check(st[0] == "Effective" and str(st[1]).lower() == str(a1).lower(), "approval by another actor makes the version Effective")
    check(q("SELECT COUNT(*) FROM audit.vActionLog WHERE ActionKindCode = 'Approval' AND SubjectRowId = ?", ver[0])[0][0] == 1, "approval logged in audit.ActionLog")
    time.sleep(0.05)   # v1's Effective period must be non-zero, or SQL Server drops that history row
    ver2 = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @ChangeNote=N'v2', @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r, @n", key, SYSTEM_ACTOR)[0]
    cur.execute("EXEC config.ApproveDefinitionVersion @VersionRowId=?, @ActorId=?", ver2[0], a1)
    sts = dict(q("SELECT VersionNumber, Status FROM config.vDefinitionVersion WHERE DefinitionEntityId = ?", ent))
    check(sts == {1: "Retired", 2: "Effective"}, f"approving v2 retires v1 ({sts})")
    hist = q("SELECT COUNT(*) FROM config.vDefinitionVersionHistory WHERE RowId = ?", ver[0])[0][0]
    check(hist >= 3, f"history view shows the version's row versions ({hist})")

    # ---- Versioned _Update and _SoftDelete
    drow = q("SELECT RowId FROM config.vDefinition WHERE EntityId=?", ent)[0][0]
    cur.execute("EXEC config.Definition_Update @RowId=?, @DefinitionKind=N'CharacteristicSchema.AssetTemplate', @DefinitionKey=?, @Name=N'smoke template renamed', @ActorId=?", drow, key, SYSTEM_ACTOR)
    check(q("SELECT Name FROM config.vDefinition WHERE EntityId = ?", ent)[0][0] == "smoke template renamed", "Versioned _Update changes the live row in place")

    # ---- ValidTime class through generated procs: config.DefinitionAppliesTo
    e = q("""DECLARE @e UNIQUEIDENTIFIER, @r UNIQUEIDENTIFIER;
             EXEC config.DefinitionAppliesTo_Add @DefinitionVersionRowId=?, @DimensionCode=N'VoltageClass', @ValueCode=N'138', @ActorId=?, @EntityId=@e OUTPUT, @RowId=@r OUTPUT;
             SELECT @e, @r""", ver2[0], SYSTEM_ACTOR)[0]
    check(q("SELECT COUNT(*) FROM config.vDefinitionAppliesTo WHERE EntityId = ?", e[0])[0][0] == 1, "ValidTime _Add: one current row")
    r2 = q("DECLARE @r UNIQUEIDENTIFIER; EXEC config.DefinitionAppliesTo_Revise @EntityId=?, @DefinitionVersionRowId=?, @DimensionCode=N'VoltageClass', @ValueCode=N'230', @ActorId=?, @RowId=@r OUTPUT; SELECT @r", e[0], ver2[0], SYSTEM_ACTOR)[0][0]
    cur_rows = q("SELECT RowId, ValueCode FROM config.vDefinitionAppliesTo WHERE EntityId = ?", e[0])
    check(len(cur_rows) == 1 and cur_rows[0][1] == "230", "ValidTime _Revise: prior row closed, new row current")
    check(q("SELECT COUNT(*) FROM config.DefinitionAppliesTo WHERE EntityId = ? AND ValidTo IS NOT NULL", e[0])[0][0] == 1, "ValidTime _Revise: prior row has ValidTo set")
    check(expect_error(cur, "EXEC config.DefinitionAppliesTo_Add @DefinitionVersionRowId=?, @DimensionCode=N'VoltageClass', @ValueCode=N'x', @ValueEntityId=?, @ActorId=?", ver2[0], str(uuid.uuid4()), SYSTEM_ACTOR, contains="CK_DefinitionAppliesTo_OneValue"),
          "CHECK: exactly one of ValueEntityId / ValueCode")
    cur.execute("EXEC config.DefinitionAppliesTo_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    check(q("SELECT COUNT(*) FROM config.vDefinitionAppliesTo WHERE EntityId = ?", e[0])[0][0] == 0, "ValidTime _SoftDelete: gone from current view")
    check(q("SELECT COUNT(*) FROM config.vDefinitionAppliesToHistory WHERE EntityId = ?", e[0])[0][0] >= 3, "ValidTime history retains every version")

    # ---- Versioned: config.StandardSettingEntry (§8.6; MIGRATION-PLAN Q9) — rows of a StandardSettings version
    sse = q("""DECLARE @e UNIQUEIDENTIFIER, @r UNIQUEIDENTIFIER;
               EXEC config.StandardSettingEntry_Add @DefinitionVersionRowId=?, @SettingCode=N'50P1P', @ExpectedValue=N'6.00', @Tolerance=N'±5 %', @Basis=N'smoke basis', @ActorId=?, @EntityId=@e OUTPUT, @RowId=@r OUTPUT;
               SELECT @e, @r""", ver2[0], SYSTEM_ACTOR)[0]
    check(tuple(q("SELECT ExpectedValue, Tolerance FROM config.vStandardSettingEntry WHERE EntityId = ?", sse[0])[0]) == ("6.00", "±5 %"), "StandardSettingEntry_Add: (SettingCode, ExpectedValue, Tolerance, Basis) row under the version")
    check(expect_error(cur, "EXEC config.StandardSettingEntry_Add @DefinitionVersionRowId=?, @SettingCode=N'50P1P', @ExpectedValue=N'7.00', @ActorId=?", ver2[0], SYSTEM_ACTOR, contains="UX_StandardSettingEntry_Code"),
          "StandardSettingEntry: one live row per SettingCode within a version")
    cur.execute("EXEC config.StandardSettingEntry_SoftDelete @EntityId=?, @ActorId=?", sse[0], SYSTEM_ACTOR)
    check(q("SELECT COUNT(*) FROM config.vStandardSettingEntry WHERE EntityId = ?", sse[0])[0][0] == 0, "StandardSettingEntry_SoftDelete: gone from the current view")

    # ---- resolver
    k2 = key + "_b"
    cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'CharacteristicSchema.AssetTemplate', ?, N'smoke specific', @ActorId=?, @EntityId=@e OUTPUT", k2, SYSTEM_ACTOR)
    vb = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", k2, SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC config.DefinitionAppliesTo_Add @DefinitionVersionRowId=?, @DimensionCode=N'VoltageClass', @ValueCode=N'138', @ActorId=?", vb, SYSTEM_ACTOR)
    cur.execute("EXEC config.ApproveDefinitionVersion @VersionRowId=?, @ActorId=?", vb, a1)
    k3 = key + "_o"
    cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'CharacteristicSchema.AssetTemplate', ?, N'smoke overlay', @ActorId=?, @EntityId=@e OUTPUT", k3, SYSTEM_ACTOR)
    vo = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", k3, SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC config.DefinitionAppliesTo_Add @DefinitionVersionRowId=?, @DimensionCode=N'AssetType', @ValueCode=N'Relay', @IsOverlay=1, @ActorId=?", vo, SYSTEM_ACTOR)
    cur.execute("EXEC config.ApproveDefinitionVersion @VersionRowId=?, @ActorId=?", vo, a1)

    def resolve(facts):
        sql = "SET NOCOUNT ON; DECLARE @f config.AppliesToFactList; " + " ".join(f"INSERT @f VALUES (N'{d}', NULL, N'{c}');" for d, c in facts) + \
              " EXEC config.ResolveDefinition N'CharacteristicSchema.AssetTemplate', @f"
        return [(r.IsOverlay, r.DefinitionKey) for r in cur.execute(sql).fetchall()]
    # other smoke definitions from earlier runs may exist as defaults; restrict comparison to ours
    mine = lambda rs: [(o, k_) for o, k_ in rs if k_.startswith(key)]
    r = mine(resolve([("VoltageClass", "138")]))
    check(r == [(0, k2)], f"resolver picks the most specific match ({r})")
    r = mine(resolve([("VoltageClass", "138"), ("AssetType", "Relay")]))
    check(r == [(0, k2), (1, k3)], f"resolver applies overlay after the base ({r})")
    # a tie: second definition with the same single dimension
    k4 = key + "_t"
    cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'CharacteristicSchema.AssetTemplate', ?, N'smoke tie', @ActorId=?, @EntityId=@e OUTPUT", k4, SYSTEM_ACTOR)
    vt = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", k4, SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC config.DefinitionAppliesTo_Add @DefinitionVersionRowId=?, @DimensionCode=N'VoltageClass', @ValueCode=N'138', @ActorId=?", vt, SYSTEM_ACTOR)
    cur.execute("EXEC config.ApproveDefinitionVersion @VersionRowId=?, @ActorId=?", vt, a1)
    check(expect_error(cur, "SET NOCOUNT ON; DECLARE @f config.AppliesToFactList; INSERT @f VALUES (N'VoltageClass', NULL, N'138'); EXEC config.ResolveDefinition N'CharacteristicSchema.AssetTemplate', @f", contains="tie"),
          "resolver raises on a tie")

    # ---- Reference class: _Upsert / _Deactivate
    cur.execute("EXEC ref.Unit_Upsert @UnitCode=N'smokeU', @Name=N'smoke unit', @Dimension=N'Other', @ActorId=?", SYSTEM_ACTOR)
    check(q("SELECT COUNT(*) FROM ref.vUnit WHERE UnitCode = N'smokeU'")[0][0] == 1, "Reference _Upsert inserts")
    cur.execute("EXEC ref.Unit_Upsert @UnitCode=N'smokeU', @Name=N'smoke unit 2', @Dimension=N'Other', @ActorId=?", SYSTEM_ACTOR)
    check(q("SELECT Name FROM ref.vUnit WHERE UnitCode = N'smokeU'")[0][0] == "smoke unit 2", "Reference _Upsert updates")
    cur.execute("EXEC ref.Unit_Deactivate @UnitCode=N'smokeU', @ActorId=?", SYSTEM_ACTOR)
    check(q("SELECT COUNT(*) FROM ref.vUnit WHERE UnitCode = N'smokeU'")[0][0] == 0, "Reference _Deactivate hides from current view")

    # ---- AppendOnly: audit.LogAction
    n = q("DECLARE @i BIGINT; EXEC audit.LogAction @ActionKindCode=N'Administrative', @SubjectSchema=N'config', @SubjectTable=N'Definition', @SubjectEntityId=?, @Detail=N'{\"smoke\":true}', @ActorId=?, @ActionLogId=@i OUTPUT; SELECT @i", ent, SYSTEM_ACTOR)[0][0]
    check(n is not None and n > 0, "AppendOnly: LogAction appends and returns the id")
    check(expect_error(cur, "DECLARE @i BIGINT; EXEC audit.LogAction @ActionKindCode=N'Administrative', @Detail=N'not json', @ActorId=?, @ActionLogId=@i OUTPUT", SYSTEM_ACTOR, contains="CK_ActionLog_DetailJson"), "ActionLog.Detail must be JSON")

    # ---- BiTemporal as-of (first bi-temporal table arrives in wave 2; skipped when none)
    bt = [f"{s}.{t}" for s, t, c in classes if c == "BiTemporal"]
    if bt:
        print(f"     bi-temporal tables present: {len(bt)} (as-of exercised by wave-specific smoke)")

    # ================================================================ wave 2: steps 3–5
    W = "smoke_w2_" + uuid.uuid4().hex[:6]
    cur.execute("EXEC ref.AssetType_Upsert @AssetTypeCode=?, @Name=N'smoke relay type', @AssetClassCode=N'Secondary', @IsDevice=1, @ActorId=?", W, SYSTEM_ACTOR)
    org = q("DECLARE @e UNIQUEIDENTIFIER; EXEC party.Entity_Add @Name=?, @EntityKind=N'Utility', @IsOwnerOrganisation=1, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W + " utility", SYSTEM_ACTOR)[0][0]
    region = q("DECLARE @e UNIQUEIDENTIFIER; EXEC location.Node_Add @NodeTypeCode=N'Region', @ParentEntityId=NULL, @Path=N'/', @Depth=0, @Name=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W + " region", SYSTEM_ACTOR)[0][0]
    station = q("DECLARE @e UNIQUEIDENTIFIER; EXEC location.Node_Add @NodeTypeCode=N'Station', @ParentEntityId=?, @Path=?, @Depth=1, @Name=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", region, f"/{region}/", W + " station", SYSTEM_ACTOR)[0][0]
    check(expect_error(cur, "DECLARE @e UNIQUEIDENTIFIER; EXEC location.Node_Add @NodeTypeCode=N'Region', @ParentEntityId=?, @Path=N'/', @Depth=1, @Name=N'x', @ActorId=?, @EntityId=@e OUTPUT", region, SYSTEM_ACTOR, contains="CK_Node_RootHasNoParent"),
          "CHECK: a Region has no parent")
    asset_id = q("DECLARE @e UNIQUEIDENTIFIER; EXEC asset.Asset_Add @AssetTypeCode=?, @Name=?, @Status=N'Planned', @ManufacturerEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W, W + " relay", org, SYSTEM_ACTOR)[0][0]
    # extension _Add shares the asset's identity
    cur.execute("EXEC device.Device_Add @EntityId=?, @PartNumber=N'P-1', @ActorId=?", asset_id, SYSTEM_ACTOR)
    check(q("SELECT COUNT(*) FROM device.vDevice WHERE EntityId = ?", asset_id)[0][0] == 1, "extension _Add (device.Device) shares the asset EntityId")
    check(expect_error(cur, "EXEC device.Device_Add @EntityId=?, @ActorId=?", str(uuid.uuid4()), SYSTEM_ACTOR, contains="not a registered"),
          "extension _Add refuses an unregistered parent identity")
    # alternate key through the union view
    cur.execute("EXEC asset.AlternateKey_Add @SubjectEntityId=?, @KeyKindCode=N'SerialNumber', @KeyValue=?, @ScopeEntityId=?, @IsPrimaryLabel=1, @ActorId=?", asset_id, W + "-SN", org, SYSTEM_ACTOR)
    ak = [tuple(r) for r in q("SELECT SchemaName, KeyKindCode FROM core.vAlternateKey WHERE SubjectEntityId = ?", asset_id)]
    check(ak == [("asset", "SerialNumber")], f"alternate key visible through core.vAlternateKey ({ak})")
    check(expect_error(cur, "EXEC asset.AlternateKey_Add @SubjectEntityId=?, @KeyKindCode=N'SerialNumber', @KeyValue=?, @ScopeEntityId=?, @ActorId=?", asset_id, W + "-SN", org, SYSTEM_ACTOR, contains="UX_AlternateKey_Value"),
          "duplicate current alternate key refused (unique filtered index)")
    # polymorphic kind checks
    check(expect_error(cur, "EXEC asset.OwnershipLink_Add @SubjectKind=N'Bogus', @SubjectEntityId=?, @EntityEntityId=?, @OwnershipRole=N'Owner', @ActorId=?", asset_id, org, SYSTEM_ACTOR, contains="Subject"),
          "polymorphic kind outside the design's list is refused (fEntityExists / CHECK)")
    check(expect_error(cur, "EXEC asset.OwnershipLink_Add @SubjectKind=N'Asset', @SubjectEntityId=?, @EntityEntityId=?, @OwnershipRole=N'Owner', @ActorId=?", str(uuid.uuid4()), org, SYSTEM_ACTOR, contains="no Subject entity"),
          "meta.fEntityExists refuses an unknown subject id for a known kind")
    cur.execute("EXEC asset.OwnershipLink_Add @SubjectKind=N'Asset', @SubjectEntityId=?, @EntityEntityId=?, @OwnershipRole=N'Owner', @IsResponsibleForReporting=1, @ActorId=?", asset_id, org, SYSTEM_ACTOR)
    r = ev("asset.owner_of_record[role='Owner']", asset_id)
    check(r.get("k") == "ref" and str(r.get("id")).lower() == str(org).lower() and r.get("kind") == "Entity", f"fact asset.owner_of_record[role] is the owning entity (#35: {r})")
    check(ev("asset.owner_of_record[role='Maintainer']", asset_id).get("k") == "unk", "fact asset.owner_of_record with no link of that role is Unknown")
    check(q("SELECT COUNT(*) FROM asset.vOwnershipLink WHERE SubjectEntityId = ?", asset_id)[0][0] == 1, "ownership link written for an existing asset")
    # bi-temporal placement: Add -> (believed t1) -> Revise -> as-of on both clocks
    pl = q("DECLARE @e UNIQUEIDENTIFIER; EXEC asset.Placement_Add @AssetEntityId=?, @NodeEntityId=?, @PlacementKind=N'Installed', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", asset_id, station, SYSTEM_ACTOR)[0][0]
    time.sleep(0.3)
    t1 = q("SELECT SYSUTCDATETIME()")[0][0]
    time.sleep(0.3)
    cur.execute("EXEC asset.Placement_Revise @EntityId=?, @AssetEntityId=?, @NodeEntityId=?, @PlacementKind=N'Installed', @ActorId=?", pl, asset_id, region, SYSTEM_ACTOR)
    now_v = q("SELECT CONVERT(NVARCHAR(40), SYSDATETIMEOFFSET(), 127)")[0][0]
    believed_then = q("SELECT NodeEntityId FROM asset.fPlacementAsOf(?, ?) WHERE EntityId = ?", now_v, t1, pl)
    believed_now = q("SELECT NodeEntityId FROM asset.fPlacementAsOf(?, SYSUTCDATETIME()) WHERE EntityId = ?", now_v, pl)
    check(len(believed_then) == 1 and str(believed_then[0][0]).lower() == str(station).lower(), "bi-temporal as-of: earlier belief returns the station")
    check(len(believed_now) == 1 and str(believed_now[0][0]).lower() == str(region).lower(), "bi-temporal as-of: current belief returns the revised node")
    check(q("SELECT COUNT(*) FROM asset.vPlacement WHERE EntityId = ?", pl)[0][0] == 1, "one current placement after revise")
    check(expect_error(cur, "EXEC asset.Placement_Add @AssetEntityId=?, @NodeEntityId=?, @CustodyLocationEntityId=?, @PlacementKind=N'Stored', @ActorId=?", asset_id, station, str(uuid.uuid4()), SYSTEM_ACTOR, contains="CK_Placement_OneLocation"),
          "CHECK: placement is a node or a custody location, never both")
    # AppendOnly with TimeSourceQuality
    lid = q("DECLARE @i BIGINT, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC device.LifecycleEvent_Append @DeviceEntityId=?, @EventKind=N'Received', @OccurredAt=@t, @TimeSourceQuality=3, @ActorId=?, @NodeEntityId=?, @LifecycleEventId=@i OUTPUT; SELECT @i", asset_id, SYSTEM_ACTOR, station)[0][0]
    check(lid is not None and lid > 0, "AppendOnly lifecycle event appended with TimeSourceQuality")
    check(expect_error(cur, "DECLARE @i BIGINT, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC device.LifecycleEvent_Append @DeviceEntityId=?, @EventKind=N'Received', @OccurredAt=@t, @TimeSourceQuality=9, @ActorId=?, @NodeEntityId=?, @LifecycleEventId=@i OUTPUT", asset_id, SYSTEM_ACTOR, station, contains="CK_LifecycleEvent_TimeSourceQuality"),
          "CHECK: TimeSourceQuality outside 0-4 refused")
    # geography round-trips through the generated procedure
    cur.execute("DECLARE @g geography = geography::Point(45.96, -66.64, 4326); EXEC location.Node_Revise @EntityId=?, @NodeTypeCode=N'Station', @ParentEntityId=?, @Path=?, @Depth=1, @Name=?, @Location=@g, @ActorId=?", station, region, f"/{region}/", W + " station", SYSTEM_ACTOR)
    check(q("SELECT Location.STSrid FROM location.vNode WHERE EntityId = ?", station)[0][0] == 4326, "geography column stored through the generated procedure")
    check(q("SELECT COUNT(*) FROM ref.vLocationNodeType WHERE NodeTypeCode IN (N'Station', N'Raceway', N'DevicePosition') AND SubtypeListDefinitionRowId IS NOT NULL")[0][0] == 3,
          "seeded enumeration definitions attached to Station, Raceway, DevicePosition")
    # cleanup (soft only)
    for e in q("SELECT EntityId FROM asset.vOwnershipLink WHERE SubjectEntityId = ?", asset_id):
        cur.execute("EXEC asset.OwnershipLink_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    for e in q("SELECT EntityId FROM asset.vAlternateKey WHERE SubjectEntityId = ?", asset_id):
        cur.execute("EXEC asset.AlternateKey_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    for proc, ent in [("asset.Placement_SoftDelete", pl), ("device.Device_SoftDelete", asset_id), ("asset.Asset_SoftDelete", asset_id),
                      ("location.Node_SoftDelete", station), ("location.Node_SoftDelete", region), ("party.Entity_SoftDelete", org)]:
        cur.execute(f"EXEC {proc} @EntityId=?, @ActorId=?", ent, SYSTEM_ACTOR)
    cur.execute("EXEC ref.AssetType_Deactivate @AssetTypeCode=?, @ActorId=?", W, SYSTEM_ACTOR)

    # ================================================================ wave 2 domain rules: PROCEDURES.md #4–#8, #34
    W2 = "smoke_w2r_" + uuid.uuid4().hex[:6]
    lo = lambda g: str(g).lower()
    org2 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC party.Entity_Add @Name=?, @EntityKind=N'Utility', @IsOwnerOrganisation=1, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W2 + " utility", SYSTEM_ACTOR)[0][0]
    def add_node(t, parent, name, sub=None):
        return q("DECLARE @e UNIQUEIDENTIFIER; EXEC location.AddNode @NodeTypeCode=?, @ParentEntityId=?, @Name=?, @SubtypeCode=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", t, parent, name, sub, SYSTEM_ACTOR)[0][0]
    reg2 = add_node("Region", None, W2 + " region")
    st2 = add_node("Station", reg2, W2 + " station")
    pd = q("SELECT Path, Depth FROM location.vNode WHERE EntityId = ?", st2)[0]
    check((pd[0].lower(), pd[1]) == (f"/{lo(reg2)}/", 1), f"AddNode computes Path/Depth from the parent ({pd[0]}, {pd[1]})")
    check(expect_error(cur, "DECLARE @e UNIQUEIDENTIFIER; EXEC location.AddNode @NodeTypeCode=N'Panel', @ParentEntityId=?, @Name=N'x', @ActorId=?, @EntityId=@e OUTPUT", reg2, SYSTEM_ACTOR, contains="not allowed under"),
          "AddNode refuses a node type not allowed under the parent's type (#4)")
    b1 = add_node("Building", st2, W2 + " b1"); b2 = add_node("Building", st2, W2 + " b2")
    pan = add_node("Panel", b1, W2 + " panel")
    check(expect_error(cur, "DECLARE @e UNIQUEIDENTIFIER; EXEC location.AddNode @NodeTypeCode=N'DevicePosition', @ParentEntityId=?, @Name=N'x', @SubtypeCode=N'Bogus', @ActorId=?, @EntityId=@e OUTPUT", pan, SYSTEM_ACTOR, contains="not in the enumeration"),
          "AddNode refuses a subtype outside the type's enumeration list")
    dp = add_node("DevicePosition", pan, W2 + " dp", "Relay")
    cur.execute("EXEC location.MoveNode @EntityId=?, @NewParentEntityId=?, @ActorId=?", pan, b2, SYSTEM_ACTOR)
    paths = {lo(r[0]): (r[1].lower(), r[2]) for r in q("SELECT EntityId, Path, Depth FROM location.vNode WHERE EntityId IN (?, ?)", pan, dp)}
    check(paths[lo(pan)] == (f"/{lo(reg2)}/{lo(st2)}/{lo(b2)}/", 3) and paths[lo(dp)] == (f"/{lo(reg2)}/{lo(st2)}/{lo(b2)}/{lo(pan)}/", 4),
          f"MoveNode rewrites Path/Depth of the node and its descendants ({paths[lo(dp)]})")
    check(expect_error(cur, "EXEC location.MoveNode @EntityId=?, @NewParentEntityId=?, @ActorId=?", b1, pan, SYSTEM_ACTOR, contains="not allowed under"), "MoveNode refuses a parent type the node is not allowed under")
    # linear node, touch points, segments re-linked
    rw = add_node("Raceway", st2, W2 + " raceway", "Trench")
    seg1 = add_node("Segment", rw, W2 + " seg1"); seg2 = add_node("Segment", rw, W2 + " seg2")
    cur.execute("UPDATE location.Node SET SiblingOrder = 1 WHERE EntityId = ? AND ValidTo IS NULL", seg1)
    cur.execute("UPDATE location.Node SET SiblingOrder = 2 WHERE EntityId = ? AND ValidTo IS NULL", seg2)
    for sg in (seg1, seg2):
        cur.execute("EXEC location.Segment_Add @EntityId=?, @ActorId=?", sg, SYSTEM_ACTOR)
    check(expect_error(cur, "DECLARE @e UNIQUEIDENTIFIER; EXEC location.AddAdjacency @LinearNodeEntityId=?, @TouchedNodeEntityId=?, @Sequence=1, @ActorId=?, @EntityId=@e OUTPUT", st2, b1, SYSTEM_ACTOR, contains="Linear"),
          "AddAdjacency refuses a non-linear node")
    adj = []
    for i, touched in enumerate((b1, b2, pan), start=1):
        adj.append(q("DECLARE @e UNIQUEIDENTIFIER, @r UNIQUEIDENTIFIER; EXEC location.AddAdjacency @LinearNodeEntityId=?, @TouchedNodeEntityId=?, @Sequence=?, @ActorId=?, @EntityId=@e OUTPUT, @RowId=@r OUTPUT; SELECT @r", rw, touched, i, SYSTEM_ACTOR)[0][0])
    segs = {lo(r[0]): (lo(r[1]), lo(r[2])) for r in q("SELECT EntityId, FromAdjacencyRowId, ToAdjacencyRowId FROM location.vSegment WHERE EntityId IN (?, ?)", seg1, seg2)}
    check(segs.get(lo(seg1)) == (lo(adj[0]), lo(adj[1])) and segs.get(lo(seg2)) == (lo(adj[1]), lo(adj[2])), f"AddAdjacency re-links segments between consecutive touch points ({segs})")
    # placement rules (#5, #6)
    cur.execute("EXEC ref.AssetType_Upsert @AssetTypeCode=?, @Name=N'smoke relay type', @AssetClassCode=N'Secondary', @IsDevice=1, @ActorId=?", W2, SYSTEM_ACTOR)
    cur.execute("EXEC ref.AssetType_Upsert @AssetTypeCode=?, @Name=N'smoke routed type', @AssetClassCode=N'Primary', @IsRouted=1, @ActorId=?", W2 + "_r", SYSTEM_ACTOR)
    man, mod = str(uuid.uuid4()), str(uuid.uuid4())
    cur.execute("EXEC ref.Manufacturer_Upsert @ManufacturerId=?, @EntityEntityId=?, @ShortCode=?, @ActorId=?", man, org2, W2[-8:], SYSTEM_ACTOR)
    cur.execute("EXEC ref.Model_Upsert @ModelId=?, @ManufacturerId=?, @ModelCode=?, @ModelName=N'smoke meter model', @AssetTypeCode=?, @DeviceCategory=N'Meter', @Technology=N'Microprocessor', @ActorId=?", mod, man, W2 + "-M", W2, SYSTEM_ACTOR)
    dev2 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC asset.Asset_Add @AssetTypeCode=?, @Name=?, @Status=N'Planned', @ManufacturerEntityId=?, @ModelId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W2, W2 + " relay", org2, mod, SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC device.Device_Add @EntityId=?, @PartNumber=N'P-2', @ActorId=?", dev2, SYSTEM_ACTOR)
    routed = q("DECLARE @e UNIQUEIDENTIFIER; EXEC asset.Asset_Add @AssetTypeCode=?, @Name=?, @Status=N'Planned', @ManufacturerEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W2 + "_r", W2 + " line", org2, SYSTEM_ACTOR)[0][0]
    check(expect_error(cur, "EXEC asset.PlaceAsset @AssetEntityId=?, @NodeEntityId=?, @PlacementKind=N'Installed', @ActorId=?", routed, st2, SYSTEM_ACTOR, contains="routed"), "PlaceAsset refuses a placement for a routed asset (§4.4)")
    check(expect_error(cur, "EXEC asset.PlaceAsset @AssetEntityId=?, @NodeEntityId=?, @PlacementKind=N'Installed', @ActorId=?", dev2, st2, SYSTEM_ACTOR, contains="DevicePosition"), "PlaceAsset refuses a device at a node that is not a DevicePosition")
    check(expect_error(cur, "EXEC asset.PlaceAsset @AssetEntityId=?, @NodeEntityId=?, @PlacementKind=N'Installed', @ActorId=?", dev2, dp, SYSTEM_ACTOR, contains="PlacementOverride"), "PlaceAsset refuses a device category that does not match the position subtype (§5.7)")
    per_o = q("DECLARE @e UNIQUEIDENTIFIER; EXEC personnel.Person_Add @FirstName=N'Smoke', @LastName=N'Override', @DisplayName=?, @EmployerEntityEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W2 + " override", org2, SYSTEM_ACTOR)[0][0]
    usr_o = q("DECLARE @e UNIQUEIDENTIFIER; EXEC security.User_Add @PersonEntityId=?, @UserPrincipalName=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", per_o, W2 + "@smoke.local", SYSTEM_ACTOR)[0][0]
    gr_o = q("DECLARE @e UNIQUEIDENTIFIER; EXEC security.Grant_Add @GranteeKind=N'User', @GranteeEntityId=?, @RoleCode=N'PlacementOverride', @ScopeKind=N'Global', @GrantedByActorId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", usr_o, SYSTEM_ACTOR, SYSTEM_ACTOR)[0][0]
    act_o = q("DECLARE @a UNIQUEIDENTIFIER, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC personnel.Actor_Append @PersonEntityId=?, @ActingUserEntityId=?, @ActorKind=N'Self', @CreatedAt=@t, @ActorId=@a OUTPUT; SELECT @a", per_o, usr_o)[0][0]
    check(expect_error(cur, "EXEC asset.PlaceAsset @AssetEntityId=?, @NodeEntityId=?, @PlacementKind=N'Installed', @ActorId=?", dev2, dp, act_o, contains="OverrideReason"), "PlaceAsset: an override without a reason is refused")
    pl2 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC asset.PlaceAsset @AssetEntityId=?, @NodeEntityId=?, @PlacementKind=N'Installed', @OverrideReason=N'smoke: meter in relay slot', @ActorId=?, @PlacementEntityId=@e OUTPUT; SELECT @e", dev2, dp, act_o)[0][0]
    check(q("SELECT COUNT(*) FROM audit.ActionLog WHERE ActionKindCode = N'Override' AND SubjectTable = N'Placement' AND SubjectEntityId = ?", dev2)[0][0] == 1, "PlaceAsset with an override grant proceeds and logs the override")
    check([r[0] for r in q("SELECT EventKind FROM device.vLifecycleEvent WHERE DeviceEntityId = ? ORDER BY LifecycleEventId", dev2)] == ["Installed"], "PlaceAsset writes the Installed lifecycle event in the same transaction (§5.4)")
    cust = q("DECLARE @e UNIQUEIDENTIFIER; EXEC location.CustodyLocation_Add @Name=?, @CustodyKind=N'Store', @OwnerEntityEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W2 + " store", org2, SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC asset.PlaceAsset @AssetEntityId=?, @CustodyLocationEntityId=?, @PlacementKind=N'Stored', @ActorId=?", dev2, cust, SYSTEM_ACTOR)
    check([r[0] for r in q("SELECT EventKind FROM device.vLifecycleEvent WHERE DeviceEntityId = ? ORDER BY LifecycleEventId", dev2)] == ["Installed", "Removed"], "PlaceAsset to custody writes the Removed event and revises the one placement")
    check(q("SELECT COUNT(*) FROM asset.vPlacement WHERE AssetEntityId = ?", dev2)[0][0] == 1 and q("SELECT COUNT(*) FROM asset.vPlacementHistory WHERE EntityId = ?", pl2)[0][0] >= 2, "one current placement per asset; the prior fact is closed, not lost")
    # firmware (#7, #8)
    fw1, fw2 = str(uuid.uuid4()), str(uuid.uuid4())
    cur.execute("EXEC ref.FirmwareVersion_Upsert @FirmwareVersionId=?, @ModelId=?, @VersionString=N'1.0', @ActorId=?", fw1, mod, SYSTEM_ACTOR)
    check(expect_error(cur, "EXEC device.ApplyFirmware @DeviceEntityId=?, @FirmwareVersionId=?, @ActorId=?", dev2, fw1, SYSTEM_ACTOR, contains="parse transform"), "ApplyFirmware refuses a firmware version with no parse transform, naming what is missing (§5.3)")
    tdef = q("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'Transform.SettingsParse', ?, N'smoke parse transform', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W2 + "_parse", SYSTEM_ACTOR)[0][0]
    wrong = q("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'CharacteristicSchema.AssetTemplate', ?, N'smoke not a transform', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W2 + "_tmpl", SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC ref.FirmwareVersion_Upsert @FirmwareVersionId=?, @ModelId=?, @VersionString=N'1.0', @ParseTransformDefinitionEntityId=?, @ActorId=?", fw1, mod, wrong, SYSTEM_ACTOR)
    check(expect_error(cur, "EXEC device.ApplyFirmware @DeviceEntityId=?, @FirmwareVersionId=?, @ActorId=?", dev2, fw1, SYSTEM_ACTOR, contains="not a Transform.SettingsParse"), "ApplyFirmware refuses a parse transform of the wrong definition kind")
    cur.execute("EXEC ref.FirmwareVersion_Upsert @FirmwareVersionId=?, @ModelId=?, @VersionString=N'1.0', @ParseTransformDefinitionEntityId=?, @ActorId=?", fw1, mod, tdef, SYSTEM_ACTOR)
    cur.execute("EXEC ref.FirmwareVersion_Upsert @FirmwareVersionId=?, @ModelId=?, @VersionString=N'1.1', @ParseTransformDefinitionEntityId=?, @ActorId=?", fw2, mod, tdef, SYSTEM_ACTOR)
    cur.execute("EXEC device.ApplyFirmware @DeviceEntityId=?, @FirmwareVersionId=?, @ActorId=?", dev2, fw1, SYSTEM_ACTOR)
    cur.execute("EXEC device.ApplyFirmware @DeviceEntityId=?, @FirmwareVersionId=?, @ActorId=?", dev2, fw2, SYSTEM_ACTOR)
    check(lo(q("SELECT CurrentFirmwareVersionId FROM device.vDevice WHERE EntityId = ?", dev2)[0][0]) == lo(fw2), "ApplyFirmware derives Device.CurrentFirmwareVersionId (§5.1)")
    fh = q("SELECT COUNT(*) FROM device.vFirmwareHistory WHERE DeviceEntityId = ?", dev2)[0][0]
    fhh = q("SELECT COUNT(*) FROM device.vFirmwareHistoryHistory WHERE DeviceEntityId = ?", dev2)[0][0]
    check(fh == 1 and fhh >= 2, f"ApplyFirmware opens a new period and closes the prior one ({fh} open, {fhh} versions)")
    check(q("SELECT COUNT(*) FROM audit.ActionLog WHERE ActionKindCode = N'FirmwareChanged' AND SubjectEntityId = ?", dev2)[0][0] == 2, "ApplyFirmware logs FirmwareChanged for the re-validation rule")
    # delegation (#34)
    per_d = q("DECLARE @e UNIQUEIDENTIFIER; EXEC personnel.Person_Add @FirstName=N'Smoke', @LastName=N'Delegate', @DisplayName=?, @EmployerEntityEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W2 + " delegate", org2, SYSTEM_ACTOR)[0][0]
    check(expect_error(cur, "DECLARE @e UNIQUEIDENTIFIER; EXEC security.Delegate @FromPersonEntityId=?, @ToPersonEntityId=?, @RoleCode=N'PCTechnician', @ActorId=?, @EntityId=@e OUTPUT", per_o, per_d, SYSTEM_ACTOR, contains="not positional"), "Delegate refuses a role that is not positional (§11.5)")
    dlg = q("DECLARE @e UNIQUEIDENTIFIER; EXEC security.Delegate @FromPersonEntityId=?, @ToPersonEntityId=?, @RoleCode=N'Administrator', @Reason=N'smoke', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", per_o, per_d, SYSTEM_ACTOR)[0][0]
    check(q("SELECT COUNT(*) FROM security.vDelegation WHERE EntityId = ?", dlg)[0][0] == 1, "Delegate writes a positional delegation")
    # cleanup (soft only)
    cur.execute("EXEC security.Delegation_SoftDelete @EntityId=?, @ActorId=?", dlg, SYSTEM_ACTOR)
    cur.execute("EXEC security.Grant_SoftDelete @EntityId=?, @ActorId=?", gr_o, SYSTEM_ACTOR)
    cur.execute("EXEC security.User_SoftDelete @EntityId=?, @ActorId=?", usr_o, SYSTEM_ACTOR)
    for pe in (per_o, per_d):
        cur.execute("EXEC personnel.Person_SoftDelete @EntityId=?, @ActorId=?", pe, SYSTEM_ACTOR)
    for e in q("SELECT EntityId FROM device.vFirmwareHistory WHERE DeviceEntityId = ?", dev2):
        cur.execute("EXEC device.FirmwareHistory_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    cur.execute("EXEC asset.Placement_SoftDelete @EntityId=?, @ActorId=?", pl2, SYSTEM_ACTOR)
    cur.execute("EXEC device.Device_SoftDelete @EntityId=?, @ActorId=?", dev2, SYSTEM_ACTOR)
    for a_ in (dev2, routed):
        cur.execute("EXEC asset.Asset_SoftDelete @EntityId=?, @ActorId=?", a_, SYSTEM_ACTOR)
    for fw in (fw1, fw2):
        cur.execute("EXEC ref.FirmwareVersion_Deactivate @FirmwareVersionId=?, @ActorId=?", fw, SYSTEM_ACTOR)
    cur.execute("EXEC ref.Model_Deactivate @ModelId=?, @ActorId=?", mod, SYSTEM_ACTOR)
    cur.execute("EXEC ref.Manufacturer_Deactivate @ManufacturerId=?, @ActorId=?", man, SYSTEM_ACTOR)
    for d_ in (tdef, wrong):
        cur.execute("EXEC config.Definition_SoftDelete @EntityId=?, @ActorId=?", d_, SYSTEM_ACTOR)
    cur.execute("EXEC location.CustodyLocation_SoftDelete @EntityId=?, @ActorId=?", cust, SYSTEM_ACTOR)
    for e in q("SELECT EntityId FROM location.vAdjacency WHERE LinearNodeEntityId = ?", rw):
        cur.execute("EXEC location.Adjacency_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    for sg in (seg1, seg2):
        cur.execute("EXEC location.Segment_SoftDelete @EntityId=?, @ActorId=?", sg, SYSTEM_ACTOR)
    for n_ in (seg1, seg2, rw, dp, pan, b1, b2, st2, reg2):
        cur.execute("EXEC location.Node_SoftDelete @EntityId=?, @ActorId=?", n_, SYSTEM_ACTOR)
    cur.execute("EXEC party.Entity_SoftDelete @EntityId=?, @ActorId=?", org2, SYSTEM_ACTOR)
    for t_ in (W2, W2 + "_r"):
        cur.execute("EXEC ref.AssetType_Deactivate @AssetTypeCode=?, @ActorId=?", t_, SYSTEM_ACTOR)

    # ================================================================ wave 3: steps 6–8
    W3 = "smoke_w3_" + uuid.uuid4().hex[:6]
    cur.execute("EXEC ref.AssetType_Upsert @AssetTypeCode=?, @Name=N'smoke relay type', @AssetClassCode=N'Secondary', @IsDevice=1, @ActorId=?", W3, SYSTEM_ACTOR)
    org3 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC party.Entity_Add @Name=?, @EntityKind=N'Utility', @IsOwnerOrganisation=1, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W3 + " utility", SYSTEM_ACTOR)[0][0]
    dev3 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC asset.Asset_Add @AssetTypeCode=?, @Name=?, @Status=N'Planned', @ManufacturerEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W3, W3 + " relay", org3, SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC device.Device_Add @EntityId=?, @ActorId=?", dev3, SYSTEM_ACTOR)
    # ports and a connection (bi-temporal) with the realisation FK and the not-self CHECK
    p1 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC connection.Port_Add @AssetEntityId=?, @PortDesignator=N'ETH1', @PortKindCode=N'Ethernet', @Direction=N'Bidirectional', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", dev3, SYSTEM_ACTOR)[0][0]
    p2 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC connection.Port_Add @AssetEntityId=?, @PortDesignator=N'ETH2', @PortKindCode=N'Ethernet', @Direction=N'Bidirectional', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", dev3, SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC connection.NetworkPort_Add @EntityId=?, @IpAddress=N'10.0.0.1', @ActorId=?", p1, SYSTEM_ACTOR)
    check(q("SELECT COUNT(*) FROM connection.vCyberAsset WHERE DeviceEntityId = ?", dev3)[0][0] == 1, "vCyberAsset lists a device with a network port")
    cur.execute("EXEC connection.PortService_Add @NetworkPortEntityId=?, @Protocol=N'TCP', @LogicalPort=102, @ServiceName=N'MMS', @ActorId=?", p1, SYSTEM_ACTOR)
    check(ev("count(network.port)", dev3) == {"k": "num", "v": "1"} and ev("count(network.vlan)", dev3) == {"k": "num", "v": "0"}, "facts network.port / network.vlan: one network port, no VLAN (#35)")
    check(ev("count(network.services[protocol='TCP'])", dev3) == {"k": "num", "v": "1"} and ev("count(network.services[protocol='UDP'])", dev3) == {"k": "num", "v": "0"}, "fact network.services[protocol] lists the port's services (#35)")
    cx = q("DECLARE @e UNIQUEIDENTIFIER; EXEC connection.Connection_Add @FromKind=N'NetworkPort', @FromEntityId=?, @ToKind=N'NetworkPort', @ToEntityId=?, @RealisationCode=N'EthernetLink', @DesignStatus=N'Designed', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", p1, p2, SYSTEM_ACTOR)[0][0]
    check(expect_error(cur, "EXEC connection.Connection_Add @FromKind=N'NetworkPort', @FromEntityId=?, @ToKind=N'NetworkPort', @ToEntityId=?, @RealisationCode=N'Teleporter', @DesignStatus=N'Designed', @ActorId=?", p1, p2, SYSTEM_ACTOR, contains="FK_Connection_Realisation"),
          "connection realisation outside ref.ConnectionRealisation is refused")
    check(expect_error(cur, "EXEC connection.Connection_Add @FromKind=N'Port', @FromEntityId=?, @ToKind=N'Port', @ToEntityId=?, @RealisationCode=N'EthernetLink', @DesignStatus=N'Designed', @ActorId=?", p1, p1, SYSTEM_ACTOR, contains="CK_Connection_NotSelf"),
          "CHECK: a connection cannot join a thing to itself")
    time.sleep(0.3); t3 = q("SELECT SYSUTCDATETIME()")[0][0]; time.sleep(0.3)
    cur.execute("EXEC connection.Connection_Revise @EntityId=?, @FromKind=N'NetworkPort', @FromEntityId=?, @ToKind=N'NetworkPort', @ToEntityId=?, @RealisationCode=N'EthernetLink', @DesignStatus=N'Installed', @ActorId=?", cx, p1, p2, SYSTEM_ACTOR)
    now3 = q("SELECT CONVERT(NVARCHAR(40), SYSDATETIMEOFFSET(), 127)")[0][0]
    check(q("SELECT DesignStatus FROM connection.fConnectionAsOf(?, ?) WHERE EntityId = ?", now3, t3, cx)[0][0] == "Designed", "connection as-of: earlier belief shows Designed")
    check(q("SELECT DesignStatus FROM connection.vConnection WHERE EntityId = ?", cx)[0][0] == "Installed", "connection current view shows Installed after revise")
    # document → revision → configuration file → in-service invariant
    dcls = q("SELECT TOP (1) EntityId FROM config.vDefinition WHERE DefinitionKind = N'CharacteristicSchema.DocumentClass'")
    if not dcls:
        cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'CharacteristicSchema.DocumentClass', ?, N'smoke settings file class', @ActorId=?, @EntityId=@e OUTPUT", W3 + "_class", SYSTEM_ACTOR)
        dcls = q("SELECT EntityId FROM config.vDefinition WHERE DefinitionKey = ?", W3 + "_class")
    doc = q("DECLARE @e UNIQUEIDENTIFIER; EXEC document.Document_Add @DocumentClassDefinitionEntityId=?, @Title=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", dcls[0][0], W3 + " settings", SYSTEM_ACTOR)[0][0]
    revA = q("DECLARE @e UNIQUEIDENTIFIER, @r UNIQUEIDENTIFIER; EXEC document.Revision_Add @DocumentEntityId=?, @RevisionLabel=N'A', @Status=N'Draft', @ActorId=?, @EntityId=@e OUTPUT, @RowId=@r OUTPUT; SELECT @r", doc, SYSTEM_ACTOR)[0][0]
    revB = q("DECLARE @e UNIQUEIDENTIFIER, @r UNIQUEIDENTIFIER; EXEC document.Revision_Add @DocumentEntityId=?, @RevisionLabel=N'B', @Status=N'Draft', @ActorId=?, @EntityId=@e OUTPUT, @RowId=@r OUTPUT; SELECT @r", doc, SYSTEM_ACTOR)[0][0]
    cur.execute("DECLARE @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC document.ConfigurationFile_Add @RevisionRowId=?, @DeviceEntityId=?, @FileKind=N'NativeSettings', @CaptureKind=N'Designed', @InServiceFrom=@t, @ActorId=?", revA, dev3, SYSTEM_ACTOR)
    check(q("SELECT COUNT(*) FROM document.vConfigurationFile WHERE RevisionRowId = ?", revA)[0][0] == 1, "Subclass _Add: configuration file keyed by the revision RowId")
    check(q("SELECT IsInServiceUnapproved FROM document.vConfigurationFileStatus WHERE RevisionRowId = ?", revA)[0][0] == 1, "vConfigurationFileStatus flags in service while unapproved")
    check(expect_error(cur, "DECLARE @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC document.ConfigurationFile_Add @RevisionRowId=?, @DeviceEntityId=?, @FileKind=N'NativeSettings', @CaptureKind=N'Designed', @InServiceFrom=@t, @ActorId=?", revB, dev3, SYSTEM_ACTOR, contains="UX_ConfigurationFile_InService"),
          "in-service invariant: a second open NativeSettings file for the same device is refused")
    check(expect_error(cur, "EXEC document.ConfigurationFile_Add @RevisionRowId=?, @DeviceEntityId=NULL, @FileKind=N'NativeSettings', @CaptureKind=N'Designed', @ActorId=?", revB, SYSTEM_ACTOR, contains="CK_ConfigurationFile_ScdDevice"),
          "CHECK: only an SCD may have no device")
    cur.execute("EXEC document.ConfigurationFile_Add @RevisionRowId=?, @DeviceEntityId=?, @FileKind=N'NativeSettings', @CaptureKind=N'Designed', @ActorId=?", revB, dev3, SYSTEM_ACTOR)
    time.sleep(0.05)   # the inserted version's period must be non-zero, or SQL Server drops that history row
    cur.execute("EXEC document.ConfigurationFile_Update @RevisionRowId=?, @DeviceEntityId=?, @FileKind=N'NativeSettings', @CaptureKind=N'Designed', @ParseStatus=N'Parsed', @ActorId=?", revB, dev3, SYSTEM_ACTOR)
    check(q("SELECT ParseStatus FROM document.vConfigurationFile WHERE RevisionRowId = ?", revB)[0][0] == "Parsed", "Subclass _Update by revision RowId")
    check(q("SELECT COUNT(*) FROM document.vConfigurationFileHistory WHERE RevisionRowId = ?", revB)[0][0] >= 2, "Subclass history retains versions")
    # a file with a SHA-256
    fid = q("DECLARE @e UNIQUEIDENTIFIER; EXEC document.File_Add @RevisionRowId=?, @FileName=N'smoke.txt', @MimeType=N'text/plain', @SizeBytes=5, @Sha256=0x2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824, @FileRole=N'Source', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", revA, SYSTEM_ACTOR)[0][0]
    check(q("SELECT CONVERT(NVARCHAR(64), Sha256, 2) FROM document.vFile WHERE EntityId = ?", fid)[0][0].lower() == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824", "document.File stores the SHA-256")
    ft = q("SELECT COUNT(*) FROM sys.tables WHERE name = 'FileStore' AND is_filetable = 1")[0][0]
    check(ft == 1, "document.FileStore deployed as a FILESTREAM FileTable")
    # bytes written through File_Write (MIGRATION-PLAN Q14): FileTable row in a per-revision directory, hash verified, File row cites the stream
    HELLO, HELLO_SHA = "0x68656C6C6F", "0x2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824"
    wf = q(f"""DECLARE @s UNIQUEIDENTIFIER, @e UNIQUEIDENTIFIER, @r UNIQUEIDENTIFIER;
               EXEC document.File_Write @RevisionRowId=?, @FileName=N'smoke-write.txt', @MimeType=N'text/plain', @Content={HELLO}, @FileRole=N'Source',
                    @Sha256={HELLO_SHA}, @ActorId=?, @FileStreamId=@s OUTPUT, @EntityId=@e OUTPUT, @RowId=@r OUTPUT;
               SELECT @s, @e""", revA, SYSTEM_ACTOR)[0]
    check(wf[0] is not None and q("SELECT COUNT(*) FROM document.vFile WHERE EntityId = ? AND FileStreamId = ? AND SizeBytes = 5 AND CONVERT(NVARCHAR(64), Sha256, 2) = ?", wf[1], wf[0], HELLO_SHA[2:])[0][0] == 1,
          "File_Write: document.File row cites the stream with the computed size and SHA-256")
    stored = q("SELECT CONVERT(VARCHAR(5), file_stream), name FROM document.FileStore WHERE stream_id = ?", wf[0])
    check(stored and tuple(stored[0]) == ("hello", "smoke-write.txt"), f"File_Write: bytes stored in document.FileStore ({stored})")
    check(q("""SELECT COUNT(*) FROM document.FileStore f JOIN document.FileStore d ON d.path_locator = f.parent_path_locator
               WHERE f.stream_id = ? AND d.is_directory = 1 AND d.parent_path_locator IS NULL AND d.name = LOWER(?)""", wf[0], revA)[0][0] == 1,
          "File_Write: file sits in a root directory named by the revision RowId")
    check(expect_error(cur, f"EXEC document.File_Write @RevisionRowId=?, @FileName=N'smoke-bad.txt', @MimeType=N'text/plain', @Content={HELLO}, @FileRole=N'Source', @Sha256=0x{'00' * 32}, @ActorId=?", revA, SYSTEM_ACTOR, contains="does not match"),
          "File_Write refuses a caller hash that does not match the content")
    check(expect_error(cur, f"EXEC document.File_Write @RevisionRowId=?, @FileName=N'smoke-write.txt', @MimeType=N'text/plain', @Content={HELLO}, @FileRole=N'Source', @ActorId=?", revA, SYSTEM_ACTOR, contains="already holds"),
          "File_Write refuses a second file of the same name in one revision")
    cur.execute(f"EXEC document.File_Write @RevisionRowId=?, @FileName=N'smoke-write.txt', @MimeType=N'text/plain', @Content={HELLO}, @FileRole=N'Source', @ActorId=?", revB, SYSTEM_ACTOR)
    check(q("SELECT COUNT(*) FROM document.FileStore WHERE name = N'smoke-write.txt' AND is_directory = 0")[0][0] >= 2, "File_Write: the same file name is allowed under another revision")
    # scheme member polymorphic refusal and a bi-temporal scheme member
    stype = q("SELECT TOP (1) v.RowId FROM config.vDefinitionVersion v JOIN config.vDefinition d ON d.EntityId = v.DefinitionEntityId WHERE d.DefinitionKind = N'Program.SchemeType'")
    if not stype:
        cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'Program.SchemeType', ?, N'smoke scheme type', @ActorId=?, @EntityId=@e OUTPUT", W3 + "_stype", SYSTEM_ACTOR)
        stype = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=N'{}', @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", W3 + "_stype", SYSTEM_ACTOR)
    sch = q("DECLARE @e UNIQUEIDENTIFIER; EXEC scheme.Scheme_Add @SchemeTypeDefinitionVersionRowId=?, @Name=?, @Status=N'Designed', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", stype[0][0], W3 + " scheme", SYSTEM_ACTOR)[0][0]
    check(expect_error(cur, "EXEC scheme.SchemeMember_Add @SchemeEntityId=?, @MemberKind=N'Device', @MemberEntityId=?, @MemberRoleCode=N'EndA', @ActorId=?", sch, dev3, SYSTEM_ACTOR, contains="CK_SchemeMember_Kind"),
          "scheme member kind outside the design's list is refused (members are functions and connections, not devices)")
    check(expect_error(cur, "EXEC scheme.SchemeMember_Add @SchemeEntityId=?, @MemberKind=N'Connection', @MemberEntityId=?, @MemberRoleCode=N'EndA', @ActorId=?", sch, str(uuid.uuid4()), SYSTEM_ACTOR, contains="no Member entity"),
          "scheme member with an unknown connection id is refused (fEntityExists)")
    sm = q("DECLARE @e UNIQUEIDENTIFIER; EXEC scheme.SchemeMember_Add @SchemeEntityId=?, @MemberKind=N'Connection', @MemberEntityId=?, @MemberRoleCode=N'TripCircuit', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", sch, cx, SYSTEM_ACTOR)[0][0]
    check(q("SELECT COUNT(*) FROM scheme.vSchemeMember WHERE EntityId = ?", sm)[0][0] == 1, "scheme member written for an existing connection")
    cur.execute("EXEC scheme.AlternateKey_Add @SubjectEntityId=?, @KeyKindCode=N'SchemeNumber', @KeyValue=?, @ActorId=?", sch, W3 + "-S1", SYSTEM_ACTOR)
    check([tuple(r) for r in q("SELECT SchemaName, KeyKindCode FROM core.vAlternateKey WHERE SubjectEntityId = ?", sch)] == [("scheme", "SchemeNumber")], "scheme alternate key visible through core.vAlternateKey")
    # cleanup (soft only)
    for e in q("SELECT EntityId FROM scheme.vAlternateKey WHERE SubjectEntityId = ?", sch):
        cur.execute("EXEC scheme.AlternateKey_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    cur.execute("EXEC scheme.SchemeMember_SoftDelete @EntityId=?, @ActorId=?", sm, SYSTEM_ACTOR)
    cur.execute("EXEC scheme.Scheme_SoftDelete @EntityId=?, @ActorId=?", sch, SYSTEM_ACTOR)
    cur.execute("EXEC document.File_SoftDelete @EntityId=?, @ActorId=?", fid, SYSTEM_ACTOR)
    for r_ in (revA, revB):
        cur.execute("EXEC document.ConfigurationFile_SoftDelete @RevisionRowId=?, @ActorId=?", r_, SYSTEM_ACTOR)
    for e in q("SELECT EntityId FROM document.vRevision WHERE DocumentEntityId = ?", doc):
        cur.execute("EXEC document.Revision_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    cur.execute("EXEC document.Document_SoftDelete @EntityId=?, @ActorId=?", doc, SYSTEM_ACTOR)
    cur.execute("EXEC connection.Connection_SoftDelete @EntityId=?, @ActorId=?", cx, SYSTEM_ACTOR)
    cur.execute("EXEC connection.NetworkPort_SoftDelete @EntityId=?, @ActorId=?", p1, SYSTEM_ACTOR)
    for e in (p1, p2):
        cur.execute("EXEC connection.Port_SoftDelete @EntityId=?, @ActorId=?", e, SYSTEM_ACTOR)
    cur.execute("EXEC device.Device_SoftDelete @EntityId=?, @ActorId=?", dev3, SYSTEM_ACTOR)
    cur.execute("EXEC asset.Asset_SoftDelete @EntityId=?, @ActorId=?", dev3, SYSTEM_ACTOR)
    cur.execute("EXEC party.Entity_SoftDelete @EntityId=?, @ActorId=?", org3, SYSTEM_ACTOR)
    cur.execute("EXEC ref.AssetType_Deactivate @AssetTypeCode=?, @ActorId=?", W3, SYSTEM_ACTOR)

    # ================================================================ wave 3 domain rules: PROCEDURES.md #1, #9, #12, #13, #14, #15, #16
    W3r = "smoke_w3r_" + uuid.uuid4().hex[:6]
    lo = lambda g: str(g).lower()
    add_node = lambda t, parent, name, sub=None: q("DECLARE @e UNIQUEIDENTIFIER; EXEC location.AddNode @NodeTypeCode=?, @ParentEntityId=?, @Name=?, @SubtypeCode=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", t, parent, name, sub, SYSTEM_ACTOR)[0][0]
    org3r = q("DECLARE @e UNIQUEIDENTIFIER; EXEC party.Entity_Add @Name=?, @EntityKind=N'Utility', @IsOwnerOrganisation=1, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W3r + " utility", SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC ref.AssetType_Upsert @AssetTypeCode=?, @Name=N'smoke relay type', @AssetClassCode=N'Secondary', @IsDevice=1, @ActorId=?", W3r, SYSTEM_ACTOR)
    cur.execute("EXEC ref.AssetType_Upsert @AssetTypeCode=?, @Name=N'smoke primary type', @AssetClassCode=N'Primary', @ActorId=?", W3r + "_p", SYSTEM_ACTOR)
    devr = q("DECLARE @e UNIQUEIDENTIFIER; EXEC asset.Asset_Add @AssetTypeCode=?, @Name=?, @Status=N'Planned', @ManufacturerEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W3r, W3r + " relay", org3r, SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC device.Device_Add @EntityId=?, @ActorId=?", devr, SYSTEM_ACTOR)
    prim = q("DECLARE @e UNIQUEIDENTIFIER; EXEC asset.Asset_Add @AssetTypeCode=?, @Name=?, @Status=N'InService', @ManufacturerEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W3r + "_p", W3r + " line", org3r, SYSTEM_ACTOR)[0][0]
    wire = q("DECLARE @e UNIQUEIDENTIFIER; EXEC asset.Asset_Add @AssetTypeCode=?, @Name=?, @Status=N'InService', @ManufacturerEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W3r + "_p", W3r + " wire", org3r, SYSTEM_ACTOR)[0][0]
    regr = add_node("Region", None, W3r + " region"); str_ = add_node("Station", regr, W3r + " station"); bldr = add_node("Building", str_, W3r + " b")
    panr = add_node("Panel", bldr, W3r + " panel"); dpr = add_node("DevicePosition", panr, W3r + " dp", "Relay"); pfr = add_node("ProtectionFunction", dpr, W3r + " 21")
    tbr = add_node("TerminalBlock", panr, W3r + " tb"); st1 = add_node("Stud", tbr, W3r + " s1"); st2_ = add_node("Stud", tbr, W3r + " s2")
    cur.execute("EXEC asset.PlaceAsset @AssetEntityId=?, @NodeEntityId=?, @PlacementKind=N'Installed', @ActorId=?", devr, dpr, SYSTEM_ACTOR)
    # #9 connection rules per realisation
    check(expect_error(cur, "EXEC connection.Connect @FromKind=N'Stud', @FromEntityId=?, @ToKind=N'Stud', @ToEntityId=?, @RealisationCode=N'PanelWire', @ActorId=?", st1, st2_, SYSTEM_ACTOR, contains="carrier"), "Connect: PanelWire without a carrier is refused (§6.2)")
    check(expect_error(cur, "EXEC connection.Connect @FromKind=N'Stud', @FromEntityId=?, @ToKind=N'Stud', @ToEntityId=?, @RealisationCode=N'PanelWire', @CarrierAssetEntityId=?, @ActorId=?", st1, panr, wire, SYSTEM_ACTOR, contains="not a current node of the stated kind"), "Connect: a Stud endpoint must be a Stud node")
    wcx = q("DECLARE @e UNIQUEIDENTIFIER; EXEC connection.Connect @FromKind=N'Stud', @FromEntityId=?, @ToKind=N'Stud', @ToEntityId=?, @RealisationCode=N'PanelWire', @CarrierAssetEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", st1, st2_, wire, SYSTEM_ACTOR)[0][0]
    check(q("SELECT COUNT(*) FROM connection.vConnection WHERE EntityId = ?", wcx)[0][0] == 1, "Connect: PanelWire stud-to-stud with a carrier written")
    pr1 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC connection.Port_Add @AssetEntityId=?, @PortDesignator=N'ETH1', @PortKindCode=N'Ethernet', @Direction=N'Bidirectional', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", devr, SYSTEM_ACTOR)[0][0]
    pr2 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC connection.Port_Add @AssetEntityId=?, @PortDesignator=N'ETH2', @PortKindCode=N'Ethernet', @Direction=N'Bidirectional', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", devr, SYSTEM_ACTOR)[0][0]
    check(expect_error(cur, "EXEC connection.Connect @FromKind=N'Port', @FromEntityId=?, @ToKind=N'Port', @ToEntityId=?, @RealisationCode=N'EthernetLink', @ActorId=?", pr1, pr2, SYSTEM_ACTOR, contains="network ports"), "Connect: EthernetLink needs NetworkPort endpoints")
    for p_ in (pr1, pr2):
        cur.execute("EXEC connection.NetworkPort_Add @EntityId=?, @IpAddress=N'10.0.0.9', @ActorId=?", p_, SYSTEM_ACTOR)
    check(expect_error(cur, "EXEC connection.Connect @FromKind=N'NetworkPort', @FromEntityId=?, @ToKind=N'NetworkPort', @ToEntityId=?, @RealisationCode=N'EthernetLink', @CarrierAssetEntityId=?, @ActorId=?", pr1, pr2, wire, SYSTEM_ACTOR, contains="no carrier"), "Connect: EthernetLink refuses a carrier")
    check(expect_error(cur, "EXEC connection.Connect @FromKind=N'Port', @FromEntityId=?, @ToKind=N'Port', @ToEntityId=?, @RealisationCode=N'Goose', @ActorId=?", pr1, pr2, SYSTEM_ACTOR, contains="Dataset"), "Connect: Goose runs from a Dataset")
    ecx = q("DECLARE @e UNIQUEIDENTIFIER; EXEC connection.Connect @FromKind=N'NetworkPort', @FromEntityId=?, @ToKind=N'NetworkPort', @ToEntityId=?, @RealisationCode=N'EthernetLink', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", pr1, pr2, SYSTEM_ACTOR)[0][0]
    check(ev("count(device.connections[realisation='EthernetLink'])", devr) == {"k": "num", "v": "1"} and ev("count(device.connections[realisation='Goose'])", devr) == {"k": "num", "v": "0"}, "fact device.connections[realisation] counts the device's connections of that realisation (#35)")
    # #12 scheme members and the expanded view
    stype3 = q("SELECT TOP (1) v.RowId FROM config.vDefinitionVersion v JOIN config.vDefinition d ON d.EntityId = v.DefinitionEntityId WHERE d.DefinitionKind = N'Program.SchemeType'")
    if not stype3:
        cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'Program.SchemeType', ?, N'smoke scheme type', @ActorId=?, @EntityId=@e OUTPUT", W3r + "_stype", SYSTEM_ACTOR)
        stype3 = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=N'{}', @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", W3r + "_stype", SYSTEM_ACTOR)
    schr = q("DECLARE @e UNIQUEIDENTIFIER; EXEC scheme.Scheme_Add @SchemeTypeDefinitionVersionRowId=?, @Name=?, @Status=N'InService', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", stype3[0][0], W3r + " scheme", SYSTEM_ACTOR)[0][0]
    check(expect_error(cur, "EXEC scheme.AddSchemeMember @SchemeEntityId=?, @MemberKind=N'ProtectionFunction', @MemberEntityId=?, @MemberRoleCode=N'EndA', @ActorId=?", schr, panr, SYSTEM_ACTOR, contains="ProtectionFunction node"), "AddSchemeMember: a ProtectionFunction member must be a node of that type (§7.2)")
    check(expect_error(cur, "EXEC scheme.AddSchemeMember @SchemeEntityId=?, @MemberKind=N'Channel', @MemberEntityId=?, @MemberRoleCode=N'Channel', @ActorId=?", schr, str(uuid.uuid4()), SYSTEM_ACTOR, contains="channel asset"), "AddSchemeMember: a Channel member must be a current asset")
    sm1 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC scheme.AddSchemeMember @SchemeEntityId=?, @MemberKind=N'ProtectionFunction', @MemberEntityId=?, @MemberRoleCode=N'EndA', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", schr, pfr, SYSTEM_ACTOR)[0][0]
    sm2 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC scheme.AddSchemeMember @SchemeEntityId=?, @MemberKind=N'Connection', @MemberEntityId=?, @MemberRoleCode=N'TripCircuit', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", schr, wcx, SYSTEM_ACTOR)[0][0]
    # FORMULA-GRAMMAR.md §4.2 / PROCEDURES.md #35: a parameterised fact read through the interpreter on real rows
    import formula as FG
    r = ev("count(scheme.members[role='EndA'])", schr)
    check(r.get("k") == "num" and r.get("v") == "1", f"the engine: count(scheme.members[role='EndA']) = 1 on the scheme ({r})")
    r = ev("all(scheme.members[role='TripCircuit'], m -> m in scheme.members[role='TripCircuit'])", schr)
    check(r == {"k": "bool", "v": True}, f"the engine: a lambda over scheme.members binds its variable ({r})")
    r = ev("count(scheme.members[role='Nope'])", schr)
    check(r == {"k": "num", "v": "0"}, f"the engine: no member in that role is an empty set, not Unknown ({r})")
    exp = {r[0]: (lo(r[1]) if r[1] else None, lo(r[2]) if r[2] else None) for r in q("SELECT MemberKind, ResolvedDeviceEntityId, ConnectionEntityId FROM scheme.vSchemeExpanded WHERE SchemeEntityId = ?", schr)}
    check(exp.get("ProtectionFunction") == (lo(devr), None) and exp.get("Connection") == (None, lo(wcx)), f"vSchemeExpanded resolves the function to the device installed at its position and the connection to itself ({exp})")
    cur.execute("EXEC scheme.SchemeProtects_Add @SchemeEntityId=?, @PrimaryAssetEntityId=?, @ZoneRole=N'Primary', @ActorId=?", schr, prim, SYSTEM_ACTOR)
    # #14 in-service opener; #16 approval segregation; #1 warn-and-log
    dcls3 = q("SELECT TOP (1) EntityId FROM config.vDefinition WHERE DefinitionKind = N'CharacteristicSchema.DocumentClass'")
    if not dcls3:
        cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'CharacteristicSchema.DocumentClass', ?, N'smoke settings file class', @ActorId=?, @EntityId=@e OUTPUT", W3r + "_class", SYSTEM_ACTOR)
        dcls3 = q("SELECT EntityId FROM config.vDefinition WHERE DefinitionKey = ?", W3r + "_class")
    docr = q("DECLARE @e UNIQUEIDENTIFIER; EXEC document.Document_Add @DocumentClassDefinitionEntityId=?, @Title=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", dcls3[0][0], W3r + " settings", SYSTEM_ACTOR)[0][0]
    def add_rev(label, doc_=None):
        return q("DECLARE @e UNIQUEIDENTIFIER, @r UNIQUEIDENTIFIER; EXEC document.Revision_Add @DocumentEntityId=?, @RevisionLabel=?, @Status=N'Draft', @ActorId=?, @EntityId=@e OUTPUT, @RowId=@r OUTPUT; SELECT @r", doc_ or docr, label, SYSTEM_ACTOR)[0][0]
    rA, rB, rC, rD = add_rev("A"), add_rev("B"), add_rev("C"), add_rev("D")
    for r_ in (rA, rB, rC, rD):
        cur.execute("EXEC document.ConfigurationFile_Add @RevisionRowId=?, @DeviceEntityId=?, @FileKind=N'NativeSettings', @CaptureKind=N'Designed', @ActorId=?", r_, devr, SYSTEM_ACTOR)
    un = q("DECLARE @u BIT, @t DATETIMEOFFSET(7) = DATEADD(MINUTE, -10, SYSDATETIMEOFFSET()); EXEC document.SetInService @RevisionRowId=?, @InServiceFrom=@t, @ActorId=?, @IsUnapproved=@u OUTPUT; SELECT @u", rA, SYSTEM_ACTOR)[0][0]
    check(un == True, "SetInService opens a period and reports in-service-while-unapproved (decision 55)")
    check(expect_error(cur, "DECLARE @t DATETIMEOFFSET(7) = DATEADD(MINUTE, -20, SYSDATETIMEOFFSET()); EXEC document.SetInService @RevisionRowId=?, @InServiceFrom=@t, @ActorId=?", rB, SYSTEM_ACTOR, contains="must start after"), "SetInService refuses a period starting before the prior one")
    cur.execute("DECLARE @t DATETIMEOFFSET(7) = DATEADD(MINUTE, -5, SYSDATETIMEOFFSET()); EXEC document.SetInService @RevisionRowId=?, @InServiceFrom=@t, @ActorId=?", rB, SYSTEM_ACTOR)
    st_ = {lo(r[0]): (bool(r[1]), bool(r[2])) for r in q("SELECT RevisionRowId, CASE WHEN InServiceFrom IS NULL THEN 0 ELSE 1 END, CASE WHEN InServiceTo IS NULL THEN 0 ELSE 1 END FROM document.vConfigurationFile WHERE RevisionRowId IN (?, ?)", rA, rB)}
    check(st_[lo(rA)] == (True, True) and st_[lo(rB)] == (True, False), "SetInService closes the device's prior open period in the same transaction (§8.3)")
    check(expect_error(cur, "EXEC document.SetInService @RevisionRowId=?, @ActorId=?", rB, SYSTEM_ACTOR, contains="already in service"), "SetInService refuses a revision already in service")
    check(expect_error(cur, "EXEC document.ApproveRevision @RevisionRowId=?, @ActorId=?", rB, SYSTEM_ACTOR, contains="segregation"), "ApproveRevision: preparer approving without a stated reason is refused (warn-and-log, vision §9.5)")
    cur.execute("EXEC document.ApproveRevision @RevisionRowId=?, @OverrideReason=N'smoke: single-person team', @ActorId=?", rB, SYSTEM_ACTOR)
    check(q("SELECT Status FROM document.vRevision WHERE RowId = ?", rB)[0][0] == "Approved" and q("SELECT COUNT(*) FROM security.vSegregationOverride WHERE SubjectEntityId = ? AND ActionTaken = N'Approve after Prepare'", rB)[0][0] == 1,
          "ApproveRevision with a reason proceeds and records the segregation override (§11.7)")
    check(q("SELECT IsInServiceUnapproved FROM document.vConfigurationFileStatus WHERE RevisionRowId = ?", rB)[0][0] == 0, "approval clears the in-service-unapproved state")
    check(expect_error(cur, "EXEC document.ApproveRevision @RevisionRowId=?, @ActorId=?", rB, a1, contains="Draft or Checked"), "ApproveRevision refuses a revision that is not Draft or Checked")
    # #15 package cascade
    pkgdoc = q("DECLARE @e UNIQUEIDENTIFIER; EXEC document.Document_Add @DocumentClassDefinitionEntityId=?, @Title=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", dcls3[0][0], W3r + " issue package", SYSTEM_ACTOR)[0][0]
    rP = add_rev("P", pkgdoc)
    for i_, r_ in enumerate((rC, rD), start=1):
        cur.execute("EXEC document.SettingsIssuePackageItem_Add @PackageRevisionRowId=?, @ConfigurationFileRevisionRowId=?, @Sequence=?, @ActorId=?", rP, r_, i_, SYSTEM_ACTOR)
    check(expect_error(cur, "EXEC document.ApproveRevision @RevisionRowId=?, @ActorId=?", rC, a1, contains="open settings-issue package"), "ApproveRevision refuses an item of an open package on its own (§8.4)")
    n_items = q("DECLARE @n INT; EXEC document.ApproveSettingsIssuePackage @PackageRevisionRowId=?, @ActorId=?, @ItemsApproved=@n OUTPUT; SELECT @n", rP, a1)[0][0]
    sts = [r[0] for r in q("SELECT Status FROM document.vRevision WHERE RowId IN (?, ?, ?)", rP, rC, rD)]
    check(n_items == 2 and sts == ["Approved"] * 3, f"ApproveSettingsIssuePackage approves the package and cascades to its items ({n_items}, {sts})")
    check(q("SELECT COUNT(*) FROM audit.ActionLog WHERE ActionKindCode = N'Approval' AND SubjectRowId IN (?, ?) AND JSON_VALUE(Detail, '$.authorityPackageRevisionRowId') IS NOT NULL", rC, rD)[0][0] == 2, "item approvals cite the package as authority (decision 60)")
    # #1 definition approval by the author: refused without a reason, overrides with one
    import formula as FG
    cur.execute("EXEC compliance.Standard_Upsert @StandardCode=?, @IssuingEntityEntityId=?, @Subject=N'smoke', @ActorId=?", W3r[-8:], org3r, SYSTEM_ACTOR)
    sv3 = q("DECLARE @e UNIQUEIDENTIFIER, @r UNIQUEIDENTIFIER; EXEC compliance.StandardVersion_Add @StandardCode=?, @VersionLabel=N'1', @ActorId=?, @EntityId=@e OUTPUT, @RowId=@r OUTPUT; SELECT @r", W3r[-8:], SYSTEM_ACTOR)[0][0]
    req3 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC compliance.Requirement_Add @StandardVersionRowId=?, @RequirementNumber=N'R1', @Title=N'smoke misoperation reporting', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", sv3, SYSTEM_ACTOR)[0][0]
    cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'Program.ObligationRule', ?, N'smoke misoperation rule', @ActorId=?, @EntityId=@e OUTPUT", W3r + "_misop", SYSTEM_ACTOR)
    check(expect_error(cur, "DECLARE @r UNIQUEIDENTIFIER; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=N'{}', @ActorId=?, @VersionRowId=@r OUTPUT", W3r + "_misop", SYSTEM_ACTOR, contains="must name its requirement"),
          "an obligation rule without a requirement is refused at authoring (#22)")
    misop_payload = lambda days: FG.canonical({"requirement": str(req3), "subjectKinds": ["Asset"], "scope": FG.parse("true"), "cadence": FG.parse_cadence("within %d d of event" % days)})
    rulev = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=?, @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", W3r + "_misop", misop_payload(30), SYSTEM_ACTOR)[0][0]
    check(expect_error(cur, "EXEC config.ApproveDefinitionVersion @VersionRowId=?, @ActorId=?", rulev, SYSTEM_ACTOR, contains="segregation"), "ApproveDefinitionVersion: author approving without a reason is refused")
    cur.execute("EXEC config.ApproveDefinitionVersion @VersionRowId=?, @OverrideReason=N'smoke: author approves', @ActorId=?", rulev, SYSTEM_ACTOR)
    check(q("SELECT Status FROM config.vDefinitionVersion WHERE RowId = ?", rulev)[0][0] == "Effective" and q("SELECT COUNT(*) FROM security.vSegregationOverride WHERE SubjectEntityId = ?", rulev)[0][0] == 1,
          "ApproveDefinitionVersion by the author with a reason proceeds and logs the override (Program.SegregationRule, WarnAndLog)")
    # #13 protection operation raise
    check(expect_error(cur, "DECLARE @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC scheme.RaiseProtectionOperation @OccurredAt=@t, @TimeSourceQuality=1, @PrimaryAssetEntityId=?, @Outcome=N'Incorrect', @DataSource=N'Scada', @ActorId=?", prim, SYSTEM_ACTOR, contains="MisoperationRuleVersionRowId"),
          "RaiseProtectionOperation: an Incorrect outcome needs the misoperation rule version (§12.8)")
    # The clock is derived by the engine and handed to the procedure. It used to be derived inside it by
    # compliance.fClockDue; that left the database with the rest of the evaluator on 2026-09-10.
    #
    # The instant travels as ISO text, not as a datetime parameter. pyodbc does not preserve the offset
    # of a DATETIMEOFFSET on the way back in — measured 2026-09-10: a value read as 15:47:43-03:00 and
    # sent straight back arrives as 15:47:43+00:00, three hours adrift. That put @OccurredAt before the
    # fixtures existed and the as-of-the-event snapshot found nothing. Text round-trips exactly.
    op_at = q("SELECT CONVERT(NVARCHAR(40), SYSDATETIMEOFFSET(), 127)")[0][0]
    op_clock = engine("clock", rulev, op_at)["clockDueAt"]
    op = q("""DECLARE @e UNIQUEIDENTIFIER, @x UNIQUEIDENTIFIER, @n INT, @t DATETIMEOFFSET(7) = CONVERT(DATETIMEOFFSET(7), ?);
              EXEC scheme.RaiseProtectionOperation @OccurredAt=@t, @TimeSourceQuality=1, @PrimaryAssetEntityId=?, @Outcome=N'Incorrect', @DataSource=N'Scada', @MisoperationRuleVersionRowId=?, @ClockDueAt=?, @ActorId=?, @EntityId=@e OUTPUT, @ExceptionEntityId=@x OUTPUT, @SnapshotRows=@n OUTPUT;
              SELECT @e, @x, @n""", op_at, prim, rulev, op_clock, SYSTEM_ACTOR)[0]
    clk = q("SELECT TOP (1) DATEDIFF(DAY, OpenedAt, ClockDueAt) FROM compliance.vException WHERE RuleDefinitionVersionRowId = ? AND ExceptionKind = N'Misoperation' ORDER BY CreatedAt DESC", rulev)
    check(bool(clk) and clk[0][0] == 30, f"the engine derives the exception clock from the rule's 'within 30 d of event' cadence and RaiseProtectionOperation stores it (#23: {clk})")
    rulev2 = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=?, @ChangeNote=N'60 days', @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", W3r + "_misop", misop_payload(60), SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC config.ApproveDefinitionVersion @VersionRowId=?, @ActorId=?", rulev2, a1)
    nre = engine("clocks", W3r + "_misop")["rederived"]
    clk2 = q("SELECT TOP (1) DATEDIFF(DAY, OpenedAt, ClockDueAt) FROM compliance.vException WHERE RuleDefinitionVersionRowId = ? AND ExceptionKind = N'Misoperation' ORDER BY CreatedAt DESC", rulev2)
    check(nre == 1 and bool(clk2) and clk2[0][0] == 60, f"the engine moves the open exception to the new rule version and recomputes its clock (#23: {nre}, {clk2})")
    check(op[1] is not None and q("SELECT ExceptionKind FROM compliance.vException WHERE EntityId = ?", op[1])[0][0] == "Misoperation"
          and lo(q("SELECT ExceptionEntityId FROM scheme.vProtectionOperation WHERE EntityId = ?", op[0])[0][0]) == lo(op[1]), "RaiseProtectionOperation: Incorrect opens a Misoperation exception and cites it on the operation (§7.6, §12.8)")
    snaps = {r[0]: r[1] for r in q("SELECT SubjectKind, COUNT(*) FROM scheme.vProtectionOperationSnapshot WHERE OperationEntityId = ? GROUP BY SubjectKind", op[0])}
    check(snaps.get("SchemeMember") == 2 and snaps.get("ConfigurationFileRevision") == 1 and op[2] == 3, f"RaiseProtectionOperation snapshots the member and in-service configuration-file row versions ({snaps})")
    check(lo(q("SELECT SchemeEntityId FROM scheme.vProtectionOperationScheme WHERE OperationEntityId = ?", op[0])[0][0]) == lo(schr), "RaiseProtectionOperation links the schemes protecting the primary asset")
    # cleanup (soft only)
    for e in q("SELECT EntityId FROM scheme.vProtectionOperationScheme WHERE OperationEntityId = ?", op[0]):
        cur.execute("EXEC scheme.ProtectionOperationScheme_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    cur.execute("EXEC scheme.ProtectionOperation_SoftDelete @EntityId=?, @ActorId=?", op[0], SYSTEM_ACTOR)
    cur.execute("EXEC compliance.Exception_SoftDelete @EntityId=?, @ActorId=?", op[1], SYSTEM_ACTOR)
    cur.execute("EXEC config.Definition_SoftDelete @EntityId=?, @ActorId=?", q("SELECT EntityId FROM config.vDefinition WHERE DefinitionKey = ?", W3r + "_misop")[0][0], SYSTEM_ACTOR)
    for e in q("SELECT EntityId FROM document.vSettingsIssuePackageItem WHERE PackageRevisionRowId = ?", rP):
        cur.execute("EXEC document.SettingsIssuePackageItem_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    for r_ in (rA, rB, rC, rD):
        cur.execute("EXEC document.ConfigurationFile_SoftDelete @RevisionRowId=?, @ActorId=?", r_, SYSTEM_ACTOR)
    for d_ in (docr, pkgdoc):
        for e in q("SELECT EntityId FROM document.vRevision WHERE DocumentEntityId = ?", d_):
            cur.execute("EXEC document.Revision_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
        cur.execute("EXEC document.Document_SoftDelete @EntityId=?, @ActorId=?", d_, SYSTEM_ACTOR)
    for e in q("SELECT EntityId FROM scheme.vSchemeProtects WHERE SchemeEntityId = ?", schr):
        cur.execute("EXEC scheme.SchemeProtects_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    for e in (sm1, sm2):
        cur.execute("EXEC scheme.SchemeMember_SoftDelete @EntityId=?, @ActorId=?", e, SYSTEM_ACTOR)
    cur.execute("EXEC scheme.Scheme_SoftDelete @EntityId=?, @ActorId=?", schr, SYSTEM_ACTOR)
    for e in (wcx, ecx):
        cur.execute("EXEC connection.Connection_SoftDelete @EntityId=?, @ActorId=?", e, SYSTEM_ACTOR)
    for p_ in (pr1, pr2):
        cur.execute("EXEC connection.NetworkPort_SoftDelete @EntityId=?, @ActorId=?", p_, SYSTEM_ACTOR)
        cur.execute("EXEC connection.Port_SoftDelete @EntityId=?, @ActorId=?", p_, SYSTEM_ACTOR)
    for e in q("SELECT EntityId FROM asset.vPlacement WHERE AssetEntityId = ?", devr):
        cur.execute("EXEC asset.Placement_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    cur.execute("EXEC device.Device_SoftDelete @EntityId=?, @ActorId=?", devr, SYSTEM_ACTOR)
    for a_ in (devr, prim, wire):
        cur.execute("EXEC asset.Asset_SoftDelete @EntityId=?, @ActorId=?", a_, SYSTEM_ACTOR)
    for n_ in (st1, st2_, tbr, pfr, dpr, panr, bldr, str_, regr):
        cur.execute("EXEC location.Node_SoftDelete @EntityId=?, @ActorId=?", n_, SYSTEM_ACTOR)
    cur.execute("EXEC party.Entity_SoftDelete @EntityId=?, @ActorId=?", org3r, SYSTEM_ACTOR)
    for t_ in (W3r, W3r + "_p"):
        cur.execute("EXEC ref.AssetType_Deactivate @AssetTypeCode=?, @ActorId=?", t_, SYSTEM_ACTOR)

    # ================================================================ wave 4: steps 9–12
    W4 = "smoke_w4_" + uuid.uuid4().hex[:6]
    VC4 = W4[-8:]
    org4 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC party.Entity_Add @Name=?, @EntityKind=N'Utility', @IsOwnerOrganisation=1, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W4 + " utility", SYSTEM_ACTOR)[0][0]
    per1 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC personnel.Person_Add @FirstName=N'Smoke', @LastName=N'One', @DisplayName=?, @EmployerEntityEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W4 + " one", org4, SYSTEM_ACTOR)[0][0]
    per2 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC personnel.Person_Add @FirstName=N'Smoke', @LastName=N'Two', @DisplayName=?, @EmployerEntityEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W4 + " two", org4, SYSTEM_ACTOR)[0][0]
    upn = W4 + "@smoke.local"
    usr1 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC security.User_Add @PersonEntityId=?, @UserPrincipalName=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", per1, upn, SYSTEM_ACTOR)[0][0]
    # ResolveActor through SESSION_CONTEXT('UserPrincipalName'): Self, then Delegated, rows reused
    resolve = lambda: q("""SET NOCOUNT ON; EXEC sp_set_session_context N'UserPrincipalName', ?;
                           DECLARE @a UNIQUEIDENTIFIER; EXEC personnel.ResolveActor @ActorId=@a OUTPUT;
                           EXEC sp_set_session_context N'UserPrincipalName', NULL;
                           SELECT CONVERT(NVARCHAR(36), @a), ActorKind, CONVERT(NVARCHAR(36), DelegationEntityId), CONVERT(NVARCHAR(36), PersonEntityId) FROM personnel.Actor WHERE ActorId = @a""", upn)[0]
    s1, s2 = resolve(), resolve()
    check(s1[1] == "Self" and s1[3].lower() == str(per1).lower() and s1[0] == s2[0], f"ResolveActor via UPN -> Self actor for the user's person, reused ({s1[1]})")
    starts = q("SELECT CONVERT(NVARCHAR(40), DATEADD(MINUTE, -1, SYSDATETIMEOFFSET()), 127)")[0][0]
    deleg = q("DECLARE @e UNIQUEIDENTIFIER; EXEC security.Delegation_Add @FromPersonEntityId=?, @ToPersonEntityId=?, @RoleCode=N'Approver', @StartsAt=?, @GrantedByActorId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e",
               per2, per1, starts, SYSTEM_ACTOR, SYSTEM_ACTOR)[0][0]
    d1, d2 = resolve(), resolve()
    check(d1[1] == "Delegated" and d1[2].lower() == str(deleg).lower() and d1[0] == d2[0] and d1[0] != s1[0],
          f"ResolveActor via UPN with a delegation in force -> Delegated actor citing it, reused ({d1[1]})")
    check(expect_error(cur, "SET NOCOUNT ON; EXEC sp_set_session_context N'UserPrincipalName', N'nobody@smoke.local'; DECLARE @a UNIQUEIDENTIFIER; EXEC personnel.ResolveActor @ActorId=@a OUTPUT", contains="enabled user"),
          "ResolveActor refuses an unknown UPN")
    cur.execute("EXEC sp_set_session_context N'UserPrincipalName', NULL")
    # grants
    check(expect_error(cur, "EXEC security.Grant_Add @GranteeKind=N'User', @GranteeEntityId=?, @RoleCode=N'ReadOnly', @ScopeKind=N'NodeSubtree', @GrantedByActorId=?, @ActorId=?", usr1, SYSTEM_ACTOR, SYSTEM_ACTOR, contains="CK_Grant_Scope"),
          "Grant scope CHECK: NodeSubtree without a node refused")
    gr = q("DECLARE @e UNIQUEIDENTIFIER; EXEC security.Grant_Add @GranteeKind=N'User', @GranteeEntityId=?, @RoleCode=N'ReadOnly', @ScopeKind=N'Global', @GrantedByActorId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", usr1, SYSTEM_ACTOR, SYSTEM_ACTOR)[0][0]
    check(q("SELECT COUNT(*) FROM security.vGrant WHERE EntityId = ?", gr)[0][0] == 1, "Global grant written")
    # record -> test sheet -> result -> reading
    cur.execute("EXEC ref.VoltageClass_Upsert @VoltageClassCode=?, @NominalKv=138, @IsTransmission=1, @ActorId=?", VC4, SYSTEM_ACTOR)
    cur.execute("EXEC ref.AssetType_Upsert @AssetTypeCode=?, @Name=N'smoke w4 type', @AssetClassCode=N'Secondary', @IsDevice=1, @ActorId=?", W4, SYSTEM_ACTOR)
    asset4 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC asset.Asset_Add @AssetTypeCode=?, @Name=?, @Status=N'InService', @VoltageClassCode=?, @ManufacturerEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W4, W4 + " relay", VC4, org4, SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC device.Device_Add @EntityId=?, @ActorId=?", asset4, SYSTEM_ACTOR)
    tpk = W4 + "_tp"
    cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'Program.TestPlan', ?, N'smoke test plan', @ActorId=?, @EntityId=@e OUTPUT", tpk, SYSTEM_ACTOR)
    tpv = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=?, @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", tpk, '{}', SYSTEM_ACTOR)[0][0]
    # V2 W0: config.TestPlanStep / TestPlanReading are replaced (SCHEMA-REVIEW §3); TestResult.TestPlanStepRowId and
    # TestReading.TestPlanReadingRowId are unconstrained until W3 re-points them, so the ids here are placeholders.
    step = str(uuid.uuid4())
    rdg = str(uuid.uuid4())
    rec = q("DECLARE @e UNIQUEIDENTIFIER, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC record.Record_Add @RecordKindCode=N'TestSheet', @SubjectKind=N'Device', @SubjectEntityId=?, @OccurredAt=@t, @PerformedByActorId=?, @OverallResult=N'Pass', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", asset4, SYSTEM_ACTOR, SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC record.TestSheet_Add @EntityId=?, @TestPlanDefinitionVersionRowId=?, @ActorId=?", rec, tpv, SYSTEM_ACTOR)
    check(expect_error(cur, "DECLARE @e UNIQUEIDENTIFIER; EXEC record.TestResult_Add @TestSheetEntityId=?, @TestPlanStepRowId=?, @Status=N'NotPerformed', @ActorId=?, @EntityId=@e OUTPUT", rec, step, SYSTEM_ACTOR, contains="CK_TestResult_NotPerformedReason"),
          "TestResult NotPerformed requires a reason (gap G7)")
    tr = q("DECLARE @e UNIQUEIDENTIFIER; EXEC record.TestResult_Add @TestSheetEntityId=?, @TestPlanStepRowId=?, @Status=N'Performed', @Outcome=N'Pass', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", rec, step, SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC record.TestReading_Add @TestResultEntityId=?, @TestPlanReadingRowId=?, @Phase=N'AsLeft', @DecimalValue=1.5, @IsWithinLimits=1, @ActorId=?", tr, rdg, SYSTEM_ACTOR)
    chain = q("""SELECT COUNT(*) FROM record.vRecord r JOIN record.vTestSheet ts ON ts.EntityId = r.EntityId
                 JOIN record.vTestResult tr ON tr.TestSheetEntityId = r.EntityId JOIN record.vTestReading rd ON rd.TestResultEntityId = tr.EntityId
                 WHERE r.EntityId = ?""", rec)[0][0]
    check(chain == 1, "Record -> TestSheet -> TestResult -> TestReading chain readable through the views")
    r = ev("record.last[kind='TestSheet', accepted=false]", asset4)
    check(r.get("k") == "ref" and str(r.get("id")).lower() == str(rec).lower(), f"the engine: record.last[kind, accepted=false] is the test sheet ({r})")
    r = ev("record.last[kind='TestSheet', accepted=true]", asset4)
    check(r.get("k") == "unk", f"the engine: record.last[accepted=true] with no acceptance is Unknown, never a guess ({r})")
    r = ev("record.last[kind='TestSheet', accepted=false].record.occurred_at > @at - 1 h", asset4)
    check(r == {"k": "bool", "v": True}, f"the engine: a path through a single reference yields the record's occurred_at ({r})")
    r = ev("record.last[kind='Calibration', accepted=false] is unknown", asset4)
    check(r == {"k": "bool", "v": True}, "the engine: 'is unknown' is the only test that is never Unknown")
    check(expect_error(cur, "EXEC record.TestReading_Add @TestResultEntityId=?, @TestPlanReadingRowId=?, @Phase=N'AsFound', @DecimalValue=1, @TextValue=N'x', @ActorId=?", tr, rdg, SYSTEM_ACTOR, contains="CK_TestReading_OneValue"),
          "TestReading holds exactly one typed value")
    # obligation rule: fact catalogue gate
    cat = {r[0] for r in q("SELECT FactName FROM compliance.vFactCatalogue")}
    check("asset.voltage_class" in cat and "device.technology" in cat and "station.classification.BesStatus" in cat, f"fact catalogue lists fixed facts ({len(cat)} facts)")
    cur.execute("EXEC compliance.Standard_Upsert @StandardCode=?, @IssuingEntityEntityId=?, @Subject=N'smoke', @ActorId=?", W4[-8:], org4, SYSTEM_ACTOR)
    sv4 = q("DECLARE @e UNIQUEIDENTIFIER, @r UNIQUEIDENTIFIER; EXEC compliance.StandardVersion_Add @StandardCode=?, @VersionLabel=N'1', @ActorId=?, @EntityId=@e OUTPUT, @RowId=@r OUTPUT; SELECT @r", W4[-8:], SYSTEM_ACTOR)[0][0]
    req4 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC compliance.Requirement_Add @StandardVersionRowId=?, @RequirementNumber=N'R3', @SubRequirement=N'3.1', @Title=N'smoke maintenance', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", sv4, SYSTEM_ACTOR)[0][0]
    rk = W4 + "_R"
    cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'Program.ObligationRule', ?, N'smoke rule', @ActorId=?, @EntityId=@e OUTPUT", rk, SYSTEM_ACTOR)
    bad_payload = '{"subjectKinds":["Asset"],"predicate":{"fact":"asset.template.nonexistent","op":"=","value":1}}'
    check(expect_error(cur, "DECLARE @r UNIQUEIDENTIFIER; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=?, @ActorId=?, @VersionRowId=@r OUTPUT", rk, bad_payload, SYSTEM_ACTOR, contains="not in the catalogue"),
          "rule naming an uncatalogued fact is refused at authoring")
    check(expect_error(cur, "DECLARE @r UNIQUEIDENTIFIER; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=?, @ActorId=?, @VersionRowId=@r OUTPUT", rk, '{"requirement":{"standard":"%s","version":"9","number":"R3"},"subjectKinds":["Asset"],"predicate":{"fact":"asset.voltage_class","op":"=","value":"x"}}' % W4[-8:], SYSTEM_ACTOR, contains="does not resolve"),
          "an obligation rule naming an unknown standard version is refused at authoring")
    payload = '{"requirement":{"standard":"%s","version":"1","number":"R3","sub":"3.1"},"subjectKinds":["Asset"],"predicate":{"fact":"asset.voltage_class","op":"=","value":"%s"}}' % (W4[-8:], VC4)
    rv = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=?, @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", rk, payload, SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC config.ApproveDefinitionVersion @VersionRowId=?, @ActorId=?", rv, a1)
    allrows = engine_rows("preview", rk)
    scoped = [r for r in allrows if r[5] == "Scoped"]
    check(len(scoped) == 1 and str(scoped[0][3]).lower() == str(asset4).lower(), f"rule preview scopes the asset by asset.voltage_class ({[s[4] for s in scoped]}; {len(allrows) - len(scoped)} indeterminate: assets without a voltage class)")
    check(q("SELECT COUNT(*) FROM compliance.vRuleEvaluationRun WHERE RuleDefinitionVersionRowId = ? AND Mode = N'Preview'", rv)[0][0] == 1, "preview wrote exactly one RuleEvaluationRun row")
    # FORMULA-GRAMMAR.md §7, §9: a grammar-1 payload previews the same as the grammar-0 one; Unknown scope is Indeterminate
    rk1 = W4 + "_R1"
    cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'Program.ObligationRule', ?, N'smoke rule g1', @ActorId=?, @EntityId=@e OUTPUT", rk1, SYSTEM_ACTOR)
    p1 = {"requirement": str(req4), "subjectKinds": ["Asset"], "scope": FG.parse("asset.voltage_class = '%s' and device.technology is unknown" % VC4)}
    rv1 = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=?, @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", rk1, FG.canonical(p1), SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC config.ApproveDefinitionVersion @VersionRowId=?, @ActorId=?", rv1, a1)
    scoped1 = [r for r in engine_rows("preview", rk1) if r[5] == "Scoped"]
    check(len(scoped1) == 1 and str(scoped1[0][3]).lower() == str(asset4).lower() and scoped1[0][5] == "Scoped", f"grammar-1 rule scopes the same asset ({[(s[4], s[5]) for s in scoped1]})")
    check(expect_error(cur, "DECLARE @r UNIQUEIDENTIFIER; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=?, @ActorId=?, @VersionRowId=@r OUTPUT", rk1, '{"g":7,"scope":{"lit":true,"t":"bool"}}', SYSTEM_ACTOR, contains="grammar_version"),
          "a payload of an unknown grammar version is refused at authoring")
    p2 = {"requirement": str(req4), "subjectKinds": ["Asset"], "scope": FG.parse("asset.voltage_class = '%s' and device.technology = 'Microprocessor'" % VC4), "cadence": FG.parse_cadence("once")}
    rk2 = W4 + "_R2"
    cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'Program.ObligationRule', ?, N'smoke rule g1 unknown', @ActorId=?, @EntityId=@e OUTPUT", rk2, SYSTEM_ACTOR)
    rv2 = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=?, @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", rk2, FG.canonical(p2), SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC config.ApproveDefinitionVersion @VersionRowId=?, @ActorId=?", rv2, a1)
    scoped2 = engine_rows("preview", rk2)
    ind = [s for s in scoped2 if s[5] == "Indeterminate" and str(s[3]).lower() == str(asset4).lower()]
    check(len(ind) == 1 and "device.technology" in str(ind[0][6]) and not [s for s in scoped2 if s[5] == "Scoped"], f"a subject whose scope is Unknown (no model) is listed Indeterminate with the fact named ({[(s[4], s[5], s[6]) for s in ind]})")
    check(q("SELECT SubjectsScoped FROM compliance.vRuleEvaluationRun WHERE RuleDefinitionVersionRowId = ?", rv2)[0][0] == 0, "an Indeterminate subject is not counted as scoped")
    # ---- PROCEDURES.md #22 Effective mode: instances, fact versions, due, work
    wt4 = W4 + "_wt"
    cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'Program.WorkType', ?, N'smoke maintenance work type', @ActorId=?, @EntityId=@e OUTPUT", wt4, SYSTEM_ACTOR)
    wt4v = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=N'{}', @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", wt4, SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC config.ApproveDefinitionVersion @VersionRowId=?, @ActorId=?", wt4v, a1)
    rk3 = W4 + "_R3"
    rule3 = lambda scope, lead, note: FG.canonical({"requirement": str(req4), "subjectKinds": ["Asset"], "scope": FG.parse(scope),
                                                   "cadence": FG.parse_cadence("every 1 y from record.last[kind='TestSheet', accepted=false].record.occurred_at"),
                                                   "evidence": {"recordKinds": ["TestSheet"], "minAcceptance": None}, "workType": wt4, "leadTime": FG.parse(lead), "note": note})
    cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'Program.ObligationRule', ?, N'smoke maintenance rule', @ActorId=?, @EntityId=@e OUTPUT", rk3, SYSTEM_ACTOR)
    rv3 = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=?, @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", rk3, rule3("asset.voltage_class = '%s'" % VC4, "2 y", "v1"), SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC config.ApproveDefinitionVersion @VersionRowId=?, @ActorId=?", rv3, a1)
    eff = lambda key: engine_rows("run", key)
    e1 = [r for r in eff(rk3) if str(r[3]).lower() == str(asset4).lower()]
    occ = q("SELECT OccurredAt FROM record.vRecord WHERE EntityId = ?", rec)[0][0]
    check(len(e1) == 1 and e1[0][5] == "Opened" and e1[0][6] == "Open", f"Effective run opens an Open instance for the scoped asset ({[(r[4], r[5], r[6]) for r in e1]})")
    inst = e1[0][10] if e1 else None
    oi = q("SELECT Status, PeriodStartAt, PeriodEndAt, RaisedWorkRequestEntityId, RowId, RuleDefinitionVersionRowId FROM compliance.vObligationInstance WHERE EntityId = ?", inst) if inst else []
    check(bool(oi) and oi[0][1] == occ and oi[0][2] is not None and (oi[0][2].year - occ.year) == 1, f"the period runs from the last satisfying record (the test sheet) for the 1 y interval ({oi[0][1:3] if oi else None})")
    facts = {r[0]: r[1] for r in q("SELECT FactName, ValueAsRead FROM compliance.vObligationInstanceFact WHERE ObligationInstanceRowId = ?", oi[0][4])} if oi else {}
    check("asset.voltage_class" in facts and facts.get("asset.voltage_class") == VC4 and "cadence.due" in facts and facts.get("cadence.anchor") not in (None, "Unknown"), f"ObligationInstanceFact records the fact versions read and the cadence anchor/due ({facts})")
    due = engine("due", inst) if inst else None
    due_at = datetime.datetime.fromisoformat(due["dueAt"]) if due and due.get("dueAt") else None
    check(bool(due) and due["dueBasis"] == "Cadence" and due_at == oi[0][2] and due["isOverdue"] is False,
          f"the engine derives the due instant from the cadence, equal to the period end ({due})")
    check(bool(oi) and oi[0][3] is not None and (lambda w: lo(w[0]) == lo(inst) and w[1] == "Asset")(q("SELECT RaisedByObligationInstanceEntityId, ScopeKind FROM work.vWorkRequest WHERE EntityId = ?", oi[0][3])[0]), "a work request is raised within the lead time, scoped to the asset and citing the instance")
    run1 = tuple(q("SELECT InstancesOpened, InstancesClosed, InstancesUnchanged FROM compliance.vRuleEvaluationRun WHERE RunId = ?", e1[0][0])[0]) if e1 else None
    check(run1 == (1, 0, 0), f"run counts: opened 1 ({run1})")
    e2 = [r for r in eff(rk3) if str(r[3]).lower() == str(asset4).lower()]
    run2 = tuple(q("SELECT InstancesOpened, InstancesClosed, InstancesUnchanged FROM compliance.vRuleEvaluationRun WHERE RunId = ?", e2[0][0])[0]) if e2 else None
    wrs = q("SELECT COUNT(*) FROM work.vWorkRequest WHERE RaisedByObligationInstanceEntityId = ?", inst)[0][0]
    check(bool(e2) and e2[0][5] == "Unchanged" and run2 == (0, 0, 1) and wrs == 1, f"a second run with nothing changed is idempotent: unchanged, no second work request ({e2[0][5] if e2 else None}, {run2}, {wrs})")
    # a new record after the period start satisfies the instance
    rec2 = q("DECLARE @e UNIQUEIDENTIFIER, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC record.Record_Add @RecordKindCode=N'TestSheet', @SubjectKind=N'Device', @SubjectEntityId=?, @OccurredAt=@t, @PerformedByActorId=?, @OverallResult=N'Pass', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", asset4, SYSTEM_ACTOR, SYSTEM_ACTOR)[0][0]
    e3 = [r for r in eff(rk3) if str(r[3]).lower() == str(asset4).lower()]
    st3 = q("SELECT Status, PeriodStartAt FROM compliance.vObligationInstance WHERE EntityId = ?", inst)[0]
    check(bool(e3) and e3[0][6] == "Open" and st3[0] == "Open" and st3[1] > occ, f"a newer satisfying record moves the period forward: a new Open period anchored on it ({e3[0][5] if e3 else None}, {st3})")
    # a new rule version supersedes
    rv3b = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=?, @ChangeNote=N'v2', @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", rk3, rule3("asset.voltage_class = '%s'" % VC4, "3 y", "v2"), SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC config.ApproveDefinitionVersion @VersionRowId=?, @ActorId=?", rv3b, a1)
    e4 = [r for r in eff(rk3) if str(r[3]).lower() == str(asset4).lower()]
    old_st = q("SELECT Status FROM compliance.vObligationInstance WHERE EntityId = ?", inst)[0][0]
    inst2 = e4[0][10] if e4 else None
    check(bool(e4) and e4[0][5] == "Superseded" and old_st == "Superseded" and inst2 is not None and str(inst2).lower() != str(inst).lower(), f"a new rule version supersedes the instance and opens one under the new version ({e4[0][5] if e4 else None}, {old_st})")
    # scope no longer matches -> NotApplicable
    rv3c = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=?, @ChangeNote=N'v3', @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", rk3, rule3("asset.voltage_class = 'nope'", "3 y", "v3"), SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC config.ApproveDefinitionVersion @VersionRowId=?, @ActorId=?", rv3c, a1)
    e5 = [r for r in eff(rk3) if str(r[3]).lower() == str(asset4).lower()]
    na = q("SELECT Status FROM compliance.vObligationInstance WHERE EntityId = ?", inst2)[0][0] if inst2 else None
    check(bool(e5) and e5[0][5] == "NotApplicable" and na == "NotApplicable" and engine("due", inst2)["status"] == "NotApplicable", f"a subject that leaves the scope closes as NotApplicable and drops off the due list ({e5[0][5] if e5 else None}, {na})")
    e6 = eff(rk2)
    check(all(r[5] == "Indeterminate" for r in e6 if str(r[3]).lower() == str(asset4).lower()) and q("SELECT COUNT(*) FROM compliance.vObligationInstance i JOIN config.DefinitionVersion v ON v.RowId = i.RuleDefinitionVersionRowId WHERE v.RowId = ?", rv2)[0][0] == 0,
          "an Indeterminate subject gets no instance in Effective mode")
    for ie in (inst, inst2):
        if ie:
            cur.execute("EXEC compliance.ObligationInstance_SoftDelete @EntityId=?, @ActorId=?", ie, SYSTEM_ACTOR)
    if oi and oi[0][3]:
        cur.execute("EXEC work.WorkRequest_SoftDelete @EntityId=?, @ActorId=?", oi[0][3], SYSTEM_ACTOR)
    cur.execute("EXEC record.Record_SoftDelete @EntityId=?, @ActorId=?", rec2, SYSTEM_ACTOR)
    check(q("SELECT compliance.fFactValue(?, N'device.technology', SYSDATETIMEOFFSET())", asset4)[0][0] is None, "fFactValue is NULL for a subject without the fact (no model)")
    # exception: bi-temporal as-of
    ex = q("DECLARE @e UNIQUEIDENTIFIER, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC compliance.Exception_Add @SubjectKind=N'Asset', @SubjectEntityId=?, @RuleDefinitionVersionRowId=?, @ExceptionKind=N'SelfReport', @OpenedAt=@t, @OpenedByActorId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", asset4, rv, SYSTEM_ACTOR, SYSTEM_ACTOR)[0][0]
    tx = q("SELECT CONVERT(NVARCHAR(40), SYSUTCDATETIME(), 127)")[0][0]   # as a string: Python truncates datetime2(7) to microseconds
    time.sleep(0.05)
    cur.execute("DECLARE @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC compliance.Exception_Revise @EntityId=?, @SubjectKind=N'Asset', @SubjectEntityId=?, @RuleDefinitionVersionRowId=?, @ExceptionKind=N'SelfReport', @OpenedAt=@t, @OpenedByActorId=?, @ClosureBasis=N'closed', @ActorId=?", ex, asset4, rv, SYSTEM_ACTOR, SYSTEM_ACTOR)
    now4 = q("SELECT CONVERT(NVARCHAR(40), SYSDATETIMEOFFSET(), 127)")[0][0]
    then_b = q("SELECT ClosureBasis FROM compliance.fExceptionAsOf(?, ?) WHERE EntityId = ?", now4, tx, ex)
    now_b = q("SELECT ClosureBasis FROM compliance.fExceptionAsOf(?, SYSUTCDATETIME()) WHERE EntityId = ?", now4, ex)
    check(bool(then_b) and then_b[0][0] is None and bool(now_b) and now_b[0][0] == "closed", "Exception as-of: earlier belief open, current belief closed")
    # cleanup (soft delete only)
    cur.execute("EXEC compliance.Exception_SoftDelete @EntityId=?, @ActorId=?", ex, SYSTEM_ACTOR)
    cur.execute("EXEC record.TestResult_SoftDelete @EntityId=?, @ActorId=?", tr, SYSTEM_ACTOR)
    cur.execute("EXEC record.TestSheet_SoftDelete @EntityId=?, @ActorId=?", rec, SYSTEM_ACTOR)
    cur.execute("EXEC record.Record_SoftDelete @EntityId=?, @ActorId=?", rec, SYSTEM_ACTOR)
    cur.execute("EXEC device.Device_SoftDelete @EntityId=?, @ActorId=?", asset4, SYSTEM_ACTOR)
    cur.execute("EXEC asset.Asset_SoftDelete @EntityId=?, @ActorId=?", asset4, SYSTEM_ACTOR)
    cur.execute("EXEC security.Grant_SoftDelete @EntityId=?, @ActorId=?", gr, SYSTEM_ACTOR)
    cur.execute("EXEC security.Delegation_SoftDelete @EntityId=?, @ActorId=?", deleg, SYSTEM_ACTOR)
    cur.execute("EXEC security.User_SoftDelete @EntityId=?, @ActorId=?", usr1, SYSTEM_ACTOR)
    for pe in (per1, per2):
        cur.execute("EXEC personnel.Person_SoftDelete @EntityId=?, @ActorId=?", pe, SYSTEM_ACTOR)
    cur.execute("EXEC party.Entity_SoftDelete @EntityId=?, @ActorId=?", org4, SYSTEM_ACTOR)
    cur.execute("EXEC ref.AssetType_Deactivate @AssetTypeCode=?, @ActorId=?", W4, SYSTEM_ACTOR)
    cur.execute("EXEC ref.VoltageClass_Deactivate @VoltageClassCode=?, @ActorId=?", VC4, SYSTEM_ACTOR)

    # ================================================================ wave 4 domain rules: PROCEDURES.md #17, #18, #19, #20, #21, #24, #29, #31
    W4r = "smoke_w4r_" + uuid.uuid4().hex[:6]
    lo = lambda g: str(g).lower()
    add_node = lambda t, parent, name, sub=None: q("DECLARE @e UNIQUEIDENTIFIER; EXEC location.AddNode @NodeTypeCode=?, @ParentEntityId=?, @Name=?, @SubtypeCode=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", t, parent, name, sub, SYSTEM_ACTOR)[0][0]
    org4r = q("DECLARE @e UNIQUEIDENTIFIER; EXEC party.Entity_Add @Name=?, @EntityKind=N'Utility', @IsOwnerOrganisation=1, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W4r + " utility", SYSTEM_ACTOR)[0][0]
    VC4r = W4r[-8:]
    cur.execute("EXEC ref.VoltageClass_Upsert @VoltageClassCode=?, @NominalKv=69, @IsTransmission=1, @ActorId=?", VC4r, SYSTEM_ACTOR)
    cur.execute("EXEC ref.AssetType_Upsert @AssetTypeCode=?, @Name=N'smoke w4r type', @AssetClassCode=N'Secondary', @IsDevice=1, @ActorId=?", W4r, SYSTEM_ACTOR)
    man4, mod4 = str(uuid.uuid4()), str(uuid.uuid4())
    cur.execute("EXEC ref.Manufacturer_Upsert @ManufacturerId=?, @EntityEntityId=?, @ShortCode=?, @ActorId=?", man4, org4r, W4r[-8:], SYSTEM_ACTOR)
    cur.execute("EXEC ref.Model_Upsert @ModelId=?, @ManufacturerId=?, @ModelCode=?, @ModelName=N'smoke relay model', @AssetTypeCode=?, @DeviceCategory=N'Relay', @Technology=N'Microprocessor', @ActorId=?", mod4, man4, W4r + "-M", W4r, SYSTEM_ACTOR)
    dev4 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC asset.Asset_Add @AssetTypeCode=?, @Name=?, @Status=N'InService', @VoltageClassCode=?, @ManufacturerEntityId=?, @ModelId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W4r, W4r + " relay", VC4r, org4r, mod4, SYSTEM_ACTOR)[0][0]
    dev4b = q("DECLARE @e UNIQUEIDENTIFIER; EXEC asset.Asset_Add @AssetTypeCode=?, @Name=?, @Status=N'InService', @VoltageClassCode=?, @ManufacturerEntityId=?, @ModelId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W4r, W4r + " relay b", VC4r, org4r, mod4, SYSTEM_ACTOR)[0][0]
    for d_ in (dev4, dev4b):
        cur.execute("EXEC device.Device_Add @EntityId=?, @ActorId=?", d_, SYSTEM_ACTOR)
    per4 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC personnel.Person_Add @FirstName=N'Smoke', @LastName=N'Tech', @DisplayName=?, @EmployerEntityEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W4r + " tech", org4r, SYSTEM_ACTOR)[0][0]
    usr4 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC security.User_Add @PersonEntityId=?, @UserPrincipalName=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", per4, W4r + "@smoke.local", SYSTEM_ACTOR)[0][0]
    # workflow definition and work type (#17)
    wfk, wtk = W4r + "_wf", W4r + "_wt"
    cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'Program.Workflow', ?, N'smoke workflow', @ActorId=?, @EntityId=@e OUTPUT", wfk, SYSTEM_ACTOR)
    wf_payload = ('{"initial":"Draft","states":["Draft","Submitted","Closed"],"final":["Closed"],"transitions":['
                  '{"name":"submit","from":"Draft","to":"Submitted"},'
                  '{"name":"close","from":"Submitted","to":"Closed"},'
                  '{"name":"guarded","from":"Submitted","to":"Closed","guard":{"fact":"asset.voltage_class","op":"=","value":"nope"}}]}')
    wfv = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=?, @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", wfk, wf_payload, SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC config.ApproveDefinitionVersion @VersionRowId=?, @ActorId=?", wfv, a1)
    cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'Program.WorkType', ?, N'smoke work type', @ActorId=?, @EntityId=@e OUTPUT", wtk, SYSTEM_ACTOR)
    wtv = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=?, @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", wtk, '{"workflow":"%s"}' % wfk, SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC config.ApproveDefinitionVersion @VersionRowId=?, @ActorId=?", wtv, a1)
    wr = q("DECLARE @e UNIQUEIDENTIFIER; EXEC work.WorkRequest_Add @WorkTypeDefinitionVersionRowId=?, @Title=?, @ScopeKind=N'Asset', @ScopeEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", wtv, W4r + " request", dev4, SYSTEM_ACTOR)[0][0]
    # V2 W0: work.StartWorkflow / work.Transition and their tables are replaced by the process schema (PROCEDURE-ENGINE §4);
    # the five interpreter checks that stood here return in W4 against process.WorkflowInstance / WorkflowTransition.
    # assignment gate (#18)
    QT = W4r[-8:].upper()
    cur.execute("EXEC personnel.QualificationType_Upsert @QualificationTypeCode=?, @Name=N'smoke relay tech', @ActorId=?", QT, SYSTEM_ACTOR)
    qrk = W4r + "_qr"
    cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'Program.QualificationRequirement', ?, N'smoke qualification requirement', @ActorId=?, @EntityId=@e OUTPUT", qrk, SYSTEM_ACTOR)
    qrv = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=?, @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", qrk,
            '{"requirements":[{"workType":"%s","deviceCategory":"Relay","qualificationTypeCode":"%s","mode":"Block"}]}' % (wtk, QT), SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC config.ApproveDefinitionVersion @VersionRowId=?, @ActorId=?", qrv, a1)
    check(expect_error(cur, "EXEC work.AssignPerson @WorkRequestEntityId=?, @PersonEntityId=?, @ActorId=?", wr, per4, SYSTEM_ACTOR, contains="lacks the qualification"), "AssignPerson refuses an unqualified person under a Block requirement (§11.6)")
    check(expect_error(cur, "EXEC work.AssignPerson @WorkRequestEntityId=?, @PersonEntityId=?, @RoleCode=N'ReadOnly', @ActorId=?", wr, per4, SYSTEM_ACTOR, contains="not an assignment role"), "AssignPerson refuses a role that is not an assignment role")
    ga = q("DECLARE @e UNIQUEIDENTIFIER; EXEC work.AssignPerson @WorkRequestEntityId=?, @PersonEntityId=?, @OverrideReason=N'smoke: supervised', @OverrideApprovedByActorId=?, @ActorId=?, @GrantEntityId=@e OUTPUT; SELECT @e", wr, per4, a1, SYSTEM_ACTOR)[0][0]
    check(q("SELECT COUNT(*) FROM security.vGrant WHERE EntityId = ? AND ScopeKind = N'WorkRequest' AND RoleCode = N'Assignee'", ga)[0][0] == 1
          and q("SELECT COUNT(*) FROM security.vSegregationOverride WHERE SubjectKind = N'WorkRequest' AND SubjectEntityId = ?", wr)[0][0] == 1, "AssignPerson with an approved override grants the assignment role scoped to the request and records the override (§9.7, §11.7)")
    cur.execute("DECLARE @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC personnel.PersonQualification_Add @PersonEntityId=?, @QualificationTypeCode=?, @GrantedAt=@t, @GrantedByActorId=?, @ActorId=?", per4, QT, SYSTEM_ACTOR, SYSTEM_ACTOR)
    ga2 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC work.AssignPerson @WorkRequestEntityId=?, @PersonEntityId=?, @ActorId=?, @GrantEntityId=@e OUTPUT; SELECT @e", wr, per4, SYSTEM_ACTOR)[0][0]
    # ---- PROCEDURES.md #35: the remaining catalogue facts
    check(ev("person.qualifications[type='%s']" % QT, per4) == {"k": "bool", "v": True} and ev("person.qualifications[type='NOPE']", per4) == {"k": "bool", "v": False}, "fact person.qualifications[type] (#35)")
    check(ev("person.authorisations[kind='ElectronicAccess']", per4) == {"k": "bool", "v": False}, "fact person.authorisations[kind] is false before the grant")
    cur.execute("EXEC personnel.Authorisation_Add @PersonEntityId=?, @RightKindCode=N'ElectronicAccess', @ScopeKind=N'DeviceCategory', @ScopeCode=N'Relay', @GrantedByActorId=?, @ActorId=?", per4, SYSTEM_ACTOR, SYSTEM_ACTOR)
    check(ev("person.authorisations[kind='ElectronicAccess']", per4) == {"k": "bool", "v": True}, "fact person.authorisations[kind] is true after the grant (#35)")
    r = ev("person.employer", per4)
    check(r.get("k") == "ref" and str(r.get("id")).lower() == str(org4r).lower(), f"fact person.employer (#35: {r})")
    TM = W4r[-8:].upper() + "_TM"
    cur.execute("EXEC personnel.TrainingModule_Upsert @TrainingModuleCode=?, @Name=N'smoke module', @RequiredFrequencyDays=365, @ActorId=?", TM, SYSTEM_ACTOR)
    tme = q("SELECT EntityId FROM personnel.vTrainingModule WHERE TrainingModuleCode = ?", TM)[0][0]
    check(tme is not None, "personnel.TrainingModule carries an EntityId a record can cite (#35 schema fix)")
    check(ev("person.training_current[module='%s']" % TM, per4) == {"k": "bool", "v": False}, "fact person.training_current[module] is false with no attendance")
    tra = q("DECLARE @e UNIQUEIDENTIFIER, @t DATETIMEOFFSET(7) = DATEADD(DAY, -30, SYSDATETIMEOFFSET()); EXEC record.Record_Add @RecordKindCode=N'TrainingAttendance', @SubjectKind=N'Person', @SubjectEntityId=?, @SecondSubjectKind=N'TrainingModule', @SecondSubjectEntityId=?, @OccurredAt=@t, @PerformedByActorId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", per4, tme, SYSTEM_ACTOR, SYSTEM_ACTOR)[0][0]
    check(ev("person.training_current[module='%s']" % TM, per4) == {"k": "bool", "v": True} and ev("person.training_current[module='NOPE']", per4).get("k") == "unk", "fact person.training_current[module] is true within the module's frequency; an unknown module is Unknown (#35)")
    check(ev("count(entity.agreements[kind='SupportContract'])", org4r) == {"k": "num", "v": "0"} and ev("entity.kind", org4r) == {"k": "text", "v": "Utility"}, "facts entity.agreements[kind] (none yet) and entity.kind (#35)")
    agr = q("DECLARE @e UNIQUEIDENTIFIER; EXEC party.EntityAgreement_Add @EntityEntityId=?, @AgreementKind=N'SupportContract', @Reference=N'smoke', @StartsAt='2020-01-01', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", org4r, SYSTEM_ACTOR)[0][0]
    check(ev("count(entity.agreements[kind='SupportContract'])", org4r) == {"k": "num", "v": "1"} and ev("count(entity.agreements[kind='Licence'])", org4r) == {"k": "num", "v": "0"}, "fact entity.agreements[kind] lists the current agreement of that kind (#35)")
    # document facts: class, current revision, study staleness
    doc4r = q("DECLARE @e UNIQUEIDENTIFIER; EXEC document.Document_Add @DocumentClassDefinitionEntityId=?, @Title=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", dcls3[0][0], W4r + " study", SYSTEM_ACTOR)[0][0]
    check(ev("document.revision_current", doc4r).get("k") == "unk" and ev("document.class", doc4r).get("k") == "text", "facts document.revision_current (Unknown with no approved revision) and document.class (#35)")
    rv4r = q("DECLARE @e UNIQUEIDENTIFIER, @r UNIQUEIDENTIFIER; EXEC document.Revision_Add @DocumentEntityId=?, @RevisionLabel=N'A', @Status=N'Draft', @ActorId=?, @EntityId=@e OUTPUT, @RowId=@r OUTPUT; SELECT @r", doc4r, SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC document.Study_Add @RevisionRowId=?, @StudyKind=N'Coordination', @IsStale=1, @ActorId=?", rv4r, SYSTEM_ACTOR)
    check(ev("study.is_stale", doc4r) == {"k": "bool", "v": True}, "fact study.is_stale reads the study on the document's revision (#35)")
    cur.execute("EXEC document.ApproveRevision @RevisionRowId=?, @ActorId=?", rv4r, a1)
    r = ev("document.revision_current", doc4r)
    check(r.get("k") == "ref" and r.get("kind") == "Revision", f"fact document.revision_current is the approved revision ({r})")
    # advisories: scoped to the model, open until a completed disposition
    adv = q("DECLARE @e UNIQUEIDENTIFIER; EXEC device.Advisory_Add @IssuerEntityEntityId=?, @AdvisoryReference=?, @AdvisoryKind=N'SecurityVulnerability', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", org4r, W4r + "-ADV", SYSTEM_ACTOR)[0][0]
    check(ev("count(device.advisories[open=true])", dev4) == {"k": "num", "v": "0"}, "fact device.advisories[open] is empty before the advisory is scoped to the model")
    cur.execute("EXEC device.AdvisoryScope_Add @AdvisoryEntityId=?, @ModelId=?, @ActorId=?", adv, mod4, SYSTEM_ACTOR)
    check(ev("count(device.advisories[open=true])", dev4) == {"k": "num", "v": "1"} and ev("count(device.advisories[open=true])", dev4b) == {"k": "num", "v": "1"}, "fact device.advisories[open=true] lists an advisory scoped to the device's model, for every device of that model (#35)")
    cur.execute("DECLARE @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC device.AdvisoryDisposition_Add @AdvisoryEntityId=?, @DeviceEntityId=?, @Applicability=N'Applicable', @AssessedByActorId=?, @AssessedAt=@t, @Action=N'Patch', @CompletedAt=@t, @ActorId=?", adv, dev4, SYSTEM_ACTOR, SYSTEM_ACTOR)
    check(ev("count(device.advisories[open=true])", dev4) == {"k": "num", "v": "0"} and ev("count(device.advisories[open=false])", dev4) == {"k": "num", "v": "1"} and ev("count(device.advisories[open=true])", dev4b) == {"k": "num", "v": "1"}, "a completed disposition closes the advisory for that device only (#35)")
    check(ev("function.logical_node", pfr).get("k") == "unk", "fact function.logical_node is Unknown when the function cites no logical node")
    # a Person-scoped obligation rule end to end (decision 56)
    cur.execute("EXEC compliance.Standard_Upsert @StandardCode=?, @IssuingEntityEntityId=?, @Subject=N'smoke', @ActorId=?", W4r[-8:], org4r, SYSTEM_ACTOR)
    sv4r = q("DECLARE @e UNIQUEIDENTIFIER, @r UNIQUEIDENTIFIER; EXEC compliance.StandardVersion_Add @StandardCode=?, @VersionLabel=N'1', @ActorId=?, @EntityId=@e OUTPUT, @RowId=@r OUTPUT; SELECT @r", W4r[-8:], SYSTEM_ACTOR)[0][0]
    req4r = q("DECLARE @e UNIQUEIDENTIFIER; EXEC compliance.Requirement_Add @StandardVersionRowId=?, @RequirementNumber=N'R4', @Title=N'smoke access training', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", sv4r, SYSTEM_ACTOR)[0][0]
    rkP = W4r + "_RP"
    cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'Program.ObligationRule', ?, N'smoke person rule', @ActorId=?, @EntityId=@e OUTPUT", rkP, SYSTEM_ACTOR)
    pP = FG.canonical({"requirement": str(req4r), "subjectKinds": ["Person"], "scope": FG.parse("person.authorisations[kind='ElectronicAccess'] and person.employer = person.employer"), "cadence": FG.parse_cadence("every 1 y from record.last[kind='TrainingAttendance', accepted=false].record.occurred_at"), "evidence": {"recordKinds": ["TrainingAttendance"], "minAcceptance": None}})
    rvP = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=?, @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", rkP, pP, SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC config.ApproveDefinitionVersion @VersionRowId=?, @ActorId=?", rvP, a1)
    eP = engine_rows("run", rkP)
    mine = [r for r in eP if str(r[3]).lower() == str(per4).lower()]
    check(len(mine) == 1 and mine[0][2] == "Person" and mine[0][5] == "Opened" and mine[0][6] == "Open", f"an obligation rule scopes a Person subject and opens an instance on the training record (#35, decision 56: {[(r[2], r[5], r[6]) for r in mine]})")
    instP = mine[0][10] if mine else None
    cat35 = {r[0] for r in q("SELECT FactName FROM compliance.vFactCatalogue WHERE Parameters IS NOT NULL OR FactName IN (N'function.logical_node', N'network.port', N'network.vlan', N'channel.route', N'study.is_stale', N'document.revision_current', N'document.class', N'person.employer', N'entity.kind')")}
    want35 = {"scheme.members", "record.last", "function.logical_node", "device.advisories", "device.connections", "network.port", "network.vlan", "network.services", "channel.route", "channel.links", "asset.owner_of_record", "study.is_stale", "document.revision_current", "document.class", "person.qualifications", "person.authorisations", "person.training_current", "person.employer", "entity.agreements", "entity.kind"}
    check(want35 <= cat35, f"the fact catalogue lists every #35 fact ({sorted(want35 - cat35)} missing)")
    if instP:
        cur.execute("EXEC compliance.ObligationInstance_SoftDelete @EntityId=?, @ActorId=?", instP, SYSTEM_ACTOR)
    cur.execute("EXEC config.Definition_SoftDelete @EntityId=?, @ActorId=?", q("SELECT EntityId FROM config.vDefinition WHERE DefinitionKey = ?", rkP)[0][0], SYSTEM_ACTOR)
    cur.execute("EXEC record.Record_SoftDelete @EntityId=?, @ActorId=?", tra, SYSTEM_ACTOR)
    cur.execute("EXEC party.EntityAgreement_SoftDelete @EntityId=?, @ActorId=?", agr, SYSTEM_ACTOR)
    cur.execute("EXEC device.Advisory_SoftDelete @EntityId=?, @ActorId=?", adv, SYSTEM_ACTOR)
    cur.execute("EXEC document.Document_SoftDelete @EntityId=?, @ActorId=?", doc4r, SYSTEM_ACTOR)
    check(ga2 is not None, "AssignPerson proceeds without override once the person holds the qualification")
    # readback (#19) and baseline (#29)
    dcls4 = q("SELECT TOP (1) EntityId FROM config.vDefinition WHERE DefinitionKind = N'CharacteristicSchema.DocumentClass'")
    if not dcls4:
        cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'CharacteristicSchema.DocumentClass', ?, N'smoke settings file class', @ActorId=?, @EntityId=@e OUTPUT", W4r + "_class", SYSTEM_ACTOR)
        dcls4 = q("SELECT EntityId FROM config.vDefinition WHERE DefinitionKey = ?", W4r + "_class")
    doc4 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC document.Document_Add @DocumentClassDefinitionEntityId=?, @Title=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", dcls4[0][0], W4r + " settings", SYSTEM_ACTOR)[0][0]
    add_rev4 = lambda label: q("DECLARE @e UNIQUEIDENTIFIER, @r UNIQUEIDENTIFIER; EXEC document.Revision_Add @DocumentEntityId=?, @RevisionLabel=?, @Status=N'Draft', @ActorId=?, @EntityId=@e OUTPUT, @RowId=@r OUTPUT; SELECT @r", doc4, label, SYSTEM_ACTOR)[0][0]
    r4a, r4b, r4s = add_rev4("A"), add_rev4("B"), add_rev4("S")
    cur.execute("DECLARE @t DATETIMEOFFSET(7) = DATEADD(MINUTE, -30, SYSDATETIMEOFFSET()); EXEC document.ConfigurationFile_Add @RevisionRowId=?, @DeviceEntityId=?, @FileKind=N'NativeSettings', @CaptureKind=N'Designed', @InServiceFrom=@t, @ActorId=?", r4a, dev4, SYSTEM_ACTOR)
    cur.execute("EXEC document.ConfigurationFile_Add @RevisionRowId=?, @DeviceEntityId=?, @FileKind=N'NativeSettings', @CaptureKind=N'AsFound', @ActorId=?", r4b, dev4, SYSTEM_ACTOR)
    cur.execute("EXEC document.ConfigurationFile_Add @RevisionRowId=?, @DeviceEntityId=NULL, @FileKind=N'Scd', @CaptureKind=N'Designed', @ActorId=?", r4s, SYSTEM_ACTOR)
    rb = q("DECLARE @r UNIQUEIDENTIFIER, @f UNIQUEIDENTIFIER; EXEC record.RecordReadback @SubjectKind=N'Device', @SubjectEntityId=?, @ProducedConfigurationFileRevisionRowId=?, @ComparedToConfigurationFileRevisionRowId=?, @ComparisonResult=N'Differs', @DifferenceCount=3, @ActorId=?, @RecordEntityId=@r OUTPUT, @FindingEntityId=@f OUTPUT; SELECT @r, @f", dev4, r4b, r4a, SYSTEM_ACTOR)[0]
    check(rb[1] is not None and q("SELECT FindingCategoryCode FROM record.vFinding WHERE EntityId = ?", rb[1])[0][0] == "AsFoundDrift"
          and lo(q("SELECT SecondSubjectEntityId FROM record.vRecord WHERE EntityId = ?", rb[1])[0][0]) == lo(rb[0]), "RecordReadback: Differs raises an AsFoundDrift finding citing the readback (§10.8)")
    rb2 = q("DECLARE @r UNIQUEIDENTIFIER, @f UNIQUEIDENTIFIER; EXEC record.RecordReadback @SubjectKind=N'Device', @SubjectEntityId=?, @ProducedConfigurationFileRevisionRowId=?, @ComparedToConfigurationFileRevisionRowId=?, @ComparisonResult=N'Identical', @ActorId=?, @RecordEntityId=@r OUTPUT, @FindingEntityId=@f OUTPUT; SELECT @r, @f", dev4, r4b, r4a, SYSTEM_ACTOR)[0]
    check(rb2[0] is not None and rb2[1] is None, "RecordReadback: Identical raises no finding")
    bl = q("SELECT InServiceConfigurationFileRevisionRowId, ModelId FROM device.fBaseline(?, SYSDATETIMEOFFSET(), SYSUTCDATETIME())", dev4)
    check(len(bl) == 1 and lo(bl[0][0]) == lo(r4a) and lo(bl[0][1]) == lo(mod4), "device.fBaseline returns the in-service configuration file and model on both clocks (§5.8)")
    bl_past = q("SELECT COUNT(*) FROM device.fBaseline(?, DATEADD(DAY, -1, SYSDATETIMEOFFSET()), SYSUTCDATETIME())", dev4)[0][0]
    check(bl_past == 0, "device.fBaseline is empty for a valid-time instant before the device existed")
    # consistency check (#21)
    cur.execute("EXEC asset.AlternateKey_Add @SubjectEntityId=?, @KeyKindCode=N'IedName', @KeyValue=?, @ActorId=?", dev4, W4r + "_IED1", SYSTEM_ACTOR)
    cur.execute("EXEC asset.AlternateKey_Add @SubjectEntityId=?, @KeyKindCode=N'IedName', @KeyValue=?, @ActorId=?", dev4b, W4r + "_IED3", SYSTEM_ACTOR)
    for nm in (W4r + "_IED1", W4r + "_IED2"):
        cur.execute("EXEC connection.Ied_Add @ConfigurationFileRevisionRowId=?, @IedName=?, @ActorId=?", r4s, nm, SYSTEM_ACTOR)
    reg_other = q("SELECT COUNT(*) FROM asset.vAlternateKey k JOIN device.vDevice d ON d.EntityId = k.SubjectEntityId WHERE k.KeyKindCode = N'IedName' AND k.KeyValue NOT LIKE ?", W4r + "%")[0][0]
    cc = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC record.RunConsistencyCheck @ScdConfigurationFileRevisionRowId=?, @ActorId=?, @RecordEntityId=@r OUTPUT, @Findings=@n OUTPUT; SELECT @r, @n", r4s, SYSTEM_ACTOR)[0]
    counts = tuple(q("SELECT IedsInScl, IedsInRegistry, Matched, UnmatchedScl, UnmatchedRegistry FROM record.vConsistencyCheck WHERE EntityId = ?", cc[0])[0])
    check(counts == (2, 2 + reg_other, 1, 1, 1 + reg_other) and cc[1] == 2 + reg_other, f"RunConsistencyCheck counts SCL vs registry and raises one ConsistencyMismatch finding per unmatched IED ({counts}, {cc[1]} findings)")
    check(q("SELECT COUNT(*) FROM record.vFinding f JOIN record.vRecord r ON r.EntityId = f.EntityId WHERE r.SecondSubjectEntityId = ? AND f.FindingCategoryCode = N'ConsistencyMismatch'", cc[0])[0][0] == cc[1], "consistency findings cite the check record")
    # test results and IsPartial (#31); acceptance and package cascade (#20)
    tpk4 = W4r + "_tp"
    cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'Program.TestPlan', ?, N'smoke test plan', @ActorId=?, @EntityId=@e OUTPUT", tpk4, SYSTEM_ACTOR)
    tpv4 = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=N'{}', @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", tpk4, SYSTEM_ACTOR)[0][0]
    # V2 W0: config.TestPlanStep is replaced; record.RecordTestResult (IsPartial from TestPlanStep.IsRequired) went with it.
    # The two IsPartial checks that stood after the sheets return when the procedure document owns "required" (W3/W4).
    def sheet(name):
        r_ = q("DECLARE @e UNIQUEIDENTIFIER, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC record.Record_Add @RecordKindCode=N'TestSheet', @SubjectKind=N'Device', @SubjectEntityId=?, @OccurredAt=@t, @PerformedByActorId=?, @Summary=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", dev4, SYSTEM_ACTOR, name, SYSTEM_ACTOR)[0][0]
        cur.execute("EXEC record.TestSheet_Add @EntityId=?, @TestPlanDefinitionVersionRowId=?, @ActorId=?", r_, tpv4, SYSTEM_ACTOR)
        return r_
    sh1, sh2 = sheet(W4r + " sheet 1"), sheet(W4r + " sheet 2")
    check(expect_error(cur, "EXEC record.AcceptRecord @RecordEntityId=?, @ActorId=?", sh1, SYSTEM_ACTOR, contains="segregation"), "AcceptRecord: tester accepting without a reason is refused (Test/Accept segregation)")
    acc = q("DECLARE @e UNIQUEIDENTIFIER, @n INT; EXEC record.AcceptRecord @RecordEntityId=?, @ActorId=?, @AcceptanceEntityId=@e OUTPUT, @MembersAccepted=@n OUTPUT; SELECT @e", sh1, a1)[0][0]
    check(q("SELECT AcceptanceStatus FROM record.vAcceptance WHERE EntityId = ?", acc)[0][0] == "Accepted", "AcceptRecord by another actor writes the acceptance")
    pkg = q("DECLARE @e UNIQUEIDENTIFIER, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC record.Record_Add @RecordKindCode=N'CommissioningPackage', @SubjectKind=N'Device', @SubjectEntityId=?, @OccurredAt=@t, @PerformedByActorId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", dev4, SYSTEM_ACTOR, SYSTEM_ACTOR)[0][0]
    for i_, m_ in enumerate((sh1, sh2, rb[0]), start=1):
        cur.execute("EXEC record.CommissioningPackageItem_Add @PackageEntityId=?, @MemberRecordEntityId=?, @Sequence=?, @ActorId=?", pkg, m_, i_, SYSTEM_ACTOR)
    n_acc = q("DECLARE @e UNIQUEIDENTIFIER, @n INT; EXEC record.AcceptRecord @RecordEntityId=?, @ActorId=?, @AcceptanceEntityId=@e OUTPUT, @MembersAccepted=@n OUTPUT; SELECT @n", pkg, a1)[0][0]
    check(n_acc == 2 and q("SELECT COUNT(*) FROM record.vAcceptance WHERE RecordEntityId IN (?, ?, ?) AND AcceptanceStatus = N'Accepted'", sh1, sh2, rb[0])[0][0] == 3, f"AcceptRecord on a commissioning package cascades to members not already accepted ({n_acc} cascaded, §10.7)")
    # evidence package freeze (#24)
    cur.execute("EXEC compliance.Standard_Upsert @StandardCode=?, @IssuingEntityEntityId=?, @Subject=N'smoke', @ActorId=?", W4r[-8:], org4r, SYSTEM_ACTOR)
    sv = q("DECLARE @e UNIQUEIDENTIFIER, @r UNIQUEIDENTIFIER; EXEC compliance.StandardVersion_Add @StandardCode=?, @VersionLabel=N'1', @ActorId=?, @EntityId=@e OUTPUT, @RowId=@r OUTPUT; SELECT @r", W4r[-8:], SYSTEM_ACTOR)[0][0]
    ep = q("""DECLARE @e UNIQUEIDENTIFIER, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
              EXEC compliance.EvidencePackage_Add @SubjectKind=N'Device', @SubjectEntityId=?, @StandardVersionRowId=?, @PeriodStartAt=@t, @PeriodEndAt=@t, @ValidAsOf=@t, @BelievedAsOf=@t, @PreparedByActorId=?, @PreparedAt=@t, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e""", dev4, sv, SYSTEM_ACTOR, SYSTEM_ACTOR)[0][0]
    check(expect_error(cur, "EXEC compliance.ApproveEvidencePackage @PackageEntityId=?, @ActorId=?", ep, a1, contains="no manifest"), "ApproveEvidencePackage refuses a package with no manifest (§12.7)")
    cur.execute("EXEC compliance.EvidencePackageManifest_Append @PackageEntityId=?, @ItemKind=N'Record', @ItemRowId=?", ep, rb[0])
    h = q("DECLARE @h BINARY(32); EXEC compliance.ApproveEvidencePackage @PackageEntityId=?, @ActorId=?, @PackageHash=@h OUTPUT; SELECT CONVERT(NVARCHAR(64), @h, 2)", ep, a1)[0][0]
    check(h is not None and len(h) == 64 and q("SELECT CONVERT(NVARCHAR(64), PackageHash, 2) FROM compliance.vEvidencePackage WHERE EntityId = ?", ep)[0][0] == h, "ApproveEvidencePackage stores the SHA-256 over the manifest")
    check(expect_error(cur, "EXEC compliance.EvidencePackageManifest_Append @PackageEntityId=?, @ItemKind=N'Record', @ItemRowId=?", ep, sh1, contains="read-only"), "an approved package's manifest refuses further rows (trigger)")
    ep_row = q("SELECT RowId FROM compliance.vEvidencePackage WHERE EntityId = ?", ep)[0][0]
    check(expect_error(cur, "EXEC compliance.EvidencePackage_SoftDelete @RowId=?, @ActorId=?", ep_row, SYSTEM_ACTOR, contains="read-only")
          or expect_error(cur, "EXEC compliance.EvidencePackage_SoftDelete @EntityId=?, @ActorId=?", ep, SYSTEM_ACTOR, contains="read-only"), "an approved package refuses any later change, including soft delete (trigger)")
    # cleanup (soft only; the approved evidence package is read-only by design and stays)
    for e in q("SELECT EntityId FROM record.vAcceptance WHERE RecordEntityId IN (?, ?, ?, ?)", sh1, sh2, rb[0], pkg):
        cur.execute("EXEC record.Acceptance_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    for e in q("SELECT EntityId FROM record.vCommissioningPackageItem WHERE PackageEntityId = ?", pkg):
        cur.execute("EXEC record.CommissioningPackageItem_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    for e in q("SELECT EntityId FROM record.vTestResult WHERE TestSheetEntityId IN (?, ?)", sh1, sh2):
        cur.execute("EXEC record.TestResult_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    for s_ in (sh1, sh2):
        cur.execute("EXEC record.TestSheet_SoftDelete @EntityId=?, @ActorId=?", s_, SYSTEM_ACTOR)
    for e in q("SELECT EntityId FROM record.vRecord r WHERE r.RecordKindCode = N'Finding' AND r.SecondSubjectEntityId IN (?, ?)", rb[0], cc[0]):
        cur.execute("EXEC record.Finding_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
        cur.execute("EXEC record.Record_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    cur.execute("EXEC record.ConsistencyCheck_SoftDelete @EntityId=?, @ActorId=?", cc[0], SYSTEM_ACTOR)
    for r_ in (rb[0], rb2[0]):
        cur.execute("EXEC record.Readback_SoftDelete @EntityId=?, @ActorId=?", r_, SYSTEM_ACTOR)
    for r_ in (sh1, sh2, pkg, rb[0], rb2[0], cc[0]):
        cur.execute("EXEC record.Record_SoftDelete @EntityId=?, @ActorId=?", r_, SYSTEM_ACTOR)
    for e in q("SELECT EntityId FROM connection.vIed WHERE ConfigurationFileRevisionRowId = ?", r4s):
        cur.execute("EXEC connection.Ied_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    for r_ in (r4a, r4b, r4s):
        cur.execute("EXEC document.ConfigurationFile_SoftDelete @RevisionRowId=?, @ActorId=?", r_, SYSTEM_ACTOR)
    for e in q("SELECT EntityId FROM document.vRevision WHERE DocumentEntityId = ?", doc4):
        cur.execute("EXEC document.Revision_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    cur.execute("EXEC document.Document_SoftDelete @EntityId=?, @ActorId=?", doc4, SYSTEM_ACTOR)
    for e in q("SELECT EntityId FROM security.vGrant WHERE ScopeWorkRequestEntityId = ?", wr):
        cur.execute("EXEC security.Grant_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    for e in q("SELECT EntityId FROM personnel.vPersonQualification WHERE PersonEntityId = ?", per4):
        cur.execute("EXEC personnel.PersonQualification_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    cur.execute("EXEC work.WorkRequest_SoftDelete @EntityId=?, @ActorId=?", wr, SYSTEM_ACTOR)
    for k_ in (wfk, wtk, qrk, tpk4):
        cur.execute("EXEC config.Definition_SoftDelete @EntityId=?, @ActorId=?", q("SELECT EntityId FROM config.vDefinition WHERE DefinitionKey = ?", k_)[0][0], SYSTEM_ACTOR)
    cur.execute("EXEC personnel.QualificationType_Deactivate @QualificationTypeCode=?, @ActorId=?", QT, SYSTEM_ACTOR)
    cur.execute("EXEC security.User_SoftDelete @EntityId=?, @ActorId=?", usr4, SYSTEM_ACTOR)
    cur.execute("EXEC personnel.Person_SoftDelete @EntityId=?, @ActorId=?", per4, SYSTEM_ACTOR)
    for d_ in (dev4, dev4b):
        for e in q("SELECT EntityId FROM asset.vAlternateKey WHERE SubjectEntityId = ?", d_):
            cur.execute("EXEC asset.AlternateKey_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
        cur.execute("EXEC device.Device_SoftDelete @EntityId=?, @ActorId=?", d_, SYSTEM_ACTOR)
        cur.execute("EXEC asset.Asset_SoftDelete @EntityId=?, @ActorId=?", d_, SYSTEM_ACTOR)
    cur.execute("EXEC ref.Model_Deactivate @ModelId=?, @ActorId=?", mod4, SYSTEM_ACTOR)
    cur.execute("EXEC ref.Manufacturer_Deactivate @ManufacturerId=?, @ActorId=?", man4, SYSTEM_ACTOR)
    cur.execute("EXEC party.Entity_SoftDelete @EntityId=?, @ActorId=?", org4r, SYSTEM_ACTOR)
    cur.execute("EXEC ref.AssetType_Deactivate @AssetTypeCode=?, @ActorId=?", W4r, SYSTEM_ACTOR)
    cur.execute("EXEC ref.VoltageClass_Deactivate @VoltageClassCode=?, @ActorId=?", VC4r, SYSTEM_ACTOR)

    # ================================================================ wave 5: steps 13, 15
    W5 = "smoke_w5_" + uuid.uuid4().hex[:6]
    APPROVER = "00000000-0000-0000-0000-000000000002"
    ds = q("""SELECT ds.name FROM sys.indexes i JOIN sys.data_spaces ds ON ds.data_space_id = i.data_space_id
              WHERE i.object_id = OBJECT_ID('event.Event') AND i.index_id IN (0, 1)""")[0][0]
    check(ds == "EventData", f"event.Event data space is EventData ({ds})")
    ids = [r[0] for r in q("""SELECT DISTINCT ds.name FROM sys.indexes i JOIN sys.data_spaces ds ON ds.data_space_id = i.data_space_id
                              WHERE i.object_id = OBJECT_ID('event.Event') AND i.index_id > 1""")]
    check(ids == ["EventIndex"], f"event.Event nonclustered indexes on EventIndex ({ids})")
    cur.execute("EXEC ref.AssetType_Upsert @AssetTypeCode=?, @Name=N'smoke w5 dfr', @AssetClassCode=N'Secondary', @IsDevice=1, @ActorId=?", W5, SYSTEM_ACTOR)
    dev5 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC asset.Asset_Add @AssetTypeCode=?, @Name=?, @Status=N'InService', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W5, W5 + " dfr", SYSTEM_ACTOR)[0][0]
    ev = q("""SET NOCOUNT ON; DECLARE @id UNIQUEIDENTIFIER, @n DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC event.Event_Append @OccurredAt=@n, @TimeSourceQuality=1, @SourceDeviceEntityId=?, @SourceKind=N'Dfr',
              @Format=N'Comtrade', @SampleRateHz=4800, @IngestedAt=@n, @EventId=@id OUTPUT; SELECT @id""", dev5)[0][0]
    ch = q("SET NOCOUNT ON; DECLARE @c BIGINT; EXEC event.Channel_Append @EventId=?, @ChannelKind=N'Analog', @Name=N'IA', @UnitCode=N'A', @Phase=N'A', @SortOrder=1, @ChannelId=@c OUTPUT; SELECT @c", ev)[0][0]
    cur.execute("EXEC event.SampleBlock_Append @ChannelId=?, @BlockSequence=1, @SampleCount=4, @Encoding=N'raw-int16', @Samples=0x0001000200030004", ch)
    check(q("SELECT COUNT(*) FROM event.vSampleBlock WHERE ChannelId = ?", ch)[0][0] == 1, "event tier: Event > Channel > SampleBlock appended and visible")
    check(expect_error(cur, "DECLARE @id UNIQUEIDENTIFIER, @n DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC event.Event_Append @OccurredAt=@n, @TimeSourceQuality=9, @SourceDeviceEntityId=?, @SourceKind=N'Dfr', @Format=N'x', @IngestedAt=@n, @EventId=@id OUTPUT", dev5, contains="CK_Event_TimeSourceQuality"),
          "event.Event refuses TimeSourceQuality outside 0-4")
    mid = q("SET NOCOUNT ON; DECLARE @m BIGINT, @n DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC archive.Manifest_Append @SourceSchema=N'event', @SourceTable=N'SampleBlock', @KeyRangeFrom=N'1', @KeyRangeTo=N'1', @RowCount=1, @MovedAt=@n, @Destination=N'SameDatabaseFilegroup', @DestinationReference=N'BulkFiles', @Sha256=0x00, @MovedByActorId=?, @ManifestId=@m OUTPUT; SELECT @m", SYSTEM_ACTOR)[0][0]
    check(mid is not None and q("SELECT COUNT(*) FROM archive.vManifest WHERE ManifestId = ?", mid)[0][0] == 1, "archive.Manifest appended")
    # backup policy definition → effective view → runs → platform facts
    cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'Program.BackupPolicy', ?, N'smoke backup policy', @ActorId=?, @EntityId=@e OUTPUT", W5, SYSTEM_ACTOR)
    payload = '{"fullSchedule":"0 2 * * 0","differentialSchedule":"0 2 * * 1-6","logIntervalMinutes":15,"destination":"BackupShare","retentionDays":{"Full":35,"Differential":14,"Log":7},"encryption":{"enabled":false},"verify":{"checksum":true,"verifyOnly":true},"rehearsalCadenceDays":90,"TargetRpoMinutes":null,"TargetRtoMinutes":null}'
    bpv = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @PayloadText=?, @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", W5, payload, SYSTEM_ACTOR)[0][0]
    check(bpv is not None, "backup policy payload accepted by ValidateProgramFacts (no facts)")
    cur.execute("EXEC config.ApproveDefinitionVersion @VersionRowId=?, @ActorId=?", bpv, APPROVER)
    eff = q("SELECT VersionRowId, PayloadText FROM config.vEffectiveBackupPolicy WHERE DefinitionKey = ?", W5)
    check(len(eff) == 1 and str(eff[0][0]).lower() == str(bpv).lower() and eff[0][1] == payload, "vEffectiveBackupPolicy returns the effective policy payload")
    br = q("SET NOCOUNT ON; DECLARE @b BIGINT, @n DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC audit.RecordBackupRun @PolicyDefinitionVersionRowId=?, @BackupKind=N'Full', @DatabaseName=N'PnCPlatform_DEV', @StartedAt=@n, @CompletedAt=@n, @DestinationReference=N'smoke', @ChecksumVerified=1, @VerifyOnlyPassed=1, @Outcome=N'Succeeded', @BackupRunId=@b OUTPUT; SELECT @b", bpv)[0][0]
    check(q("SELECT COUNT(*) FROM audit.vBackupRun WHERE BackupRunId = ?", br)[0][0] == 1, "RecordBackupRun appended and visible in audit.vBackupRun")
    rt = q("SET NOCOUNT ON; DECLARE @t BIGINT, @n DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC audit.RecordRestoreTest @BackupRunId=?, @RestoredToServer=N'smoke', @StartedAt=@n, @CompletedAt=@n, @IntegrityCheckPassed=1, @RowCountsMatched=1, @Outcome=N'Succeeded', @ActorId=?, @RestoreTestId=@t OUTPUT; SELECT @t", br, SYSTEM_ACTOR)[0][0]
    check(q("SELECT AchievedRtoMinutes FROM audit.vRestoreTest WHERE RestoreTestId = ?", rt)[0][0] == 0, "RecordRestoreTest appended with derived RTO")
    check(q("SELECT COUNT(*) FROM compliance.vFactCatalogue WHERE FactName IN (N'platform.backup.last.Full', N'platform.restore_test.last')")[0][0] == 2, "catalogue lists platform.backup.last.Full and platform.restore_test.last")
    fv = q("SELECT compliance.fFactValue(NULL, N'platform.backup.last.Full', SYSDATETIMEOFFSET()), compliance.fFactValue(NULL, N'platform.restore_test.last', SYSDATETIMEOFFSET())")[0]
    check(fv[0] is not None and fv[1] is not None, f"platform facts readable through fFactValue ({fv[0]}, {fv[1]})")
    # read logging switch (decision 65)
    cur.execute("EXEC audit.LogRead N'document', N'ConfigurationFile', @SubjectEntityId=?, @ActorId=?", dev5, SYSTEM_ACTOR)
    cur.execute("EXEC audit.LogRead N'asset', N'Asset', @SubjectEntityId=?, @ActorId=?", dev5, SYSTEM_ACTOR)
    reads = q("SELECT SubjectTable FROM audit.vActionLog WHERE ActionKindCode = N'Read' AND SubjectEntityId = ?", dev5)
    check([r[0] for r in reads] == ["ConfigurationFile"], f"LogRead writes for a logged class only ({[r[0] for r in reads]})")
    # cleanup (soft delete only; append-only rows remain by design)
    de5 = q("SELECT EntityId FROM config.vDefinition WHERE DefinitionKey=?", W5)[0][0]
    cur.execute("EXEC config.Definition_SoftDelete @EntityId=?, @ActorId=?", de5, SYSTEM_ACTOR)
    cur.execute("UPDATE config.DefinitionVersion SET IsDeleted=1, DeletedBy=?, DeletedAt=SYSDATETIMEOFFSET() WHERE DefinitionEntityId=?", SYSTEM_ACTOR, de5)
    cur.execute("EXEC asset.Asset_SoftDelete @EntityId=?, @ActorId=?", dev5, SYSTEM_ACTOR)
    cur.execute("EXEC ref.AssetType_Deactivate @AssetTypeCode=?, @ActorId=?", W5, SYSTEM_ACTOR)

    # ================================================================ wave 5 layers: SCHEMA-DESIGN §13.1 (186–190), MIGRATION-PLAN Q27
    W5L = "smoke_w5l_" + uuid.uuid4().hex[:6]
    lo = lambda g: str(g).lower()
    add_node = lambda t, parent, name, sub=None: q("DECLARE @e UNIQUEIDENTIFIER; EXEC location.AddNode @NodeTypeCode=?, @ParentEntityId=?, @Name=?, @SubtypeCode=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", t, parent, name, sub, SYSTEM_ACTOR)[0][0]
    org5 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC party.Entity_Add @Name=?, @EntityKind=N'Utility', @IsOwnerOrganisation=1, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W5L + " utility", SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC ref.AssetType_Upsert @AssetTypeCode=?, @Name=N'smoke line type', @AssetClassCode=N'Primary', @IsRouted=1, @ActorId=?", W5L, SYSTEM_ACTOR)
    line5 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC asset.Asset_Add @AssetTypeCode=?, @Name=?, @Status=N'InService', @ManufacturerEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W5L, W5L + " line", org5, SYSTEM_ACTOR)[0][0]
    line5b = q("DECLARE @e UNIQUEIDENTIFIER; EXEC asset.Asset_Add @AssetTypeCode=?, @Name=?, @Status=N'InService', @ManufacturerEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W5L, W5L + " other line", org5, SYSTEM_ACTOR)[0][0]
    reg5 = add_node("Region", None, W5L + " region"); row5 = add_node("RightOfWay", reg5, W5L + " row")
    sts = [add_node("Structure", row5, f"{W5L}_{i}") for i in range(1, 5)]
    route5 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC location.Route_Add @OwnerAssetEntityId=?, @RouteKind=N'Line', @FromNodeEntityId=?, @ToNodeEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", line5, sts[0], sts[3], SYSTEM_ACTOR)[0][0]
    for i, st_ in enumerate(sts, 1):
        cur.execute("EXEC location.RouteStep_Add @RouteEntityId=?, @Sequence=?, @NodeEntityId=?, @ActorId=?", route5, i, st_, SYSTEM_ACTOR)
    # a layer is data: its export / import behaviour is two transform definitions, no system named in a CHECK
    for k_, kind_ in ((W5L + "_export", "Transform.Export"), (W5L + "_import", "Transform.Import")):
        cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition ?, ?, N'smoke layer transform', @ActorId=?, @EntityId=@e OUTPUT", kind_, k_, SYSTEM_ACTOR)
    exp_d = q("SELECT EntityId FROM config.vDefinition WHERE DefinitionKey = ?", W5L + "_export")[0][0]
    imp_d = q("SELECT EntityId FROM config.vDefinition WHERE DefinitionKey = ?", W5L + "_import")[0][0]
    imp_v = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", W5L + "_import", SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC config.TransformMapping_Add @DefinitionVersionRowId=?, @Direction=N'Parse', @SourcePath=N'bus.number', @TargetKind=N'LayerField', @TargetKey=N'node.number', @ActorId=?", imp_v, SYSTEM_ACTOR)
    check(q("SELECT COUNT(*) FROM config.vTransformMapping WHERE DefinitionVersionRowId = ? AND TargetKind = N'LayerField'", imp_v)[0][0] == 1, "TransformMapping accepts TargetKind LayerField (a layer's rules are mapping rows)")
    layer = q("DECLARE @e UNIQUEIDENTIFIER; EXEC network.Layer_Add @Name=?, @ExportTransformDefinitionEntityId=?, @ImportTransformDefinitionEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W5L + " layer", exp_d, imp_d, SYSTEM_ACTOR)[0][0]
    case5 = q("DECLARE @e UNIQUEIDENTIFIER, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC network.Case_Add @LayerEntityId=?, @Name=?, @SystemModelAt=@t, @Origin=N'Imported', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", layer, W5L + " snapshot", SYSTEM_ACTOR)[0][0]
    check(expect_error(cur, "DECLARE @e UNIQUEIDENTIFIER, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC network.Case_Add @LayerEntityId=?, @Name=N'x', @SystemModelAt=@t, @Origin=N'Aspen', @ActorId=?, @EntityId=@e OUTPUT", layer, SYSTEM_ACTOR, contains="CK_Case_Origin"), "Case.Origin is Imported or Platform — no system is named in the schema")
    n1 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC network.LayerNode_Add @LayerEntityId=?, @ExternalNumber=N'17001', @Name=N'smoke bus A', @FirstCaseEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", layer, case5, SYSTEM_ACTOR)[0][0]
    n2 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC network.LayerNode_Add @LayerEntityId=?, @ExternalNumber=N'17002', @Name=N'smoke bus B', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", layer, SYSTEM_ACTOR)[0][0]
    check(expect_error(cur, "DECLARE @e UNIQUEIDENTIFIER; EXEC network.LayerNode_Add @LayerEntityId=?, @ExternalNumber=N'17001', @Name=N'dup', @ActorId=?, @EntityId=@e OUTPUT", layer, SYSTEM_ACTOR, contains="UX_LayerNode_Number"), "a layer node's external number is unique within its layer")
    cur.execute("EXEC network.AlternateKey_Add @SubjectEntityId=?, @KeyKindCode=N'LayerNodeNumber', @KeyValue=N'17001', @ScopeEntityId=?, @IsPrimaryLabel=1, @ActorId=?", n1, layer, SYSTEM_ACTOR)
    check([tuple(r) for r in q("SELECT SchemaName, KeyKindCode FROM core.vAlternateKey WHERE SubjectEntityId = ?", n1)] == [("network", "LayerNodeNumber")], "LayerNodeNumber key visible through core.vAlternateKey")
    # endpoints: many per node, line-scoped, verified against the route, never guessed
    check(expect_error(cur, "EXEC network.AddLayerNodeEndpoint @LayerNodeEntityId=?, @AnchorKind=N'Structure', @AnchorEntityId=?, @LineAssetEntityId=?, @IsPrimary=1, @ActorId=?", n1, sts[0], line5b, SYSTEM_ACTOR, contains="no route"), "AddLayerNodeEndpoint refuses a line scope whose route does not exist (cannot verify)")
    other_st = add_node("Structure", row5, W5L + "_off")
    check(expect_error(cur, "EXEC network.AddLayerNodeEndpoint @LayerNodeEntityId=?, @AnchorKind=N'Structure', @AnchorEntityId=?, @LineAssetEntityId=?, @IsPrimary=1, @ActorId=?", n1, other_st, line5, SYSTEM_ACTOR, contains="not on the scoped line"), "AddLayerNodeEndpoint refuses a structure that is not on the scoped line's route (§13.1: unresolved beats nearest-neighbour)")
    e1 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC network.AddLayerNodeEndpoint @LayerNodeEntityId=?, @AnchorKind=N'Structure', @AnchorEntityId=?, @LineAssetEntityId=?, @IsPrimary=1, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", n1, sts[0], line5, SYSTEM_ACTOR)[0][0]
    e1b = q("DECLARE @e UNIQUEIDENTIFIER; EXEC network.AddLayerNodeEndpoint @LayerNodeEntityId=?, @AnchorKind=N'Structure', @AnchorEntityId=?, @LineAssetEntityId=?, @IsPrimary=1, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", n1, sts[1], line5, SYSTEM_ACTOR)[0][0]
    prim = [(lo(r[0]), r[1]) for r in q("SELECT EntityId, IsPrimary FROM network.vLayerNodeEndpoint WHERE LayerNodeEntityId = ? ORDER BY CreatedAt", n1)]
    check(dict(prim) == {lo(e1): False, lo(e1b): True}, f"a new primary endpoint demotes the prior one for the same (node, line) ({prim})")
    step3 = q("SELECT EntityId FROM location.vRouteStep WHERE RouteEntityId = ? AND Sequence = 4", route5)[0][0]
    cur.execute("EXEC network.AddLayerNodeEndpoint @LayerNodeEntityId=?, @AnchorKind=N'RouteStep', @AnchorEntityId=?, @LineAssetEntityId=?, @IsPrimary=1, @SnapMethod=N'Imported', @ActorId=?", n2, step3, line5, SYSTEM_ACTOR)
    # branch path derived over route steps between the two primary endpoints
    br = q("DECLARE @e UNIQUEIDENTIFIER; EXEC network.LayerBranch_Add @LayerEntityId=?, @BranchKind=N'LineSection', @FromNodeEntityId=?, @ToNodeEntityId=?, @CircuitId=N'1', @LineAssetEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", layer, n1, n2, line5, SYSTEM_ACTOR)[0][0]
    path = [r[0] for r in q("SELECT Sequence FROM network.vLayerBranchPath WHERE LayerBranchEntityId = ? ORDER BY WalkOrder", br)]
    check(path == [2, 3, 4], f"vLayerBranchPath walks the route steps between the from and to endpoints ({path})")
    n3 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC network.LayerNode_Add @LayerEntityId=?, @ExternalNumber=N'17003', @Name=N'smoke bus C (unresolved)', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", layer, SYSTEM_ACTOR)[0][0]
    br2 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC network.LayerBranch_Add @LayerEntityId=?, @BranchKind=N'LineSection', @FromNodeEntityId=?, @ToNodeEntityId=?, @LineAssetEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", layer, n1, n3, line5, SYSTEM_ACTOR)[0][0]
    check(q("SELECT COUNT(*) FROM network.vLayerBranchPath WHERE LayerBranchEntityId = ?", br2)[0][0] == 0, "a branch with an unresolved endpoint has no path (nothing is guessed)")
    check(expect_error(cur, "EXEC network.LayerBranch_Add @LayerEntityId=?, @BranchKind=N'LineSection', @FromNodeEntityId=?, @ToNodeEntityId=?, @ActorId=?", layer, n1, n1, SYSTEM_ACTOR, contains="CK_LayerBranch_NotSelf"), "CHECK: a branch cannot join a node to itself")
    # reconciliation: candidates are records; a person accepts; ApplyReconciliation writes the endpoint
    tk = W5L + "_cand"
    cur.execute("DECLARE @e UNIQUEIDENTIFIER; EXEC config.AddDefinition N'CharacteristicSchema.RecordTemplate', ?, N'smoke candidate template', @ActorId=?, @EntityId=@e OUTPUT", tk, SYSTEM_ACTOR)
    tv = q("DECLARE @r UNIQUEIDENTIFIER, @n INT; EXEC config.AddDefinitionVersion @DefinitionKey=?, @ActorId=?, @VersionRowId=@r OUTPUT, @VersionNumber=@n OUTPUT; SELECT @r", tk, SYSTEM_ACTOR)[0][0]
    cdef = {}
    for ck, dt in (("anchor_kind", "Text"), ("anchor_entity_id", "Reference"), ("line_asset_entity_id", "Reference"), ("is_primary", "Boolean"), ("confidence", "Decimal"), ("applied_endpoint", "Reference")):
        cdef[ck] = q("DECLARE @r UNIQUEIDENTIFIER; EXEC config.AddCharacteristic @DefinitionVersionRowId=?, @CharacteristicKey=?, @Name=?, @DataType=?, @ReferenceTargetKind=?, @ActorId=?, @RowId=@r OUTPUT; SELECT @r", tv, ck, ck, dt, "Node" if dt == "Reference" else None, SYSTEM_ACTOR)[0][0]
    sess = q("DECLARE @e UNIQUEIDENTIFIER, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC record.Record_Add @RecordKindCode=N'LayerReconciliation', @SubjectKind=N'Layer', @SubjectEntityId=?, @OccurredAt=@t, @PerformedByActorId=?, @Summary=N'smoke session', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", layer, SYSTEM_ACTOR, SYSTEM_ACTOR)[0][0]
    def candidate(node_, anchor_):
        c_ = q("DECLARE @e UNIQUEIDENTIFIER, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC record.Record_Add @RecordKindCode=N'LayerMatchCandidate', @SubjectKind=N'LayerNode', @SubjectEntityId=?, @SecondSubjectKind=N'Record', @SecondSubjectEntityId=?, @OccurredAt=@t, @PerformedByActorId=?, @TemplateDefinitionVersionRowId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", node_, sess, SYSTEM_ACTOR, tv, SYSTEM_ACTOR)[0][0]
        cur.execute("EXEC record.CharacteristicValue_Add @HostEntityId=?, @CharacteristicDefinitionRowId=?, @TextValue=N'Structure', @ActorId=?", c_, cdef["anchor_kind"], SYSTEM_ACTOR)
        cur.execute("EXEC record.CharacteristicValue_Add @HostEntityId=?, @CharacteristicDefinitionRowId=?, @ReferenceEntityId=?, @ActorId=?", c_, cdef["anchor_entity_id"], anchor_, SYSTEM_ACTOR)
        cur.execute("EXEC record.CharacteristicValue_Add @HostEntityId=?, @CharacteristicDefinitionRowId=?, @ReferenceEntityId=?, @ActorId=?", c_, cdef["line_asset_entity_id"], line5, SYSTEM_ACTOR)
        cur.execute("EXEC record.CharacteristicValue_Add @HostEntityId=?, @CharacteristicDefinitionRowId=?, @BooleanValue=1, @ActorId=?", c_, cdef["is_primary"], SYSTEM_ACTOR)
        cur.execute("EXEC record.CharacteristicValue_Add @HostEntityId=?, @CharacteristicDefinitionRowId=?, @DecimalValue=130, @ActorId=?", c_, cdef["confidence"], SYSTEM_ACTOR)
        return c_
    c_acc, c_no = candidate(n3, sts[2]), candidate(n3, sts[3])
    cur.execute("EXEC record.AcceptRecord @RecordEntityId=?, @ActorId=?", c_acc, a1)
    napp = q("DECLARE @n INT; EXEC network.ApplyReconciliation @ReconciliationRecordEntityId=?, @ActorId=?, @Applied=@n OUTPUT; SELECT @n", sess, SYSTEM_ACTOR)[0][0]
    eps = [(r[0], lo(r[1])) for r in q("SELECT SnapMethod, AnchorEntityId FROM network.vLayerNodeEndpoint WHERE LayerNodeEntityId = ?", n3)]
    check(napp == 1 and eps == [("Reconciled", lo(sts[2]))], f"ApplyReconciliation applies the accepted candidate only, as a Reconciled endpoint ({napp}, {eps})")
    napp2 = q("DECLARE @n INT; EXEC network.ApplyReconciliation @ReconciliationRecordEntityId=?, @ActorId=?, @Applied=@n OUTPUT; SELECT @n", sess, SYSTEM_ACTOR)[0][0]
    check(napp2 == 0, "ApplyReconciliation is idempotent (applied candidates carry applied_endpoint)")
    path2 = [r[0] for r in q("SELECT Sequence FROM network.vLayerBranchPath WHERE LayerBranchEntityId = ? ORDER BY WalkOrder", br2)]
    check(path2 == [2, 3], f"once the endpoint is applied the branch path resolves ({path2})")
    # cleanup (soft only)
    for e in q("SELECT EntityId FROM record.vAcceptance WHERE RecordEntityId = ?", c_acc):
        cur.execute("EXEC record.Acceptance_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    for r_ in (c_acc, c_no):
        for e in q("SELECT EntityId FROM record.vCharacteristicValue WHERE HostEntityId = ?", r_):
            cur.execute("EXEC record.CharacteristicValue_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    for r_ in (c_acc, c_no, sess):
        cur.execute("EXEC record.Record_SoftDelete @EntityId=?, @ActorId=?", r_, SYSTEM_ACTOR)
    for b_ in (br, br2):
        cur.execute("EXEC network.LayerBranch_SoftDelete @EntityId=?, @ActorId=?", b_, SYSTEM_ACTOR)
    for nd in (n1, n2, n3):
        for e in q("SELECT EntityId FROM network.vLayerNodeEndpoint WHERE LayerNodeEntityId = ?", nd):
            cur.execute("EXEC network.LayerNodeEndpoint_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
        for e in q("SELECT EntityId FROM network.vAlternateKey WHERE SubjectEntityId = ?", nd):
            cur.execute("EXEC network.AlternateKey_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
        cur.execute("EXEC network.LayerNode_SoftDelete @EntityId=?, @ActorId=?", nd, SYSTEM_ACTOR)
    cur.execute("EXEC network.Case_SoftDelete @EntityId=?, @ActorId=?", case5, SYSTEM_ACTOR)
    cur.execute("EXEC network.Layer_SoftDelete @EntityId=?, @ActorId=?", layer, SYSTEM_ACTOR)
    for k_ in (W5L + "_export", W5L + "_import", tk):
        cur.execute("EXEC config.Definition_SoftDelete @EntityId=?, @ActorId=?", q("SELECT EntityId FROM config.vDefinition WHERE DefinitionKey = ?", k_)[0][0], SYSTEM_ACTOR)
    for e in q("SELECT EntityId FROM location.vRouteStep WHERE RouteEntityId = ?", route5):
        cur.execute("EXEC location.RouteStep_SoftDelete @EntityId=?, @ActorId=?", e[0], SYSTEM_ACTOR)
    cur.execute("EXEC location.Route_SoftDelete @EntityId=?, @ActorId=?", route5, SYSTEM_ACTOR)
    for a_ in (line5, line5b):
        cur.execute("EXEC asset.Asset_SoftDelete @EntityId=?, @ActorId=?", a_, SYSTEM_ACTOR)
    for n_ in sts + [other_st, row5, reg5]:
        cur.execute("EXEC location.Node_SoftDelete @EntityId=?, @ActorId=?", n_, SYSTEM_ACTOR)
    cur.execute("EXEC party.Entity_SoftDelete @EntityId=?, @ActorId=?", org5, SYSTEM_ACTOR)
    cur.execute("EXEC ref.AssetType_Deactivate @AssetTypeCode=?, @ActorId=?", W5L, SYSTEM_ACTOR)

    # ================================================================ wave 7 platform: PLATFORM-ARCHITECTURE §5.2 lightning landing and correlation, §8.1 the platform's own evidence
    W7 = "smoke_w7_" + uuid.uuid4().hex[:6]
    # A random station per run, so that neither an earlier run's strikes nor the feed's land inside this
    # run's 5 km radius. Ocean, far from anywhere the mimic or the client will ever put a real one.
    LAT7 = round(random.uniform(-58.0, -32.0), 4)
    LON7 = round(random.uniform(-140.0, -95.0), 4)
    ev7 = evaluate    # `ev` was rebound to a query result by the wave above
    # the platform's own release and deployment (PROCEDURES.md #42)
    # These two rows say which release this database is running — the answer /health gives and the fact
    # vision §9.9 asks of an incident ("what were you running on that date").
    #
    # This check used to invent a release inside a transaction, read the facts back, and roll the
    # transaction back so the database kept the truth it had. That worked while the evaluator was a
    # function on this very connection, which could see its own uncommitted rows. It cannot work now:
    # the engine is a separate process on a separate connection, and reading a row another connection
    # has written but not committed blocks until that transaction ends — which, here, is after the read.
    # The smoke waited the full 600 seconds and gave up.
    #
    # That is not a defect to work around. The engine reads committed truth, which is what an engine
    # deciding compliance should do. So the facts are asserted against the deployment record the
    # database actually holds, and the invented release is kept only for the uniqueness check, which
    # needs no evaluator.
    truth = q("""SELECT TOP (1) r.Version, r.ReleaseId FROM platform.vDeployment d JOIN platform.vRelease r ON r.ReleaseId = d.ReleaseId
                 WHERE d.DatabaseName = DB_NAME() AND d.Outcome = N'Succeeded' ORDER BY d.DeployedAt DESC""")
    before, relid_true = (truth[0][0], truth[0][1]) if truth else (None, None)
    # V2 W0: on a fresh database (deploy.py --fresh) no deployment has succeeded yet, and the engine's honest answer
    # for both facts is Unknown — which is what is asserted then. The record is written after this smoke passes.
    if truth:
        check(ev7("platform.release", None) == {"k": "text", "v": before} and ev7("platform.baseline", None).get("id") == str(relid_true),
              f"facts platform.release / platform.baseline read the latest succeeded deployment to this database ({ev7('platform.release', None)})")
    else:
        check(ev7("platform.release", None).get("k") == "unk" and ev7("platform.baseline", None).get("k") == "unk",
              f"facts platform.release / platform.baseline are Unknown on a database with no succeeded deployment ({ev7('platform.release', None)})")
    relv = W7 + ".0.0"
    cur.execute("BEGIN TRANSACTION")
    try:
        relid = q("DECLARE @id BIGINT, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC platform.Release_Append @Version=?, @ReleasedAt=@t, @DacpacHash=?, @RecordedByActorId=?, @ReleaseId=@id OUTPUT; SELECT @id", relv, bytes(32), SYSTEM_ACTOR)[0][0]
        check(expect_error(cur, "DECLARE @id BIGINT, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC platform.Release_Append @Version=?, @ReleasedAt=@t, @DacpacHash=?, @RecordedByActorId=?, @ReleaseId=@id OUTPUT", relv, bytes(32), SYSTEM_ACTOR, contains="UQ_Release_Version"), "a release version is recorded once")
    finally:
        cur.execute("IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION")
    after = q("SELECT TOP (1) r.Version FROM platform.vDeployment d JOIN platform.vRelease r ON r.ReleaseId = d.ReleaseId WHERE d.DatabaseName = DB_NAME() AND d.Outcome = N'Succeeded' ORDER BY d.DeployedAt DESC")
    after = after[0][0] if after else None
    check(after == before, f"the smoke leaves the deployed release untouched: /health and platform.release still answer {before!r}")
    # a deployment checklist record with the platform as subject (no entity id)
    tplv = q("SELECT TOP (1) dv.RowId FROM config.vDefinitionVersion dv JOIN config.vDefinition d ON d.EntityId = dv.DefinitionEntityId WHERE d.DefinitionKey = N'PlatformDeployment' AND dv.Status = N'Effective'")
    check(bool(tplv), "the PlatformDeployment record template is seeded and effective")
    prec = q("DECLARE @e UNIQUEIDENTIFIER, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC record.Record_Add @RecordKindCode=N'PlatformDeployment', @SubjectKind=N'Platform', @SubjectEntityId=NULL, @OccurredAt=@t, @PerformedByActorId=?, @OverallResult=N'Pass', @TemplateDefinitionVersionRowId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", SYSTEM_ACTOR, tplv[0][0] if tplv else None, SYSTEM_ACTOR)[0][0]
    check(prec is not None and q("SELECT SubjectKind, SubjectEntityId FROM record.vRecord WHERE EntityId = ?", prec)[0][1] is None, "a record may take the platform itself as its subject (PLATFORM-ARCHITECTURE §8.1)")
    check(expect_error(cur, "DECLARE @e UNIQUEIDENTIFIER, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC record.Record_Add @RecordKindCode=N'PlatformDeployment', @SubjectKind=N'Asset', @SubjectEntityId=NULL, @OccurredAt=@t, @PerformedByActorId=?, @ActorId=?, @EntityId=@e OUTPUT", SYSTEM_ACTOR, SYSTEM_ACTOR, contains="CK_Record_Subject"), "any other subject kind still needs an entity id")
    # a platform host as an asset with a declared service (the boundary-flow register as data)
    org7 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC party.Entity_Add @Name=?, @EntityKind=N'Utility', @IsOwnerOrganisation=1, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W7 + " utility", SYSTEM_ACTOR)[0][0]
    host7 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC asset.Asset_Add @AssetTypeCode=N'PlatformHost', @Name=?, @Status=N'InService', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W7 + " app server", SYSTEM_ACTOR)[0][0]
    hp = q("DECLARE @e UNIQUEIDENTIFIER; EXEC connection.Port_Add @AssetEntityId=?, @PortDesignator=N'NIC1', @PortKindCode=N'Ethernet', @Direction=N'Bidirectional', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", host7, SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC connection.NetworkPort_Add @EntityId=?, @IpAddress=N'10.10.70.30', @ActorId=?", hp, SYSTEM_ACTOR)
    cur.execute("EXEC connection.PortService_Add @NetworkPortEntityId=?, @Protocol=N'HTTPS', @LogicalPort=443, @ServiceName=N'PnC API and PWA (F1)', @Direction=N'In', @BusinessJustification=N'PLATFORM-ARCHITECTURE §1.2 F1', @IsInsideSecurityPerimeter=1, @ActorId=?", hp, SYSTEM_ACTOR)
    check(ev7("count(network.services[protocol='HTTPS'])", host7) == {"k": "num", "v": "1"}, "the platform's own service is read through the same fact as a relay's (PLATFORM-ARCHITECTURE §8.1)")
    # lightning: a located station, a placed asset, an operation, two strikes near and far (PROCEDURES.md #43)
    reg7 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC location.AddNode @NodeTypeCode=N'Region', @Name=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W7 + " region", SYSTEM_ACTOR)[0][0]
    st7 = q("DECLARE @e UNIQUEIDENTIFIER, @g GEOGRAPHY = geography::Point(?, ?, 4326); EXEC location.AddNode @NodeTypeCode=N'Station', @ParentEntityId=?, @Name=?, @SubtypeCode=N'Terminal', @Location=@g, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", LAT7, LON7, reg7, W7 + " station", SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC ref.AssetType_Upsert @AssetTypeCode=?, @Name=N'smoke w7 primary', @AssetClassCode=N'Primary', @IsDevice=0, @ActorId=?", W7, SYSTEM_ACTOR)
    xf7 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC asset.Asset_Add @AssetTypeCode=?, @Name=?, @Status=N'InService', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W7, W7 + " transformer", SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC asset.PlaceAsset @AssetEntityId=?, @NodeEntityId=?, @PlacementKind=N'Attached', @ActorId=?", xf7, st7, SYSTEM_ACTOR)
    frun = q("DECLARE @r UNIQUEIDENTIFIER, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC migration.Run_Append @SourceSystem=N'Lightning.Blitzortung', @SourceCaptureAt=@t, @StartedAt=@t, @RunByActorId=?, @RunId=@r OUTPUT; SELECT @r", SYSTEM_ACTOR)[0][0]
    opat = q("SELECT SYSDATETIMEOFFSET()")[0][0]
    op7 = q("DECLARE @e UNIQUEIDENTIFIER, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC scheme.RaiseProtectionOperation @OccurredAt=@t, @TimeSourceQuality=1, @PrimaryAssetEntityId=?, @Outcome=N'Correct', @DataSource=N'Scada', @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", xf7, SYSTEM_ACTOR)[0][0]
    near = (LAT7 + 0.005, LON7 - 0.005)   # ~0.7 km from the station
    far = (LAT7 + 1.8, LON7 + 1.6)        # ~200 km: outside 5 km, inside 500 km
    # what the database already believes, before this run's two strikes: the facts aggregate over every
    # strike there is, so only the change these two make is this smoke's to assert (a QA database holds
    # strikes from the feed and from earlier runs).
    base5 = int(ev7("operation.lightning_count[km=5, minutes=30]", op7)["v"])
    base500 = int(ev7("operation.lightning_count[km=500, minutes=30]", op7)["v"])
    base0 = int(ev7("operation.lightning_count[km=500, minutes=1]", op7)["v"])
    strike_ids = []
    for i, (lat, lon) in enumerate((near, far), 1):
        strike_ids.append(q("DECLARE @id BIGINT, @g GEOGRAPHY = geography::Point(?, ?, 4326), @t DATETIMEOFFSET(7) = DATEADD(MINUTE, -3, SYSDATETIMEOFFSET()); EXEC event.LightningStrike_Append @SourceSystem=N'Lightning.Blitzortung', @SourceStrikeId=?, @OccurredAt=@t, @TimeSourceQuality=2, @Location=@g, @AmplitudeKa=12.5, @StationCount=8, @FeedRunId=?, @StrikeId=@id OUTPUT; SELECT @id", lat, lon, W7 + "-" + str(i), frun)[0][0])
    near_id, far_id = strike_ids
    check(expect_error(cur, "DECLARE @id BIGINT, @g GEOGRAPHY = geography::Point(45.0, -66.0, 4326), @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC event.LightningStrike_Append @SourceSystem=N'Lightning.Blitzortung', @SourceStrikeId=?, @OccurredAt=@t, @TimeSourceQuality=2, @Location=@g, @FeedRunId=?, @StrikeId=@id OUTPUT", W7 + "-1", frun, contains="UQ_LightningStrike_Source"),
          "the lightning landing refuses a strike already landed from the same source (idempotent feed, §5.1)")
    n5 = int(ev7("operation.lightning_count[km=5, minutes=30]", op7)["v"]) - base5
    n500 = int(ev7("operation.lightning_count[km=500, minutes=30]", op7)["v"]) - base500
    n0 = int(ev7("operation.lightning_count[km=500, minutes=1]", op7)["v"]) - base0
    check(n5 == 1 and n500 == 2 and n0 == 0, f"operation.lightning_count[km, minutes] correlates strikes to the operation's place and window (+{n5} within 5 km, +{n500} within 500 km, +{n0} in the 1-minute window)")
    rn = ev7("operation.lightning_nearby[km=5, minutes=30]", op7)
    ids = {x.get("id") for x in rn.get("v", []) if x.get("kind") == "LightningStrike"}
    check(rn.get("k") == "set" and str(near_id) in ids and str(far_id) not in ids, f"operation.lightning_nearby[km, minutes] lists the near strike and not the far one (near {near_id} listed: {str(near_id) in ids}; far {far_id} listed: {str(far_id) not in ids}; {len(ids)} in the set)")
    check(ev7("operation.lightning_count[km=5, minutes=30]", str(uuid.uuid4())).get("k") == "unk", "operation.lightning_count on an unknown operation is Unknown")
    # ---- security.fHasPermission (PLATFORM-ARCHITECTURE §2.4, decision 237): the access decision as one function
    hp = lambda user, perm, kind, subj: q("SELECT security.fHasPermission(?, ?, ?, ?, SYSDATETIMEOFFSET())", user, perm, kind, subj)[0][0]
    per7 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC personnel.Person_Add @FirstName=N'Smoke', @LastName=N'Seven', @DisplayName=?, @EmployerEntityEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W7 + " person", org7, SYSTEM_ACTOR)[0][0]
    usr7 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC security.User_Add @PersonEntityId=?, @UserPrincipalName=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", per7, W7 + "@smoke.local", SYSTEM_ACTOR)[0][0]
    check(hp(usr7, "Asset.Read", "Asset", xf7) == False, "fHasPermission: deny by default (no grant)")
    check(q("SELECT COUNT(*) FROM security.vRolePermission WHERE RoleCode = N'Administrator'")[0][0] == q("SELECT COUNT(*) FROM security.vPermission WHERE IsActive = 1")[0][0]
          and q("SELECT COUNT(*) FROM security.vRolePermission WHERE RoleCode = N'ReadOnly' AND PermissionCode NOT LIKE N'%.Read'")[0][0] == 0, "seeded role permissions: Administrator holds every permission, ReadOnly only reads")
    # V2 W2: PCTechnician holds Asset.Read by seed (IDENTITY.md §3); the upsert is idempotent and the cleanup below
    # deactivates only what this smoke added, so a deploy's smoke never strips a seeded permission.
    had_tech_read = q("SELECT COUNT(*) FROM security.vRolePermission WHERE RoleCode = N'PCTechnician' AND PermissionCode = N'Asset.Read'")[0][0] == 1
    cur.execute("EXEC security.RolePermission_Upsert @RoleCode=N'PCTechnician', @PermissionCode=N'Asset.Read', @ActorId=?", SYSTEM_ACTOR)
    g7 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC security.Grant_Add @GranteeKind=N'User', @GranteeEntityId=?, @RoleCode=N'PCTechnician', @ScopeKind=N'NodeSubtree', @ScopeNodeEntityId=?, @GrantedByActorId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", usr7, reg7, SYSTEM_ACTOR, SYSTEM_ACTOR)[0][0]
    check(hp(usr7, "Asset.Read", "Asset", xf7) == True and hp(usr7, "Asset.Read", "Node", st7) == True, "fHasPermission: a NodeSubtree grant covers an asset placed under the node and the node itself")
    check(hp(usr7, "Asset.Read", "Asset", host7) == False and hp(usr7, "Asset.Modify", "Asset", xf7) == False, "fHasPermission: not an asset outside the subtree, not a verb the role lacks")
    g7c = q("DECLARE @e UNIQUEIDENTIFIER; EXEC security.Grant_Add @GranteeKind=N'User', @GranteeEntityId=?, @RoleCode=N'PCTechnician', @ScopeKind=N'NodeSubtree', @ScopeNodeEntityId=?, @ScopeAssetClassCode=N'Secondary', @GrantedByActorId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", usr7, reg7, SYSTEM_ACTOR, SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC security.Grant_Revise @EntityId=?, @GranteeKind=N'User', @GranteeEntityId=?, @RoleCode=N'PCTechnician', @ScopeKind=N'Global', @GrantedByActorId=?, @RevokedByActorId=?, @RevocationReason=N'smoke', @ActorId=?", g7, usr7, SYSTEM_ACTOR, SYSTEM_ACTOR, SYSTEM_ACTOR)
    check(hp(usr7, "Asset.Read", "Asset", xf7) == False, "fHasPermission: a revoked grant no longer counts; a class-filtered grant (Secondary) does not cover a Primary asset")
    grp7 = q("DECLARE @e UNIQUEIDENTIFIER; EXEC security.Group_Add @Name=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W7 + " group", SYSTEM_ACTOR)[0][0]
    cur.execute("EXEC security.GroupMember_Add @GroupEntityId=?, @UserEntityId=?, @ActorId=?", grp7, usr7, SYSTEM_ACTOR)
    g7g = q("DECLARE @e UNIQUEIDENTIFIER; EXEC security.Grant_Add @GranteeKind=N'Group', @GranteeEntityId=?, @RoleCode=N'ReadOnly', @ScopeKind=N'Global', @GrantedByActorId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", grp7, SYSTEM_ACTOR, SYSTEM_ACTOR)[0][0]
    check(hp(usr7, "Asset.Read", "Asset", host7) == True and hp(usr7, "Asset.Modify", "Asset", host7) == False, "fHasPermission: a Global grant to a group reaches its member (reads only for ReadOnly)")
    per7b = q("DECLARE @e UNIQUEIDENTIFIER; EXEC personnel.Person_Add @FirstName=N'Smoke', @LastName=N'Admin', @DisplayName=?, @EmployerEntityEntityId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", W7 + " admin", org7, SYSTEM_ACTOR)[0][0]
    d7 = q("DECLARE @e UNIQUEIDENTIFIER, @t DATETIMEOFFSET(7) = DATEADD(MINUTE, -1, SYSDATETIMEOFFSET()); EXEC security.Delegation_Add @FromPersonEntityId=?, @ToPersonEntityId=?, @RoleCode=N'Administrator', @StartsAt=@t, @GrantedByActorId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e", per7b, per7, SYSTEM_ACTOR, SYSTEM_ACTOR)[0][0]
    check(hp(usr7, "Definition.Administer", "Definition", None) == True, "fHasPermission: a delegation in force carries the positional role (Administrator) to the delegate")
    check(hp(str(uuid.uuid4()), "Asset.Read", "Asset", xf7) == False, "fHasPermission: an unknown user holds nothing")
    for g_ in (g7c, g7g):
        cur.execute("EXEC security.Grant_SoftDelete @EntityId=?, @ActorId=?", g_, SYSTEM_ACTOR)
    cur.execute("EXEC security.Delegation_SoftDelete @EntityId=?, @ActorId=?", d7, SYSTEM_ACTOR)
    cur.execute("EXEC security.GroupMember_SoftDelete @EntityId=?, @ActorId=?", q("SELECT EntityId FROM security.vGroupMember WHERE GroupEntityId = ?", grp7)[0][0], SYSTEM_ACTOR)
    cur.execute("EXEC security.Group_SoftDelete @EntityId=?, @ActorId=?", grp7, SYSTEM_ACTOR)
    cur.execute("EXEC security.User_SoftDelete @EntityId=?, @ActorId=?", usr7, SYSTEM_ACTOR)
    for pe_ in (per7, per7b):
        cur.execute("EXEC personnel.Person_SoftDelete @EntityId=?, @ActorId=?", pe_, SYSTEM_ACTOR)
    if not had_tech_read:
        cur.execute("EXEC security.RolePermission_Deactivate @RoleCode=N'PCTechnician', @PermissionCode=N'Asset.Read', @ActorId=?", SYSTEM_ACTOR)
    # cleanup (soft deletes; append-only rows stay, as designed)
    cur.execute("EXEC scheme.ProtectionOperation_SoftDelete @EntityId=?, @ActorId=?", op7, SYSTEM_ACTOR)
    cur.execute("EXEC record.Record_SoftDelete @EntityId=?, @ActorId=?", prec, SYSTEM_ACTOR)
    for a_ in (xf7, host7):
        cur.execute("EXEC asset.Asset_SoftDelete @EntityId=?, @ActorId=?", a_, SYSTEM_ACTOR)
    for n_ in (st7, reg7):
        cur.execute("EXEC location.Node_SoftDelete @EntityId=?, @ActorId=?", n_, SYSTEM_ACTOR)
    cur.execute("EXEC party.Entity_SoftDelete @EntityId=?, @ActorId=?", org7, SYSTEM_ACTOR)
    cur.execute("EXEC ref.AssetType_Deactivate @AssetTypeCode=?, @ActorId=?", W7, SYSTEM_ACTOR)

    # ================================================================ wave 6 grammar
    # Grammar conformance is no longer checked here. It existed to keep two implementations of the
    # grammar in step, and since 2026-09-10 there is one: src/PnC.Formula, whose own suite
    # (src/PnC.Formula.Conformance, 133 cases) is the net. The database interpreter it compared against
    # was dropped with the rest of the evaluator. What is still checked here is the fact catalogue the
    # engine reads through, which remains a database concern.
    cat2 = {r[0]: r for r in q("SELECT FactName, DataType, Parameters FROM compliance.vFactCatalogue WHERE FactName IN (N'scheme.members', N'record.last', N'record.occurred_at')")}
    check(len(cat2) == 3 and cat2["scheme.members"][2] == '["role"]', f"fact catalogue lists the parameterised facts with their parameters ({[(k, v[2]) for k, v in cat2.items()]})")

    # ---- privilege boundary: app_execute has no table SELECT
    tbl_grants = q("""SELECT COUNT(*) FROM sys.database_permissions p JOIN sys.database_principals r ON r.principal_id = p.grantee_principal_id
                      JOIN sys.objects o ON o.object_id = p.major_id WHERE r.name = 'app_execute' AND o.type = 'U' AND p.permission_name = 'SELECT'""")[0][0]
    check(tbl_grants == 0, "app_execute holds no SELECT on any table")
    view_grants = q("""SELECT COUNT(*) FROM sys.database_permissions p JOIN sys.database_principals r ON r.principal_id = p.grantee_principal_id
                       JOIN sys.objects o ON o.object_id = p.major_id WHERE r.name = 'app_execute' AND o.type = 'V' AND p.permission_name = 'SELECT'""")[0][0]
    nviews = q("SELECT COUNT(*) FROM sys.views v JOIN sys.schemas s ON s.schema_id = v.schema_id WHERE v.name LIKE 'v%'")[0][0]
    check(view_grants == nviews, f"app_execute has SELECT on every generated view ({view_grants}/{nviews})")

    # ---- cleanup: soft-delete the smoke definitions (never a hard delete)
    for kk in (key, k2, k3, k4, W4 + "_R1", W4 + "_R2", W4 + "_R3", W4 + "_wt"):
        de = q("SELECT EntityId FROM config.vDefinition WHERE DefinitionKey=?", kk)[0][0]
        cur.execute("EXEC config.Definition_SoftDelete @EntityId=?, @ActorId=?", de, SYSTEM_ACTOR)
        cur.execute("UPDATE config.DefinitionVersion SET IsDeleted=1, DeletedBy=?, DeletedAt=SYSDATETIMEOFFSET() WHERE DefinitionEntityId=(SELECT EntityId FROM config.Definition WHERE DefinitionKey=? AND IsDeleted=1)", SYSTEM_ACTOR, kk)
    print("SMOKE " + ("PASS" if not fails else f"FAIL ({len(fails)})"))
    sys.exit(0 if not fails else 1)


if __name__ == "__main__":
    main()
