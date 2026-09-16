"""W8 (decision #153): after a model gains a settings template, re-parse the migrated text files of its devices —
process.ParseSettingsText on every SettingsText revision still NotParsed (or Partial/Empty when --all), the text read back
from the file store as it was written (UTF-8, legacy SET1). Writes only through the deployed procedure, as the SYSTEM actor,
no provenance of its own: the parse is a derived state of a row that already has provenance (document.ParsedSetting).

  python reparse_settings.py --database PnCPlatform_V2_DEV [--model SEL-551 ...] [--all]
"""
import argparse, sys, time
import common

SYSTEM_ACTOR = "00000000-0000-0000-0000-000000000001"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--database", default=common.TARGET_DB)
    ap.add_argument("--model", action="append", default=None, help="model code(s); default: every model that has a template")
    ap.add_argument("--all", action="store_true", help="also re-parse Partial and Empty revisions, not only NotParsed")
    ap.add_argument("--force", action="store_true", help="re-parse every revision, Parsed ones included (a parser rule or the template changed, #168)")
    a = ap.parse_args()
    if not a.database.startswith("PnCPlatform_V2_"):
        sys.exit("refusing: the target must be a PnCPlatform_V2_* database (#99)")
    con = common.connect(a.database); cur = con.cursor()
    statuses = "(N'NotParsed', N'Partial', N'Empty', N'Parsed')" if a.force else "(N'NotParsed', N'Partial', N'Empty')" if a.all else "(N'NotParsed')"
    sql = f"""SELECT cf.RevisionRowId, f.FileStreamId, m.ModelCode
        FROM document.vConfigurationFile cf
        JOIN document.vFile f ON f.RevisionRowId = cf.RevisionRowId AND f.FileRole = N'Native'
        JOIN asset.vAsset ast ON ast.EntityId = cf.DeviceEntityId
        JOIN ref.vModel m ON m.ModelId = ast.ModelId
        WHERE cf.FileKind = N'SettingsText' AND cf.ParseStatus IN {statuses}
          AND EXISTS (SELECT 1 FROM ref.vFirmwareVersion fv WHERE fv.ModelId = m.ModelId AND fv.ParseTransformDefinitionEntityId IS NOT NULL)"""
    if a.model:
        sql += " AND m.ModelCode IN (" + ", ".join("?" for _ in a.model) + ")"
    rows = cur.execute(sql, *(a.model or [])).fetchall()
    print(f"{a.database}: {len(rows)} revision(s) to parse")
    t0 = time.time(); done = matched = unmatched = failed = 0
    for rev, stream, code in rows:
        blob = cur.execute("SELECT file_stream FROM document.FileStore WHERE stream_id = ?", stream).fetchone()
        text = (bytes(blob[0]) if blob and blob[0] is not None else b"").decode("utf-8", errors="replace")
        try:
            r = cur.execute("SET NOCOUNT ON; DECLARE @m INT, @u INT; EXEC process.ParseSettingsText @ConfigurationFileRevisionRowId = ?, @Text = ?, @ActorId = ?, @Matched = @m OUTPUT, @Unmatched = @u OUTPUT; SELECT @m, @u",
                            str(rev), text, SYSTEM_ACTOR).fetchone()
            matched += r[0] or 0; unmatched += r[1] or 0; done += 1
        except Exception as e:   # noqa: BLE001 — counted and shown, the run continues
            failed += 1
            if failed <= 5: print("  failed:", code, rev, str(e)[:160])
    print(f"parsed {done} revision(s): {matched} settings matched, {unmatched} names unmatched, {failed} failed, {round(time.time() - t0)} s")
    for code, n, st in cur.execute(f"""SELECT m.ModelCode, COUNT(*), cf.ParseStatus FROM document.vConfigurationFile cf
        JOIN asset.vAsset ast ON ast.EntityId = cf.DeviceEntityId JOIN ref.vModel m ON m.ModelId = ast.ModelId
        WHERE cf.FileKind = N'SettingsText' AND m.ModelCode IN ({', '.join('?' for _ in (a.model or ['SEL-551','SEL-311C','SEL-221F Z1-3=.125-64 OHMS']))})
        GROUP BY m.ModelCode, cf.ParseStatus ORDER BY 1, 3""", *(a.model or ['SEL-551', 'SEL-311C', 'SEL-221F Z1-3=.125-64 OHMS'])).fetchall():
        print(f"  {code}: {st} {n}")


if __name__ == "__main__":
    main()
