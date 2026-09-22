"""check_wording.py - the interface's words, checked against docs/design/UI-WORDING.md (#221).

The owner, 2026-09-22: the wording must be what a protection and control person would say. This finds the strings a user
READS that break the rule: a decision number, an owner quote or a date given as a reason, a database view, procedure,
permission or definition-kind name, one of our own nouns, or a tool path. It reads the React sources (src/PnC.Web/src)
and the screen definitions (docs/design/examples/screens/*.screen.json); code comments are not user-facing and are left
alone, and so are the manual's and the standards' quoted words (they reach the screen from the database, not from here).

usage: python tools/check_wording.py [--quiet]      exit 1 when anything is found
"""
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB = os.path.join(HERE, "src", "PnC.Web", "src")
SCREENS = os.path.join(HERE, "docs", "design", "examples", "screens")

# what a user must never read, and how to say it instead
RULES = [
    ("a decision number", re.compile(r"#\d{2,3}\b")),
    ("the owner or a date as a reason", re.compile(r"the owner,? (?:2026|20\d\d)|\(the owner\b|owner, 20\d\d-\d\d-\d\d", re.I)),
    ("a database view or procedure name", re.compile(r"\b(?:v[A-Z][A-Za-z]+|[a-z]+\.[A-Z][A-Za-z_]+)\b")),
    ("a permission code", re.compile(r"\b(?:Asset|Scheme|Device|Node|Document|ConfigurationFile|WorkRequest|Obligation|Definition|Record|Location|Connection)\.(?:Read|Modify|Archive|Delete|Approve|Issue)\b")),
    ("a definition kind", re.compile(r"\b(?:CharacteristicSchema|Program|Transform)\.[A-Z][A-Za-z]+\b")),
    ("one of our own nouns", re.compile(r"\b(?:RowId|EntityId|payload|read model|valid time|soft delete|definition version|entity id|the platform (?:writes|derives|evaluates|composes|holds|makes))\b", re.I)),
    ("a tool path", re.compile(r"\btools/[a-z_]+\.py\b")),
]

# a rendered string in the React sources: <Status>…</Status>, a note/title/placeholder/emptyText prop, a label, a plain
# button text. Crude by design: it over-reads rather than miss, and a false hit is fixed by rewording anyway.
RENDER = [
    re.compile(r"<Status[^>]*>([^<{][^<]*)<", re.S),
    re.compile(r"\b(?:note|title|placeholder|emptyText|heading|label|help)\s*[=:]\s*[\"']([^\"']{8,})[\"']"),
    re.compile(r"<(?:h1|h2|h3|h4|summary|dt|th)[^>]*>([^<{][^<]*)<"),
    re.compile(r"<Button[^>]*>([^<{][^<]*)<"),
    re.compile(r"<Panel title=[\"']([^\"']+)[\"']"),
]
JSON_KEYS = ("description", "label", "name", "empty", "badgeLabel", "heading", "note")


def strings_in_tsx(path):
    src = io.open(path, encoding="utf-8").read()
    # drop whole-line comments and JSX comment blocks: they are ours, not the user's
    src = re.sub(r"^\s*//.*$", "", src, flags=re.M)
    src = re.sub(r"\{/\*.*?\*/\}", "", src, flags=re.S)
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    out = []
    for rx in RENDER:
        for m in rx.finditer(src):
            text = " ".join(m.group(1).split())
            # code caught by a greedy prop match is not prose: a template hole, an arrow, a closing brace
            if len(text) >= 3 and "${" not in text and "=>" not in text and "})" not in text:
                out.append((src[:m.start()].count("\n") + 1, text))
    return out


def strings_in_json(path):
    doc = json.load(io.open(path, encoding="utf-8"))
    out = []

    def walk(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if k in JSON_KEYS and isinstance(v, str) and len(v) >= 3: out.append((0, v))
                else: walk(v)
        elif isinstance(o, list):
            for v in o: walk(v)
    walk(doc)
    return out


def main():
    quiet = "--quiet" in sys.argv
    findings = []
    for root, _dirs, files in os.walk(WEB):
        for f in sorted(files):
            if f.endswith(".tsx"):
                path = os.path.join(root, f)
                for line, text in strings_in_tsx(path):
                    for why, rx in RULES:
                        if rx.search(text): findings.append((os.path.relpath(path, HERE), line, why, text[:150]))
    for f in sorted(os.listdir(SCREENS)):
        if f.endswith(".json"):
            path = os.path.join(SCREENS, f)
            for line, text in strings_in_json(path):
                for why, rx in RULES:
                    if rx.search(text): findings.append((os.path.relpath(path, HERE), line, why, text[:150]))
    by_file = {}
    for path, line, why, text in findings: by_file.setdefault(path, []).append((line, why, text))
    if not quiet:
        for path in sorted(by_file):
            print(path)
            for line, why, text in by_file[path]:
                print("   " + (str(line) + ":").ljust(6) + why + " - " + text)
    print(f"{len(findings)} string(s) to reword in {len(by_file)} file(s) (docs/design/UI-WORDING.md)")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
