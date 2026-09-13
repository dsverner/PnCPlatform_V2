"""
The hash-diff cutover tool (docs/migration/CUTOVER-STRATEGY.md §3; decisions #32, W7). The whole legacy database is
48 706 rows: hash every row of every table in two copies, keyed by the natural keys of §3, and say which rows are
unchanged, added, changed or deleted. Runs in seconds; catches back-dated edits a watermark would miss.

    python tools/cutover_diff.py --left db:dbRelayManagement_Legacy --right db:dbRelayManagement_Client [--server 10.10.70.25]
    python tools/cutover_diff.py --left db:dbRelayManagement_Legacy --snapshot ours.json          # hash a copy to a file
    python tools/cutover_diff.py --left ours.json --right ours.json                                # a copy against itself → 0
    python tools/cutover_diff.py --left ours.json --mutate 5 --out mutated.json                    # a deliberately mutated copy
    python tools/cutover_diff.py --left ours.json --right mutated.json --report diff.md            # → exactly 5 changed

A side is `db:<database>` (read-only, the dev.local credentials of docs/schema/migration/common.py) or a snapshot file
written by --snapshot. The exit code is the number of rows that differ (added + changed + deleted), capped at 250.
Applying the differences is the importer's job (legacy_import.py is idempotent on the source row hash, so re-running it
over the client's copy loads exactly the added and changed rows; deleted rows are reported for a person — W8).
"""
import argparse, datetime, hashlib, json, os, random, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "docs", "schema", "migration"))
import common  # noqa: E402

# the natural keys of §3; a table with no reliable key hashes whole rows and treats duplicates as a set
KEYS = {
    "SETTINGS": ["OLD_NO", "Change Request ID"],
    "Relay Document Management": ["Change Request ID", "Relay ID Number"],
    "Setting Database Management": ["Change Request ID", "Relay ID Number"],
    "Setting Software Management": ["Change Request ID", "Relay ID Number"],
    "Settings Management": None,
    "LOCATIONS": None,
    "Users": None,
    "Setting Software Data": None,
}


def canon(v):
    if v is None:
        return ""
    if isinstance(v, datetime.datetime):
        return v.isoformat()
    if isinstance(v, bytes):
        return v.hex()
    return str(v).strip()


def hash_table(cur, table):
    """{key: row_hash} for one table; whole-row keys where §3 names none, made unique by an occurrence counter."""
    cur.execute(f"SELECT * FROM dbo.[{table}]")
    cols = [d[0] for d in cur.description]
    keycols = KEYS.get(table)
    out, seen = {}, {}
    for row in cur.fetchall():
        vals = [canon(v) for v in row]
        h = hashlib.sha256("\x1f".join(vals).encode("utf-8")).hexdigest()
        if keycols:
            k = "|".join(canon(row[cols.index(c)]) for c in keycols)
        else:
            k = h
        n = seen.get(k, 0) + 1; seen[k] = n
        if n > 1:
            k = f"{k}#{n}"        # a duplicate natural key (the header's 894): kept as a set, never collapsed
        out[k] = h
    return cols, out


def load_side(spec, server):
    if spec.startswith("db:"):
        cur = common.connect(spec[3:], server=server).cursor()
        tables = {}
        for t in KEYS:
            try:
                cols, rows = hash_table(cur, t)
            except Exception as e:  # a table absent in the copy is reported, not fatal
                tables[t] = {"error": str(e)[:200], "columns": [], "rows": {}}
                continue
            tables[t] = {"columns": cols, "rows": rows}
        return {"source": spec, "taken": datetime.datetime.now().isoformat(timespec="seconds"), "tables": tables}
    with open(spec, encoding="utf-8") as f:
        return json.load(f)


def diff(left, right):
    report = {}
    for t in KEYS:
        l = left["tables"].get(t, {}).get("rows", {}); r = right["tables"].get(t, {}).get("rows", {})
        added = sorted(k for k in r if k not in l)
        deleted = sorted(k for k in l if k not in r)
        changed = sorted(k for k in l if k in r and l[k] != r[k])
        unchanged = len(l) - len(deleted) - len(changed)
        report[t] = {"left": len(l), "right": len(r), "unchanged": unchanged, "added": added, "changed": changed, "deleted": deleted}
    return report


def mutate(snapshot, n, seed=1):
    """A copy of the snapshot with n rows changed (their hash replaced), for the gate's 'deliberately mutated copy'."""
    rnd = random.Random(seed)
    out = json.loads(json.dumps(snapshot))
    keys = [(t, k) for t, tb in out["tables"].items() for k in tb["rows"]]
    changed = []
    for t, k in rnd.sample(keys, n):
        out["tables"][t]["rows"][k] = hashlib.sha256(f"mutated:{t}:{k}".encode()).hexdigest()
        changed.append((t, k))
    out["mutations"] = changed
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--left", required=True, help="db:<database> or a snapshot file")
    ap.add_argument("--right", default=None, help="db:<database> or a snapshot file")
    ap.add_argument("--server", default=common.SERVER)
    ap.add_argument("--snapshot", default=None, help="write the left side's hashes to this file")
    ap.add_argument("--mutate", type=int, default=None, help="write a copy of the left side with N rows changed to --out")
    ap.add_argument("--out", default=None)
    ap.add_argument("--report", default=None, help="markdown report path")
    a = ap.parse_args()
    left = load_side(a.left, a.server)
    if a.snapshot:
        with open(a.snapshot, "w", encoding="utf-8") as f:
            json.dump(left, f)
        print(f"snapshot: {a.snapshot} — " + ", ".join(f"{t} {len(tb['rows']):,}" for t, tb in left["tables"].items()))
    if a.mutate is not None:
        m = mutate(left, a.mutate)
        with open(a.out or "mutated.json", "w", encoding="utf-8") as f:
            json.dump(m, f)
        print(f"mutated copy: {a.out or 'mutated.json'} — {a.mutate} row(s) changed: " + "; ".join(f"{t} {k}" for t, k in m["mutations"]))
    if a.right is None:
        return 0
    right = load_side(a.right, a.server)
    rep = diff(left, right)
    total = sum(len(x["added"]) + len(x["changed"]) + len(x["deleted"]) for x in rep.values())
    lines = [f"# Cutover diff — {a.left} vs {a.right} — {datetime.datetime.now().isoformat(timespec='seconds')}", "",
             "| Table | Left | Right | Unchanged | Added | Changed | Deleted |", "|---|---:|---:|---:|---:|---:|---:|"]
    for t, x in rep.items():
        lines.append(f"| `{t}` | {x['left']:,} | {x['right']:,} | {x['unchanged']:,} | {len(x['added']):,} | {len(x['changed']):,} | {len(x['deleted']):,} |")
    lines += ["", f"**{total:,} row(s) differ.**", ""]
    for t, x in rep.items():
        for kind in ("added", "changed", "deleted"):
            if x[kind]:
                lines.append(f"- `{t}` {kind}: " + ", ".join(x[kind][:20]) + (" …" if len(x[kind]) > 20 else ""))
    text = "\n".join(lines)
    print(text)
    if a.report:
        with open(a.report, "w", encoding="utf-8") as f:
            f.write(text + "\n")
    return min(total, 250)


if __name__ == "__main__":
    sys.exit(main())
