"""
Writes SOURCES.md: the migration sources as found on VM01 — tables, row counts, columns for the
small sources, table list for the large ones. Backup copies in dbGridInfo are excluded
(names matching %Backup%, TLM_%, RepairBackup%).

    python docs/schema/migration/catalogue_sources.py
"""
import os, datetime
from common import connect, HERE

OUT = os.path.join(HERE, "SOURCES.md")
EXCLUDE = "t.name NOT LIKE '%Backup%' AND t.name NOT LIKE 'TLM[_]%' AND t.name NOT LIKE 'RepairBackup%'"


def tables(cur, where="1=1"):
    return cur.execute(f"""
        SELECT s.name, t.name, SUM(p.rows)
        FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
        JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
        WHERE {where} GROUP BY s.name, t.name ORDER BY s.name, t.name""").fetchall()


def columns(cur, schema, table):
    return cur.execute("""
        SELECT c.name, ty.name, c.max_length, c.is_nullable
        FROM sys.columns c JOIN sys.types ty ON ty.user_type_id = c.user_type_id
        WHERE c.object_id = OBJECT_ID(QUOTENAME(?) + '.' + QUOTENAME(?)) ORDER BY c.column_id""", schema, table).fetchall()


def main():
    lines = [f"# Migration sources as found on VM01 (10.10.70.25)", "",
             f"Generated {datetime.date.today().isoformat()} by `catalogue_sources.py`, read-only, as `dev_pnc`. Row counts are the live copies'.", ""]

    cur = connect("dbRelayManagement_Legacy").cursor()
    lines += ["## `dbRelayManagement_Legacy` — the 1990s settings database (the one live import, decision 181)", "",
              "Capture on `Z:\\Reference\\SqlBackup\\dbRelayManagement_legacy.bak` dated 2026-04-22; restored on VM01. `dbo.Users` (32 rows, with passwords) is never migrated.", ""]
    for sch, tbl, n in tables(cur):
        lines.append(f"### `{sch}.{tbl}` — {n:,} rows")
        lines += ["", "| Column | Type | Nullable |", "|---|---|---|"]
        for c, ty, ml, nl in columns(cur, sch, tbl):
            size = "" if ml in (-1, None) or ty in ("int", "smallint", "bigint", "datetime", "bit", "uniqueidentifier") else f"({'MAX' if ml == -1 else (ml // 2 if ty.startswith('n') else ml)})"
            lines.append(f"| `{c}` | {ty}{size} | {'yes' if nl else 'no'} |")
        lines.append("")

    cur = connect("dbGridInfo").cursor()
    live = tables(cur, EXCLUDE)
    total = len(tables(cur))
    lines += [f"## `dbGridInfo` — TLM (transmission line model), a feed for step 13", "",
              f"{total} tables of which {len(live)} are live; the rest are dated `*Backup*` / `TLM_*` working copies and are excluded. Live tables with rows:", "",
              "| Table | Rows |", "|---|---|"]
    for sch, tbl, n in live:
        if n:
            lines.append(f"| `{sch}.{tbl}` | {n:,} |")
    lines.append("")

    cur = connect("dbPCPlatform_DEV").cursor()
    lines += ["## `dbPCPlatform_DEV` — the predecessor (schema comparison; seed lists §14.2; DEV/TRAIN population §14.1)", "",
              "Full catalogue: `docs/reference/dbPCPlatform_DEV-schema.md`. Tables by schema:", "", "| Schema | Tables | Rows |", "|---|---|---|"]
    by = {}
    for sch, tbl, n in tables(cur):
        t, r = by.get(sch, (0, 0)); by[sch] = (t + 1, r + (n or 0))
    for sch, (t, r) in sorted(by.items()):
        lines.append(f"| `{sch}` | {t} | {r:,} |")
    lines += ["", "## `PNC_Dev`, `PNC_Training`, `PNC_Production`", ""]
    cur = connect("PNC_Dev").cursor()
    n = cur.execute("SELECT COUNT(*) FROM sys.tables").fetchone()[0]
    lines += [f"Same predecessor schema as `dbPCPlatform_DEV` plus a few tables ({n} tables). Corrected 2026-09-14 (W8): these are the environments of **pnc-platform** (`Z:\\Repos\\pnc-platform.git`, C++/CMake API + React) and of **Dev_Final** (`pilot/hardening-2026-06-12`, C++Builder console server + React), not of the legacy C++Builder settings program (that program's database is `dbRelayManagement_Legacy`, renamed `dbRelay` on the server by the owner on 2026-09-14). Training = Production; Dev holds the activity. Not migration sources — reference applications for UX and the function inventory (decision #158); listed so the question in the 2026-09-04 checkpoint is closed.", ""]
    open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
