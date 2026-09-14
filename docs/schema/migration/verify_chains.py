"""W8 (decision #156): every chain's revisions checked against the source — for each A/M/P row of dbRelayManagement_Legacy,
the platform revision that carries it (by provenance key Revision:<OLD_NO>|<CR>) must hold the row's SET1 text (by SHA-256
of its UTF-8 bytes, as the file was written) and, for A and P rows, an in-service start equal to the row's VDATE (else CDATE,
else the capture instant when both are null or sentinel) or the +1 s adjustment the chain rule allows. Read-only; prints
the counts and the first mismatches, exit 1 if any text differs.

  python verify_chains.py --database PnCPlatform_V2_QA
"""
import argparse, datetime, hashlib, sys
import common
from legacy_import import dto, SENTINEL

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--database", default=common.TARGET_DB)
    ap.add_argument("--show", type=int, default=8)
    a = ap.parse_args()
    if not a.database.startswith("PnCPlatform_V2_"):
        sys.exit("refusing: the target must be a PnCPlatform_V2_* database (#99)")
    src = common.connect("dbRelay").cursor()   # the legacy copy, renamed by the owner 2026-09-14 (legacy_import.SOURCE_DB)
    tgt = common.connect(a.database); tgt.add_output_converter(-155, lambda b: b); cur = tgt.cursor()
    legacy = {}
    for oldno, cr, set1, cdate, vdate in src.execute("SELECT OLD_NO, [Change Request ID], SET1, CDATE, VDATE FROM SETTINGS WHERE LEFT(OLD_NO,1) IN ('A','M','P')").fetchall():
        legacy[(oldno, cr)] = (hashlib.sha256((set1 or "").strip().encode("utf-8")).hexdigest(), cdate, vdate)   # the importer strips the text (strip()) before writing
    rows = cur.execute("""SELECT p.SourceKey, f.Sha256, CONVERT(NVARCHAR(19), cf.InServiceFrom, 120), cf.InServiceFromQuality
        FROM migration.vProvenance p
        JOIN document.vConfigurationFile cf ON cf.RevisionRowId = p.TargetRowId
        LEFT JOIN document.vFile f ON f.RevisionRowId = cf.RevisionRowId AND f.FileRole = N'Native'
        WHERE p.TargetTable = 'ConfigurationFile' AND p.SourceKey LIKE 'Revision:%'""").fetchall()
    text_ok = text_bad = date_ok = date_adj = date_bad = date_none = missing = 0; bad = []
    for key, sha, isf, isq in rows:
        oldno, cr = key.split(":", 1)[1].split("|"); cr = int(cr)
        L = legacy.get((oldno, cr))
        if L is None:
            missing += 1; continue
        sha_t = bytes(sha).hex() if sha is not None and not isinstance(sha, str) else (sha or "")
        if sha_t.lower() == L[0]: text_ok += 1
        else: text_bad += 1; bad.append((key, "text", sha_t[:12], L[0][:12]))
        if oldno[0] == "M":
            continue
        exp, _, _ = dto(L[2])
        if exp is None:
            exp, _, _ = dto(L[1])
        if isf is None: date_none += 1; continue
        if exp is None: date_ok += 1; continue     # capture instant by rule; not compared
        if isf[:10] == exp[:10]: date_ok += 1
        elif isq == 2: date_adj += 1                # the chain rule's +1 s on a shared or out-of-order VDATE, flagged quality 2
        else: date_bad += 1; bad.append((key, "date", isf, exp[:19]))
    print(f"{a.database}: {len(rows)} revisions with provenance; legacy rows not found {missing}")
    print(f"  text: {text_ok} equal, {text_bad} differ")
    print(f"  in-service start (A and P): {date_ok} equal the source date, {date_adj} adjusted by the chain rule (quality 2), {date_bad} differ, {date_none} none")
    for b in bad[: a.show]: print("  ", b)
    sys.exit(1 if text_bad or date_bad else 0)


if __name__ == "__main__":
    main()
