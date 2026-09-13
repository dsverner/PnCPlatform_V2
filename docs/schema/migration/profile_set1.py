"""
W7 — profile the legacy SET1 text per device model, read-only, for the owner's settings-template card (decision #61:
"the per-model templates … are seeded by parsing every model's patterns — put to the owner as a card before they are
final"). For each (MANUFACTURER, DEVICE) label among the A rows: how many rows carry SET1, and the setting names found
(name=value pairs, the same split process.ParseSettingsText uses), with counts. Output: a markdown table and a JSON file.

    python docs/schema/migration/profile_set1.py [--top 40] [--out SET1-PROFILE-<date>.md]
"""
import argparse, datetime, json, os, re, sys
from collections import Counter, defaultdict
import common

HERE = os.path.dirname(os.path.abspath(__file__))
PAIR = re.compile(r"\s*([^=,;]+?)\s*=\s*([^,;]*)")


def names_of(text):
    out = []
    for m in PAIR.finditer(text or ""):
        n = re.sub(r"\s+", "_", m.group(1).strip().upper())
        if n and len(n) <= 40 and re.match(r"^[A-Z0-9_./#\-']+$", n):
            out.append(n)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=40, help="models to list (by active-row count)")
    ap.add_argument("--out", default=os.path.join(HERE, f"SET1-PROFILE-{datetime.date.today().isoformat()}.md"))
    a = ap.parse_args()
    cur = common.connect("dbRelayManagement_Legacy").cursor()
    rows = cur.execute("SELECT LTRIM(RTRIM(MANUFACTURER)), LTRIM(RTRIM(DEVICE)), SET1 FROM dbo.SETTINGS WHERE LEFT(OLD_NO,1) = 'A'").fetchall()
    per = defaultdict(lambda: {"rows": 0, "with_text": 0, "names": Counter(), "samples": []})
    for mfr, dev, set1 in rows:
        k = (common.s(mfr) or "UNKNOWN", common.s(dev) or "UNKNOWN DEVICE")
        p = per[k]; p["rows"] += 1
        t = common.s(set1)
        if not t:
            continue
        p["with_text"] += 1
        ns = names_of(t)
        p["names"].update(set(ns))
        if len(p["samples"]) < 2:
            p["samples"].append(t[:120])
    ranked = sorted(per.items(), key=lambda kv: -kv[1]["rows"])
    L = [f"# SET1 profile per model — active rows — {datetime.date.today().isoformat()}", "",
         f"{len(rows):,} active rows, {len(per):,} distinct (manufacturer, device) labels; the {a.top} most common below. A name is the left side of a",
         "name=value pair as ParseSettingsText splits it; the count is the number of rows the name appears in. Free-text SET1 (\"SEE SETTINGS DOCUMENT\")",
         "yields no names and is a native-file relay in practice.", "",
         "| # | Manufacturer | Device label | Rows | With text | Names (rows) | Sample |", "|---:|---|---|---:|---:|---|---|"]
    out = []
    for i, ((mfr, dev), p) in enumerate(ranked[: a.top], 1):
        names = ", ".join(f"{n} ({c})" for n, c in p["names"].most_common(12))
        L.append(f"| {i} | {mfr} | {dev} | {p['rows']} | {p['with_text']} | {names} | {(p['samples'][0] if p['samples'] else '').replace('|', '/')} |")
        out.append({"manufacturer": mfr, "device": dev, "rows": p["rows"], "with_text": p["with_text"], "names": p["names"].most_common(30), "samples": p["samples"]})
    with open(a.out, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
    with open(a.out.replace(".md", ".json"), "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
    print(f"wrote {a.out} ({len(per)} labels, top {a.top})")


if __name__ == "__main__":
    main()
