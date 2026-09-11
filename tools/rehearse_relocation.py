"""
rehearse_relocation.py - the relocation checklist (PLATFORM-ARCHITECTURE section 1.4, decision 253) as a runnable.

Steps 3, 6 and 7 are performed; 1, 2, 4 and 5 are observed and reported with an explicit outcome, since they are
infrastructure acts (VMs, domain, firewall) this script cannot make. Every run writes:
  - a PlatformDeployment record through POST /api/v1/forms/record (the checklist outcome as characteristics, section 8)
  - dist/<version>/REHEARSAL-<date>.md, the table of steps and outcomes
Exit code 1 if any performed step fails.

Usage (DEV, everything from the build machine):
  python tools/rehearse_relocation.py --package dist/0.10.0 --api-url http://localhost:5200 --satellite-url http://localhost:5210
         --server 10.10.70.25 --database PnCPlatform_DEV --user smoke.admin@pnc.local
         [--expect-refused host:port]   # step 5: a Business-side connection into OT that must be refused

Usage (QA/PROD, decision 256 - the evidence comes from three vantage points, because the register allows nothing else):
  1. on the Application VM, as an Administrator and again as a ReadOnly user (the package's tools/PnC.Api.Smoke.exe):
        PnC.Api.Smoke.exe https://<application server>/ - - --windows=Administrator > smoke-admin.log
        PnC.Api.Smoke.exe https://<application server>/ - - --windows=ReadOnly       > smoke-readonly.log
  2. on the build machine (Business), which has the release package, the database path for the release row, and is the
     right place to prove the temporary rule is closed:
        python tools/rehearse_relocation.py --package dist/<version> --server <sql> --database PnCPlatform_QA
               --smoke-log smoke-admin.log --smoke-log smoke-readonly.log --expect-refused <application server>:443
     With --smoke-log and no --api-url the API is not called from here (there is no path, by design): steps 1, 2 and 6 are
     read from the logs' SMOKE header and outcome lines, and the step-7 record is written through the same procedures the
     forms endpoint uses (record.Record_Add + record.CharacteristicValue_Add), as the SYSTEM actor, from the build machine.
"""
import argparse, hashlib, json, os, socket, subprocess, sys, urllib.request, urllib.error

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOTNET = os.environ.get("DOTNET", r"C:\Program Files\dotnet\dotnet.exe" if os.name == "nt" else "dotnet")


def password():
    if os.environ.get("PNC_DEV_PWD"):
        return os.environ["PNC_DEV_PWD"]
    p = os.path.join(ROOT, "dev.local")
    if os.path.exists(p):
        for line in open(p, encoding="utf-8"):
            if line.startswith("PNC_DEV_PWD="):
                return line.split("=", 1)[1].strip()
    return None


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


class Api:
    def __init__(self, base, user):
        self.base, self.user = base.rstrip("/"), user

    def call(self, method, path, body=None, auth=True):
        req = urllib.request.Request(self.base + path, method=method, data=None if body is None else json.dumps(body).encode("utf-8"))
        req.add_header("Accept", "application/json")
        if body is not None:
            req.add_header("Content-Type", "application/json")
        if auth and self.user:
            req.add_header("X-PnC-Dev-User", self.user)
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.status, json.loads(r.read().decode("utf-8") or "null")
        except urllib.error.HTTPError as e:
            try:
                return e.code, json.loads(e.read().decode("utf-8") or "null")
            except ValueError:
                return e.code, None


class Run:
    def __init__(self):
        self.rows = []      # (step, title, outcome, detail)  outcome: pass | fail | not-applicable | observed
        self.failed = False

    def add(self, step, title, outcome, detail=""):
        self.rows.append((step, title, outcome, detail))
        if outcome == "fail":
            self.failed = True
        print(f"[{outcome:>14}] step {step}: {title}" + (f" - {detail}" if detail else ""))


def parse_smoke_log(path):
    """The smoke's output: a SMOKE header line (api, environment, release, mode, host, user, at), PASS/FAIL/SKIP lines, and the
    API SMOKE PASS/FAIL summary. Returns what the rehearsal needs from it."""
    head = {}; fails = []; feed = []; passed = False; summary = ""; health_ok = False
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.rstrip("\n")
        if line.startswith("SMOKE "):
            head = dict(kv.split("=", 1) for kv in line[6:].split(" ") if "=" in kv)
        elif line.startswith("FAIL "):
            fails.append(line[5:])
        elif line.startswith("PASS health:"):
            health_ok = True
        if line.startswith(("PASS feed:", "FAIL feed:", "SKIP feed:")):
            feed.append(line)
        if line.startswith("API SMOKE"):
            summary = line; passed = line.startswith("API SMOKE PASS")
    return {"path": path, "head": head, "fails": fails, "feed": feed, "passed": passed, "summary": summary or "no summary line", "health_ok": health_ok}


def record_via_sql(server, database, body):
    """The forms endpoint's write, from the build machine: record.Record_Add then one record.CharacteristicValue_Add per
    value, typed by the template's characteristic definitions, in one transaction, as the SYSTEM actor."""
    import pyodbc
    pwd = password()
    cs = (f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={server};DATABASE={database};" +
          (f"UID=dev_pnc;PWD={pwd};" if pwd else "Trusted_Connection=yes;") + "TrustServerCertificate=yes")
    con = pyodbc.connect(cs, autocommit=False, timeout=15)
    cur = con.cursor()
    system_actor = "00000000-0000-0000-0000-000000000001"
    kind = body["record"]["RecordKindCode"]
    ver = cur.execute("""SELECT TOP (1) v.RowId FROM config.vDefinitionVersion v
                         WHERE v.DefinitionEntityId = (SELECT TemplateDefinitionEntityId FROM ref.RecordKind WHERE RecordKindCode = ?)
                           AND v.Status = N'Effective' AND v.EffectiveTo IS NULL ORDER BY v.VersionNumber DESC""", kind).fetchone()
    if ver is None:
        raise RuntimeError(f"no effective template for record kind {kind}")
    defs = {r[0]: (r[1], r[2]) for r in cur.execute("SELECT CharacteristicKey, RowId, DataType FROM config.vCharacteristicDefinition WHERE DefinitionVersionRowId = ?", ver[0]).fetchall()}
    unknown = [k for k in body["values"] if k not in defs]
    if unknown:
        raise RuntimeError(f"unknown characteristics for {kind}: {unknown}")
    # @OccurredAt takes a variable, not a function call: T-SQL rejects EXEC p @x = SYSDATETIMEOFFSET().
    rec_id = cur.execute("""DECLARE @e UNIQUEIDENTIFIER, @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET();
                            EXEC record.Record_Add @RecordKindCode=?, @SubjectKind=?, @OccurredAt=@now, @PerformedByActorId=?, @Summary=?, @TemplateDefinitionVersionRowId=?, @ActorId=?, @EntityId=@e OUTPUT;
                            SELECT @e""", kind, body["record"]["SubjectKind"], system_actor, body["record"].get("Summary"), ver[0], system_actor).fetchval()
    for key, val in body["values"].items():
        row_id, dtype = defs[key]
        col = {"Integer": "@IntegerValue", "Decimal": "@DecimalValue", "Boolean": "@BooleanValue", "DateTime": "@DateTimeValue", "Reference": "@ReferenceEntityId"}.get(dtype, "@TextValue")
        if col == "@BooleanValue":
            val = 1 if val else 0
        elif col == "@TextValue":
            val = str(val)
        cur.execute(f"EXEC record.CharacteristicValue_Add @HostEntityId=?, @CharacteristicDefinitionRowId=?, {col}=?, @ActorId=?", str(rec_id), str(row_id), val, system_actor)
    con.commit(); con.close()
    return str(rec_id)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--package", required=True, help="dist/<version> from tools/package_release.py")
    ap.add_argument("--api-url", default=None, help="the API, when reachable from here (DEV); default http://localhost:5200 unless --smoke-log is given")
    ap.add_argument("--satellite-url", default="http://localhost:5210")
    ap.add_argument("--smoke-log", action="append", default=[], help="a PnC.Api.Smoke log produced on the Application VM (repeatable: one per role)")
    ap.add_argument("--server", default="10.10.70.25")
    ap.add_argument("--database", default="PnCPlatform_DEV")
    ap.add_argument("--user", default="smoke.admin@pnc.local", help="the DEV-mode principal (ignored under Windows authentication)")
    ap.add_argument("--expect-refused", default=None, help="host:port on OT that must refuse a connection from here (step 5)")
    ap.add_argument("--no-smoke", action="store_true")
    a = ap.parse_args()
    if a.api_url is None and not a.smoke_log:
        a.api_url = "http://localhost:5200"
    run = Run()
    api = Api(a.api_url, a.user) if a.api_url else None
    rel = json.load(open(os.path.join(a.package, "release.json"), encoding="utf-8"))
    version = rel["version"]
    logs = [parse_smoke_log(p) for p in a.smoke_log]
    print(f"relocation rehearsal for release {version} against {a.api_url or 'the smoke logs'} / {a.database}")

    # ---- steps 1–2: the VMs, the domain, the service account - observed through the API's identity mode
    env = None; health = None; st_h = None
    if api:
        st, me = api.call("GET", "/api/v1/me")
        st_h, health = api.call("GET", "/health", auth=False)
        env = (health or {}).get("environment")
        if st == 200 and me:
            mode = "Development header" if a.user and env == "DEV" else "Windows"
            run.add(1, "OT VMs joined to the OT domain", "observed" if env != "DEV" else "not-applicable",
                    f"environment {env}; API host {a.api_url}; signed in as {me.get('userPrincipalName')} via {mode}")
            run.add(2, "Service account holds app_execute; users by domain account", "observed" if mode == "Windows" else "not-applicable",
                    "Development mode is not a rehearsal of step 2" if mode != "Windows" else "Windows identity in use")
        else:
            run.add(1, "OT VMs joined to the OT domain", "fail", f"/api/v1/me -> {st}")
            run.add(2, "Service account", "fail", "no identity")
    else:
        heads = [l["head"] for l in logs if l["head"]]
        if heads:
            h = heads[0]; env = h.get("environment")
            windows_runs = [x for x in heads if x.get("mode", "").startswith("Windows/")]
            st_h, health = 200, {"environment": env, "release": h.get("release"), "database": "ok" if all(l["health_ok"] for l in logs) else "not ok", "feeds": []}
            run.add(1, "OT VMs joined to the OT domain", "observed" if windows_runs else "fail",
                    "; ".join(f"{x.get('host')} as {x.get('user')} ({x.get('mode')}) against {x.get('api')} at {x.get('at')}" for x in heads))
            roles = sorted({x["mode"].split("/", 1)[1] for x in windows_runs})
            run.add(2, "Service account holds app_execute; users by domain account", "observed" if roles else "fail",
                    f"Windows identities signed in with roles {roles}" if roles else "no Windows-mode run in the logs")
        else:
            run.add(1, "OT VMs joined to the OT domain", "fail", "no SMOKE header in the logs")
            run.add(2, "Service account", "fail", "no SMOKE header in the logs")

    # ---- step 3: the release package installed
    problems = []
    for key, fname in (("dacpac", rel["artifacts"]["dacpac"]["file"]), ("package", rel["artifacts"]["package"]["file"])):
        p = os.path.join(a.package, fname)
        if not os.path.exists(p):
            problems.append(f"{fname} missing")
        elif sha256(p) != rel["artifacts"][key]["sha256"]:
            problems.append(f"{fname} hash differs from release.json")
    if os.path.exists(os.path.join(a.package, "app", "appsettings.Local.json")):
        problems.append("appsettings.Local.json inside the package")
    if st_h == 200 and health:
        if health.get("release") != version:
            problems.append(f"/health reports release {health.get('release')}, package is {version}")
        if health.get("database") != "ok":
            problems.append(f"database {health.get('database')}")
    else:
        problems.append(f"/health -> {st_h}")
    # the release row and its hashes
    db_note = ""
    try:
        import pyodbc
        pwd = password()
        cs = (f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={a.server};DATABASE={a.database};" +
              (f"UID=dev_pnc;PWD={pwd};" if pwd else "Trusted_Connection=yes;") + "TrustServerCertificate=yes")
        con = pyodbc.connect(cs, autocommit=True, timeout=15)
        row = con.execute("SELECT DacpacHash, PackageHash FROM platform.vRelease WHERE Version = ?", version).fetchone()
        if row is None:
            problems.append(f"no platform.Release row for {version}")
        else:
            if bytes(row[0]).hex() != rel["artifacts"]["dacpac"]["sha256"]:
                problems.append("platform.Release.DacpacHash differs from the package's DACPAC")
            if row[1] is None:
                db_note = "release row carries no PackageHash (recorded before the package; deploy.py --package sets it)"
            elif bytes(row[1]).hex() != rel["artifacts"]["package"]["sha256"]:
                problems.append("platform.Release.PackageHash differs from the package zip")
        con.close()
    except Exception as e:   # noqa: BLE001 - reported, not fatal: the database check is one of several
        db_note = f"release row not checked: {type(e).__name__}: {e}"
    run.add(3, "Release package installed (hashes, /health release, no developer configuration)", "fail" if problems else "pass", "; ".join(problems + ([db_note] if db_note else [])))

    # ---- steps 4–5: the firewall from the register; the temporary rule closed
    run.add(4, "Firewall configured from the register (Phase 1 flows only)", "not-applicable", "an infrastructure act; the register is docs/PLATFORM-ARCHITECTURE.md section 1.2")
    if a.expect_refused:
        host, port = a.expect_refused.rsplit(":", 1)
        try:
            with socket.create_connection((host, int(port)), timeout=5):
                run.add(5, "Temporary Business -> OT rule closed", "fail", f"{a.expect_refused} accepted a connection from this host")
                refused = False
        except OSError as e:
            run.add(5, "Temporary Business -> OT rule closed", "pass", f"{a.expect_refused} refused: {type(e).__name__}")
            refused = True
    else:
        run.add(5, "Temporary Business -> OT rule closed", "not-applicable", "no --expect-refused given (on DEV the rule is open by design)")
        refused = None

    # ---- step 6: the journey smoke and a feed pull
    feed_ok = False
    if a.no_smoke:
        run.add(6, "User-journey smoke", "not-applicable", "--no-smoke")
    elif logs:
        for l in logs:
            run.add(6, f"User-journey smoke ({l['head'].get('mode', '?') if l['head'] else '?'} on {l['head'].get('host', '?') if l['head'] else '?'})",
                    "pass" if l["passed"] else "fail", l["summary"] + (f"; FAIL lines: {' | '.join(l['fails'][:3])}" if l["fails"] else ""))
        feed_lines = [x for l in logs for x in l["feed"]]
        feed_ok = bool(feed_lines) and all(x.startswith("PASS") for x in feed_lines)
        run.add(6, "Feed pull (F3) completes", "pass" if feed_ok else "fail", "; ".join(x[5:] for x in feed_lines)[:400] or "no feed line in the logs")
    else:
        pwd = password()
        cs = f"Server={a.server};Database={a.database};" + (f"User ID=dev_pnc;Password={pwd};" if pwd else "Integrated Security=true;") + "TrustServerCertificate=true;Encrypt=true"
        r = subprocess.run([DOTNET, "run", "--no-build", "--project", os.path.join(ROOT, "src", "PnC.Api.Smoke", "PnC.Api.Smoke.csproj"), "--", a.api_url, a.satellite_url, cs],
                           cwd=ROOT, text=True, capture_output=True)
        last = [l for l in r.stdout.splitlines() if l.startswith("API SMOKE")]
        run.add(6, "User-journey smoke", "pass" if r.returncode == 0 else "fail", (last[-1] if last else r.stdout[-300:] + r.stderr[-300:]).strip())
    if api:
        st_h, health = api.call("GET", "/health", auth=False)
        feeds = (health or {}).get("feeds") or []
        if feeds:
            f = feeds[0]
            feed_ok = f.get("lastGoodPull") is not None and (f.get("ageSeconds") or 10**9) < 600
            run.add(6, "Feed pull (F3) completes", "pass" if feed_ok else "fail", f"{f.get('name')}: age {f.get('ageSeconds')} s, landed {f.get('landed')}, error {f.get('lastError')}")
        else:
            run.add(6, "Feed pull (F3) completes", "fail", "no feed configured")

    # ---- step 7: the record and the report
    reached = 7 if not run.failed else max([s for s, _, o, _ in run.rows if o == "pass"] + [0])
    notes = "; ".join(f"step {s} {o}: {d}" for s, _, o, d in run.rows if d)[:4000]
    body = {"record": {"RecordKindCode": "PlatformDeployment", "SubjectKind": "Platform", "Summary": f"relocation rehearsal of {version} on {env} ({'pass' if not run.failed else 'FAIL'})"},
            "values": {"environment": env or "?", "release_version": version, "checklist_step": reached,
                       "temporary_rule_closed": bool(refused) if refused is not None else False,
                       "feed_pull_ok": bool(feed_ok), "inbound_refused": bool(refused) if refused is not None else False, "notes": notes[:400]}}
    rec_id = None
    if api:
        st, rec = api.call("POST", "/api/v1/forms/record", body)
        rec_id = (rec or {}).get("record", {}).get("EntityId") if st == 200 else None
        run.add(7, "Run recorded as a PlatformDeployment record", "pass" if rec_id else "fail", rec_id or f"{st} {rec}")
    else:
        try:
            rec_id = record_via_sql(a.server, a.database, body)
            run.add(7, "Run recorded as a PlatformDeployment record", "pass", f"{rec_id} (written from the build machine through record.Record_Add / CharacteristicValue_Add as the SYSTEM actor: no API path from Business, by the register)")
        except Exception as e:   # noqa: BLE001 - the outcome is the report
            run.add(7, "Run recorded as a PlatformDeployment record", "fail", f"{type(e).__name__}: {e}")

    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H%M%SZ")
    report = os.path.join(a.package, f"REHEARSAL-{stamp}.md")
    with open(report, "w", encoding="utf-8") as f:
        f.write(f"# Relocation rehearsal - release {version}\n\n{datetime.now(timezone.utc).isoformat()} · API {a.api_url or 'from the smoke logs: ' + ', '.join(a.smoke_log)} · database {a.database} · environment {env}\n\n")
        f.write("| Step | Item | Outcome | Detail |\n|---|---|---|---|\n")
        for s, t, o, d in run.rows:
            f.write(f"| {s} | {t} | {o} | {d.replace('|', '/')} |\n")
        f.write(f"\nRecord: `{rec_id}` (PlatformDeployment, subject Platform). Result: **{'PASS' if not run.failed else 'FAIL'}**.\n")
        f.write("\nSteps marked not-applicable are infrastructure acts (section 1.4 items 1, 2, 4, 5) that a QA run on the OT mimic must perform by hand and re-run this script against.\n")
    print(f"report: {report}")
    print("REHEARSAL " + ("PASS" if not run.failed else "FAIL"))
    return 0 if not run.failed else 1


if __name__ == "__main__":
    sys.exit(main())
