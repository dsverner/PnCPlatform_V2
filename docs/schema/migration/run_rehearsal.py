"""
Rehearsal orchestrator (vision §10.7: rehearse against the old capture until it runs clean).

    python docs/schema/migration/run_rehearsal.py [--database PnCPlatform_V2_DEV] [--limit N] [--no-rerun] [--report REHEARSAL-<date>-<env>.md]

Carried from the predecessor in W7 (decision #137) with one loader: legacy_import.py (CUTOVER-STRATEGY §5). Runs it, then
runs it a second time to prove idempotence (expected: 0 rows written), checks that every migrated row has provenance and
that no loader writes outside a procedure, and writes the rehearsal report.
"""
import argparse, datetime, json, os, re, subprocess, sys, time
from common import connect, HERE

LOADERS = [("legacy", "legacy_import")]
TARGETS = ["location.Node", "location.NodeFunction", "location.AlternateKey", "asset.Asset", "device.Device", "asset.Placement", "asset.AlternateKey",
           "scheme.CommissionedFunction", "work.WorkRequest", "work.AlternateKey", "document.Document", "document.Revision", "document.ConfigurationFile", "document.File",
           "record.Record", "record.Finding", "ref.AssetType", "ref.AnsiFunction", "ref.Model", "ref.Manufacturer", "party.Entity", "personnel.Person",
           "process.WorkflowInstance", "process.ProcedureInstance", "process.InstanceVersionSet", "process.BlockInstance", "process.StepInstance", "process.WorkflowTransition"]


def direct_write_check():
    """No loader may INSERT/UPDATE/DELETE a target table directly (§0.5)."""
    bad = []
    for f in os.listdir(HERE):
        if f.endswith(".py") and f not in ("run_rehearsal.py",):
            for i, line in enumerate(open(os.path.join(HERE, f), encoding="utf-8"), 1):
                code = line.split("#")[0]
                if re.search(r"\b(INSERT|UPDATE|DELETE|MERGE)\b\s+(INTO\s+)?\[?\w+\]?\.\[?\w+\]?", code, re.I) and "EXEC" not in code.upper():
                    bad.append(f"{f}:{i}: {line.strip()[:100]}")
    return bad


def catalog_counts(cur, run_ids):
    out = {}
    if not run_ids:
        return out
    ids = ",".join(f"'{r}'" for r in run_ids)
    for t in TARGETS:
        sch, tbl = t.split(".")
        col = "RunId" if False else "MigrationRunId"
        try:
            if cur.execute(f"SELECT COL_LENGTH('{sch}.{tbl}', 'MigrationRunId')").fetchone()[0] is None:
                out[t] = "n/a (AppendOnly: no MigrationRunId; see provenance)"; continue
            out[t] = cur.execute(f"SELECT COUNT(*) FROM [{sch}].[{tbl}] WHERE [{col}] IN ({ids})").fetchone()[0]
        except Exception as e:
            out[t] = f"n/a ({str(e)[:40]})"
    return out


def provenance_check(cur, run_ids):
    """Rows tagged with the run but lacking provenance, per table (the reverse walk must exist)."""
    ids = ",".join(f"'{r}'" for r in run_ids)
    gaps = {}
    for t in TARGETS:
        sch, tbl = t.split(".")
        try:
            if cur.execute(f"SELECT COL_LENGTH('{sch}.{tbl}', 'MigrationRunId')").fetchone()[0] is None:
                continue   # AppendOnly: no MigrationRunId column; provenance is by source key only
            key = "RowId" if cur.execute(f"SELECT COL_LENGTH('{sch}.{tbl}', 'RowId')").fetchone()[0] else None
            if key:
                n = cur.execute(f"""SELECT COUNT(*) FROM [{sch}].[{tbl}] x WHERE x.MigrationRunId IN ({ids})
                                    AND NOT EXISTS (SELECT 1 FROM migration.Provenance p WHERE p.TargetRowId = x.RowId OR (p.TargetEntityId = x.EntityId AND p.TargetTable = '{tbl}'))""").fetchone()[0]
            else:
                n = cur.execute(f"""SELECT COUNT(*) FROM [{sch}].[{tbl}] x WHERE x.MigrationRunId IN ({ids})
                                    AND NOT EXISTS (SELECT 1 FROM migration.Provenance p WHERE p.TargetTable = '{tbl}' AND p.RunId = x.MigrationRunId)""").fetchone()[0]
            if n:
                gaps[t] = n
        except Exception as e:
            gaps[t] = f"check failed: {str(e)[:60]}"
    return gaps


def run_loader(mod, database, limit):
    m = __import__(mod)
    return m.load(database, limit)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--database", default="PnCPlatform_V2_DEV")
    ap.add_argument("--source", choices=[k for k, _ in LOADERS], default=None)
    ap.add_argument("--limit", type=int, default=None, help="load only the first N base numbers (a smoke)")
    ap.add_argument("--no-rerun", action="store_true")
    # The name carries the environment as well as the date. It did not, and on 2026-09-09 a DEV
    # rebuild silently overwrote that morning's QA rehearsal report — same date, same filename.
    ap.add_argument("--report", default=None)
    a = ap.parse_args()
    if not a.database.startswith("PnCPlatform_V2_"):
        sys.exit("refusing: the target must be a PnCPlatform_V2_* database (#99)")
    if a.report is None:
        env = a.database.rsplit("_", 1)[-1] if "_" in a.database else a.database
        a.report = os.path.join(HERE, f"REHEARSAL-{datetime.date.today().isoformat()}-{env}.md")
    os.environ["PNC_TARGET_DB"] = a.database
    sys.path.insert(0, HERE)
    started = datetime.datetime.now()

    passes = []
    for label in ("first", "second"):
        if label == "second" and a.no_rerun:
            break
        reports = []
        for key, mod in LOADERS:
            if a.source and key != a.source:
                continue
            t0 = time.time()
            rep = run_loader(mod, a.database, a.limit)
            rep["elapsed_s"] = round(time.time() - t0, 1)
            reports.append(rep)
            print(f"[{label}] {mod}: written {sum(rep['written'].values())}, skipped {sum(rep['skipped'].values())}, flags {sum(rep['flags'].values())}, {rep['elapsed_s']}s", flush=True)
        passes.append(reports)

    cur = connect(a.database).cursor()
    run_ids = [r["run_id"] for r in passes[0]]
    counts = catalog_counts(cur, run_ids)
    gaps = provenance_check(cur, run_ids)
    prov_total = cur.execute(f"SELECT COUNT(*) FROM migration.Provenance WHERE RunId IN ({','.join(chr(39)+r+chr(39) for r in run_ids)})").fetchone()[0]
    direct = direct_write_check()
    second_written = sum(sum(r["written"].values()) for r in passes[1]) if len(passes) > 1 else None

    L = [f"# Rehearsal {datetime.date.today().isoformat()} — `{a.database}`", "",
         f"Started {started.isoformat(timespec='seconds')}; loaders: {', '.join(m for k, m in LOADERS if not a.source or k == a.source)}"
         + (f"; limited to the first {a.limit} base numbers" if a.limit else "") + ".", "",
         "## Outcome", "",
         f"- First pass wrote **{sum(sum(r['written'].values()) for r in passes[0]):,}** target rows across {len(passes[0])} run(s); "
         f"**{prov_total:,}** provenance rows.",
         f"- Second pass (idempotence): **{second_written if second_written is not None else 'not run'}** rows written — " + ("PASS" if second_written == 0 else ("FAIL" if second_written else "n/a")) + ".",
         f"- Rows tagged with these runs but lacking provenance: **{sum(v for v in gaps.values() if isinstance(v, int))}** " + ("PASS" if not gaps else f"({gaps})") + ".",
         f"- Direct table writes in loaders (grep): **{len(direct)}** " + ("PASS" if not direct else "FAIL") + ".", ""]
    for rep in passes[0]:
        L += [f"## {rep['source']} — run `{rep['run_id']}`", "", f"Actor `{rep['actor']}`; {rep['calls']:,} procedure calls in {rep['seconds']}s.", "",
              "| Target | Written | Skipped (already loaded) |", "|---|---|---|"]
        for t in sorted(set(rep["written"]) | set(rep["skipped"])):
            L.append(f"| `{t}` | {rep['written'].get(t, 0):,} | {rep['skipped'].get(t, 0):,} |")
        L += ["", "| Flag | Count | Examples |", "|---|---|---|"]
        for k, n in sorted(rep["flags"].items(), key=lambda x: -x[1]):
            ex = "; ".join(rep["flag_examples"].get(k, [])[:3]).replace("|", "/")
            L.append(f"| `{k}` | {n:,} | {ex[:220]} |")
        if rep.get("unmapped"):
            L += ["", "Unmapped legacy values (by frequency; owner to extend `mappings/*.csv`):", ""]
            for kind, items in rep["unmapped"].items():
                if items:
                    L += [f"- **{kind}**: " + ", ".join(f"`{v}` ({n})" for v, n in items[:25])]
        if rep.get("attachment_kinds"):
            L += ["", "Predecessor `protection.Attachment.Kind` values seen (M-21 loads a file as a rationale only when its stem is a legacy record number or its Kind says rationale): "
                  + ", ".join(f"`{k}` ({n})" for k, n in sorted(rep["attachment_kinds"].items(), key=lambda x: -x[1])),
                  f"Legacy records with no rationale file: {rep.get('records_without_rationale', 0):,}."]
        L.append("")
    L += ["## Rows in the target tagged with these runs", "", "| Table | Rows |", "|---|---|"]
    for t, n in counts.items():
        if n:
            L.append(f"| `{t}` | {n:,} |" if isinstance(n, int) else f"| `{t}` | {n} |")
    if direct:
        L += ["", "Direct writes found:", *[f"- {d}" for d in direct]]
    L.append("")
    open(a.report, "w", encoding="utf-8", newline="\n").write("\n".join(L))
    print("wrote", a.report)
    sys.exit(0 if (second_written in (0, None) and not gaps and not direct) else 1)


if __name__ == "__main__":
    main()
