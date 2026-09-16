"""#168 (2026-09-16): the round-trip test of a settings template — the writer's output against the filed text.

For every SettingsText revision of the given model(s) that has parsed settings: render(parse(text)) through
process.RenderSettingsText and compare with the file as filed:
  identical     the rendered text is byte-identical to the filed text
  values-equal  every NAME=value pair of the filed text (aliases resolved through the template, chained names expanded,
                empty values, fragments without '=' and names the template does not know ignored — each noted) equals the rendered pairs — the differences are order,
                spelling (an alias), separators or a truncation fragment, each listed
  mismatch      a value differs or a pair is missing on one side — listed; the test fails on any mismatch
A platform-written file must be identical (the strict rule); a legacy text is expected values-equal at best, because the
legacy users typed the lists in 14 different orders and spellings (the survey of 2026-09-16).

  python roundtrip_settings.py --database PnCPlatform_V2_DEV --model "SEL-221F Z1-3=.125-64 OHMS" [--report PATH] [--state Active]
"""
import argparse, datetime, re, sys
import common


def pairs_of(text, aliases, codes=()):
    """The filed text's pairs as the parser reads them (ParseSettingsText's rules), aliases resolved to the template's codes."""
    t = re.sub(r"LOGIC SETTINGS:", ",", text.replace("\r", ",").replace("\n", ","), flags=re.I)
    t = t.replace(", ", ",")
    for c in sorted((set(codes) | set(aliases)), key=len, reverse=True):   # the parser's rule: a space, a known name and '=' is a missing separator
        if " " not in c: t = re.sub(r" " + re.escape(c) + r"=", "," + c + "=", t, flags=re.I)
    out = []; notes = []
    for frag in t.split(","):
        frag = frag.strip()
        if "=" not in frag or frag.index("=") == 0:
            if frag: notes.append(f"fragment ignored: '{frag[:30]}'")
            continue
        i = frag.rindex("=")
        value = frag[i + 1:].strip(); names = [n.strip() for n in frag[:i].split("=") if n.strip()]
        def known(n):
            c = n.upper().replace(" ", "_")
            if re.match(r"LOGIC\w*TINGS:", c): c = c.split(":", 1)[1].lstrip("_")
            return (not codes) or c in codes or c in aliases
        if len(names) > 1 and any((" " in n) and not known(n) for n in names):   # the parser's rule: a value and a name run together
            i = frag.index("="); value = frag[i + 1:].strip(); names = [frag[:i].strip()]; notes.append(f"malformed fragment: {frag[:30]}")
        if not value:
            notes.append(f"empty value: {frag[:30]}"); continue
        for n in names:
            code = n.upper().replace(" ", "_")
            if re.match(r"LOGIC\w*TINGS:", code): code = code.split(":", 1)[1].lstrip("_")   # the misspelt marker, as the parser reads it
            if codes and code not in codes and code not in aliases:
                notes.append(f"not in the template (not written): {code}"); continue
            canon = aliases.get(code, code)
            if canon != code: notes.append(f"alias {code} → {canon}")
            out.append((canon, value))
    # the first occurrence wins (the parser's rule)
    seen = {}; order = []
    for c, v in out:
        if c not in seen: seen[c] = v; order.append(c)
        else: notes.append(f"repeated: {c} (first kept)")
    return seen, order, notes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--database", default=common.TARGET_DB)
    ap.add_argument("--model", action="append", required=True)
    ap.add_argument("--state", default=None, help="GridState filter (Active / Outstanding / Archived); default every revision")
    ap.add_argument("--report", default=None)
    a = ap.parse_args()
    if not a.database.startswith("PnCPlatform_V2_"):
        sys.exit("refusing: the target must be a PnCPlatform_V2_* database (#99)")
    con = common.connect(a.database); cur = con.cursor()
    # the template's aliases (every Effective SettingsParse definition the models bind)
    aliases = {}; codes = set()
    for code, al in cur.execute("""SELECT sd.SettingCode, sd.Aliases FROM config.vSettingDefinition sd
        JOIN config.vDefinitionVersion dv ON dv.RowId = sd.DefinitionVersionRowId AND dv.Status = 'Effective'
        JOIN config.vDefinition d ON d.EntityId = dv.DefinitionEntityId AND d.DefinitionKind = 'Transform.SettingsParse'
        JOIN ref.vFirmwareVersion fv ON fv.ParseTransformDefinitionEntityId = d.EntityId
        JOIN ref.vModel m ON m.ModelId = fv.ModelId
        WHERE m.ModelCode IN (""" + ", ".join("?" for _ in a.model) + ")", *a.model).fetchall():
        codes.add(code.upper())
        for x in (al or "").split(","):
            if x.strip(): aliases[x.strip().upper()] = code.upper()
    sql = """SELECT sr.RevisionRowId, sr.DeviceName, sr.StationName, sr.GridState, sr.RevisionLabel, sr.ParseStatus, f.FileStreamId
        FROM document.vSettingsRecord sr JOIN document.vFile f ON f.RevisionRowId = sr.RevisionRowId AND f.FileRole = 'Native'
        WHERE sr.FileKind = 'SettingsText' AND sr.ModelCode IN (""" + ", ".join("?" for _ in a.model) + ")"
    args = list(a.model)
    if a.state: sql += " AND sr.GridState = ?"; args.append(a.state)
    rows = cur.execute(sql + " ORDER BY sr.StationName, sr.DeviceName, sr.RevisionLabel", *args).fetchall()
    counts = {"identical": 0, "values-equal": 0, "mismatch": 0, "unparsed": 0}
    lines = [f"# Round trip — {', '.join(a.model)} — {a.database} — {datetime.date.today().isoformat()}", "",
             "| Device | Station | State | Rev | Parse | Result | Differences |", "|---|---|---|---|---|---|---|"]
    for rev, dev, stn, state, label, pstatus, stream in rows:
        blob = cur.execute("SELECT file_stream FROM document.FileStore WHERE stream_id = ?", stream).fetchone()
        filed = (bytes(blob[0]) if blob and blob[0] is not None else b"").decode("utf-8", errors="replace")
        if pstatus not in ("Parsed", "Partial"):
            counts["unparsed"] += 1; lines.append(f"| {dev} | {stn} | {state} | {label} | {pstatus} | unparsed | — |"); continue
        rendered = cur.execute("SET NOCOUNT ON; DECLARE @t NVARCHAR(MAX); EXEC process.RenderSettingsText @ConfigurationFileRevisionRowId = ?, @Text = @t OUTPUT; SELECT @t", str(rev)).fetchone()[0] or ""
        if rendered == filed:
            counts["identical"] += 1; lines.append(f"| {dev} | {stn} | {state} | {label} | {pstatus} | identical | |"); continue
        fv, forder, fnotes = pairs_of(filed, aliases, codes)
        # the rendered side is the stored rows themselves: a chain the parser kept whole as one value would re-parse the same way
        # from the rendered text and hide the loss (Woodstock 4779: MTO held 'MRI=MRC=...=00 00 00' and five masks were missing)
        stored = cur.execute("SELECT SettingCode, RawValue FROM document.vParsedSettingNamed WHERE ConfigurationFileRevisionRowId = ? ORDER BY DisplayOrder", str(rev)).fetchall()
        rv = {c.upper(): (v or "") for c, v in stored}; rorder = [c.upper() for c, _ in stored]
        diffs = []
        for c, v in rv.items():
            if "=" in v and any(x.strip() and x.strip() in codes for x in v.split("=")[:-1]): diffs.append(f"{c}: a chain kept as one value '{v[:40]}'")
        for c in forder:
            if c not in rv: diffs.append(f"missing after render: {c}")
            elif rv[c] != fv[c]: diffs.append(f"{c}: filed '{fv[c]}' rendered '{rv[c]}'")
        for c in rorder:
            if c not in fv: diffs.append(f"rendered but not filed: {c}")
        if diffs:
            counts["mismatch"] += 1; lines.append(f"| {dev} | {stn} | {state} | {label} | {pstatus} | **mismatch** | {'; '.join(diffs)[:300]} |")
        else:
            counts["values-equal"] += 1
            why = []
            if forder != [c for c in rorder if c in fv]: why.append("order differs from the SET order")
            why += sorted(set(fnotes))
            lines.append(f"| {dev} | {stn} | {state} | {label} | {pstatus} | values-equal | {'; '.join(why)[:300]} |")
    summary = f"{len(rows)} revision(s): {counts['identical']} identical, {counts['values-equal']} values-equal, {counts['mismatch']} mismatch, {counts['unparsed']} unparsed"
    lines[1:1] = ["", summary, ""]
    print(summary)
    if a.report:
        with open(a.report, "w", encoding="utf-8", newline="\n") as f: f.write("\n".join(lines) + "\n")
        print("report:", a.report)
    sys.exit(1 if counts["mismatch"] else 0)


if __name__ == "__main__":
    main()
