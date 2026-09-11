"""
Extensibility gate harness (SCHEMA-DESIGN §2.6, decision 77).

Runs the gate scripts against SQL Server in order, asserts the expected subject sets, and
proves objectively that step 4 changed no table, view, function or procedure: a snapshot of
every user object (name, type, column list, SHA-256 of the module definition) is taken before
30-extend.sql and after 40-preview-r2.sql and the two must be identical.

Usage:
    python docs/schema/gate/run_gate.py [--server 10.10.70.25] [--database PnCPlatform_GATE] [--keep]

The password is read from dev.local (PNC_DEV_PWD=...) at the repository root, or from the
PNC_DEV_PWD environment variable. The database is dropped and recreated on every run unless
--keep is given, in which case it must not exist.
"""
import argparse, datetime, hashlib, os, re, sys
import pyodbc

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
APPROVER = "22222222-2222-2222-2222-222222222222"
EXPECTED_R1 = ["T1", "T2", "T4", "T6"]
EXPECTED_R2 = ["T1", "T4"]
DDL_TOKEN = re.compile(r"^\s*(CREATE|ALTER|DROP)\s", re.IGNORECASE | re.MULTILINE)

SNAPSHOT_SQL = """
SELECT s.name + N'.' + o.name AS obj, o.type_desc,
       CONVERT(NVARCHAR(64), HASHBYTES('SHA2_256', ISNULL(m.definition, N'')), 2) AS defhash,
       ISNULL((SELECT STRING_AGG(c.name + N':' + t.name + N':' + CONVERT(NVARCHAR(10), c.max_length)
                                 + N':' + CONVERT(NVARCHAR(10), c.precision) + N':' + CONVERT(NVARCHAR(10), c.scale), N',')
                       WITHIN GROUP (ORDER BY c.column_id)
               FROM sys.columns c JOIN sys.types t ON t.user_type_id = c.user_type_id
               WHERE c.object_id = o.object_id), N'') AS cols,
       ISNULL((SELECT STRING_AGG(i.name + N':' + CONVERT(NVARCHAR(10), i.type) + N':' + ISNULL(i.filter_definition, N''), N',')
                       WITHIN GROUP (ORDER BY i.index_id)
               FROM sys.indexes i WHERE i.object_id = o.object_id AND i.name IS NOT NULL), N'') AS idx
FROM sys.objects o JOIN sys.schemas s ON s.schema_id = o.schema_id
LEFT JOIN sys.sql_modules m ON m.object_id = o.object_id
WHERE o.is_ms_shipped = 0 AND o.type NOT IN ('IT', 'SQ')
ORDER BY obj, o.type_desc;
"""


def password():
    if os.environ.get("PNC_DEV_PWD"):
        return os.environ["PNC_DEV_PWD"]
    p = os.path.join(ROOT, "dev.local")
    if os.path.exists(p):
        for line in open(p, encoding="utf-8"):
            if line.startswith("PNC_DEV_PWD="):
                return line.split("=", 1)[1].strip()
    sys.exit("No password: set PNC_DEV_PWD or put PNC_DEV_PWD=... in dev.local")


def connect(server, database, pwd):
    return pyodbc.connect(
        f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={server};DATABASE={database};"
        f"UID=dev_pnc;PWD={pwd};TrustServerCertificate=yes", autocommit=True, timeout=15)


def batches(path):
    text = open(path, encoding="utf-8").read()
    return [b.strip() for b in re.split(r"^\s*GO\s*$", text, flags=re.IGNORECASE | re.MULTILINE) if b.strip()]


def run_file(cur, path):
    rows = None
    for b in batches(path):
        cur.execute(b)
        try:
            if cur.description:
                rows = cur.fetchall()
        except pyodbc.ProgrammingError:
            pass
    return rows


def snapshot(cur):
    return [tuple(r) for r in cur.execute(SNAPSHOT_SQL).fetchall()]


def snapshot_digest(rows):
    h = hashlib.sha256()
    for r in rows:
        h.update(("|".join(str(x) for x in r) + "\n").encode("utf-8"))
    return h.hexdigest()


def catalogue(cur):
    return cur.execute("SELECT FactName, FactSource, DataType, UnitCode FROM compliance.vFactCatalogue ORDER BY FactName").fetchall()


def fact_table(cur, facts):
    names = [r[0] for r in cur.execute("SELECT Name FROM asset.vAsset ORDER BY Name").fetchall()]
    out = []
    for n in names:
        vals = []
        for f in facts:
            v = cur.execute("SELECT compliance.fFactValue(a.EntityId, ?, SYSDATETIMEOFFSET()) FROM asset.vAsset a WHERE a.Name = ?", f, n).fetchone()[0]
            vals.append("" if v is None else str(v))
        out.append((n, vals))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default="10.10.70.25")
    ap.add_argument("--database", default="PnCPlatform_GATE")
    ap.add_argument("--keep", action="store_true", help="do not drop an existing database (it must not exist)")
    a = ap.parse_args()
    pwd = password()
    log, failures = [], []

    def check(cond, msg):
        log.append(("PASS " if cond else "FAIL ") + msg)
        if not cond:
            failures.append(msg)

    master = connect(a.server, "master", pwd)
    mc = master.cursor()
    version = mc.execute("SELECT @@VERSION").fetchone()[0].splitlines()[0].strip()
    exists = mc.execute("SELECT COUNT(*) FROM sys.databases WHERE name = ?", a.database).fetchone()[0]
    if exists and a.keep:
        sys.exit(f"{a.database} exists and --keep given")
    if exists:
        mc.execute(f"ALTER DATABASE [{a.database}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE")
        mc.execute(f"DROP DATABASE [{a.database}]")
    mc.execute(f"CREATE DATABASE [{a.database}]")
    master.close()

    db = connect(a.server, a.database, pwd)
    cur = db.cursor()
    started = datetime.datetime.now().astimezone()

    run_file(cur, os.path.join(HERE, "00-schema.sql"))
    run_file(cur, os.path.join(HERE, "10-seed.sql"))
    cat_before = catalogue(cur)
    check([r[0] for r in cat_before] == ["asset.formula.is_microprocessor", "asset.template.technology"],
          "catalogue after step 2 lists exactly the v1 characteristic and the formula")

    r1 = run_file(cur, os.path.join(HERE, "20-preview-r1.sql"))
    r1_names = [r.SubjectName for r in (r1 or [])]
    check(r1_names == EXPECTED_R1, f"R1 preview scopes {EXPECTED_R1}; got {r1_names}")
    runs_after_r1 = cur.execute("SELECT COUNT(*) FROM compliance.RuleEvaluationRun WHERE Mode = N'Preview'").fetchone()[0]
    check(runs_after_r1 == 1, "R1 preview wrote exactly one RuleEvaluationRun row")

    # negative check: a rule naming an uncatalogued fact must be refused at authoring time
    refused = False
    try:
        cur.execute("EXEC config.AddDefinition N'Program.ObligationRule', N'RX', N'bad rule', NULL, ?", APPROVER)
        cur.execute("EXEC config.AddDefinitionVersion N'RX', N'v1', "
                    "N'{\"subjectKinds\":[\"Asset\"],\"predicate\":{\"fact\":\"asset.template.nonexistent\",\"op\":\"=\",\"value\":1}}', ?", APPROVER)
    except pyodbc.Error as e:
        refused = "not in the catalogue" in str(e)
        refusal_text = str(e)
    check(refused, "interpreter refuses a rule naming a fact absent from the catalogue")

    # ---- step 4: rows only ---------------------------------------------------------
    extend_path = os.path.join(HERE, "30-extend.sql")
    check(not DDL_TOKEN.search(open(extend_path, encoding="utf-8").read()), "30-extend.sql contains no CREATE/ALTER/DROP")
    snap_before = snapshot(cur)
    run_file(cur, extend_path)
    cat_after = catalogue(cur)
    check([r[0] for r in cat_after] == ["asset.formula.is_microprocessor", "asset.template.technology", "asset.template.voltage_class_kv"],
          "catalogue after step 4 lists the new characteristic with no other change")

    # ---- step 5 --------------------------------------------------------------------
    r2 = run_file(cur, os.path.join(HERE, "40-preview-r2.sql"))
    r2_names = [r.SubjectName for r in (r2 or [])]
    check(r2_names == EXPECTED_R2, f"R2 preview scopes {EXPECTED_R2}; got {r2_names}")
    snap_after = snapshot(cur)
    same = snap_before == snap_after
    check(same, "object snapshot identical before step 4 and after step 5 (no table/view/function/procedure changed)")
    diff = []
    if not same:
        b, c = {r[0] + r[1]: r for r in snap_before}, {r[0] + r[1]: r for r in snap_after}
        for k in sorted(set(b) | set(c)):
            if b.get(k) != c.get(k):
                diff.append(k)

    # R1 still scopes the same after the template revision (values carried across versions)
    r1b = cur.execute("EXEC compliance.RunRulePreview N'R1', ?", APPROVER).fetchall()
    check([r.SubjectName for r in r1b] == EXPECTED_R1, "R1 re-run after step 4 still scopes the same subjects")

    facts = [r[0] for r in cat_after]
    table = fact_table(cur, facts)
    db.close()

    verdict = "PASS" if not failures else "FAIL"
    lines = [
        f"# Extensibility gate result — {verdict}", "",
        f"Run {started.isoformat(timespec='seconds')} against `{a.server}` / `{a.database}`  ",
        f"Server: {version}  ", f"Harness: `docs/schema/gate/run_gate.py`", "",
        "SCHEMA-DESIGN §2.6, decision 77. Toy data; nothing here describes a real installation.", "",
        "## Checks", "", *[f"- {l}" for l in log], "",
        "## Fact catalogue", "",
        "Before step 4:", "", "| FactName | Source | DataType | Unit |", "|---|---|---|---|",
        *[f"| `{r[0]}` | {r[1]} | {r[2]} | {r[3] or ''} |" for r in cat_before], "",
        "After step 4:", "", "| FactName | Source | DataType | Unit |", "|---|---|---|---|",
        *[f"| `{r[0]}` | {r[1]} | {r[2]} | {r[3] or ''} |" for r in cat_after], "",
        "## Fact values after step 4 (via `compliance.fFactValue`)", "",
        "| Asset | " + " | ".join(f"`{f}`" for f in facts) + " |", "|---|" + "---|" * len(facts),
        *[f"| {n} | " + " | ".join(v) + " |" for n, v in table], "",
        "## Scoped subjects", "",
        f"- R1 (step 3): {', '.join(r1_names)}", f"- R2 (step 5): {', '.join(r2_names)}", "",
        "## Object snapshot", "",
        f"- Objects compared: {len(snap_before)} before, {len(snap_after)} after",
        f"- Digest before step 4: `{snapshot_digest(snap_before)}`",
        f"- Digest after step 5:  `{snapshot_digest(snap_after)}`",
        f"- Identical: **{'yes' if same else 'NO'}**",
    ]
    if diff:
        lines += ["", "Objects that differ:", *[f"- {d}" for d in diff]]
    if not refused:
        lines += ["", "Negative check did not raise the expected error."]
    lines.append("")
    open(os.path.join(HERE, "RESULT.md"), "w", encoding="utf-8").write("\n".join(lines))
    print("\n".join(log))
    print(verdict)
    sys.exit(0 if not failures else 1)


if __name__ == "__main__":
    main()
