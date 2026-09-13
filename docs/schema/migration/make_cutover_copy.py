"""W8 cutover rehearsal (CUTOVER-STRATEGY §3, decision #149): the "client's copy" of the legacy database, made from the
restored one on VM01 as `dbRelayManagement_Legacy_Cutover` — the nine tables copied whole (SELECT INTO), then a known set
of mutations applied so the hash diff has something to find: per table one row added, one changed, one deleted, all
recorded here and printed. This is a scratch legacy copy: direct writes to it are the rehearsal's own business and never
touch a platform table (#138). Idempotent: an existing copy is dropped and remade.

  python make_cutover_copy.py [--copy dbRelayManagement_Legacy_Cutover]
"""
import argparse, json, sys
import common

SOURCE = "dbRelayManagement_Legacy"
TABLES = ["SETTINGS", "Settings Management", "Relay Document Management", "Setting Database Management", "Setting Software Management", "Setting Software Data", "LOCATIONS", "Users"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--copy", default="dbRelayManagement_Legacy_Cutover")
    a = ap.parse_args()
    if a.copy.startswith("PnCPlatform"):
        sys.exit("refusing: the copy is a legacy scratch database, never a platform one")
    m = common.connect("master"); mc = m.cursor()
    exists = mc.execute("SELECT COUNT(*) FROM sys.databases WHERE name = ?", a.copy).fetchone()[0]
    if exists:
        mc.execute(f"ALTER DATABASE [{a.copy}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{a.copy}]")
    mc.execute(f"CREATE DATABASE [{a.copy}]")
    print(f"created {a.copy}")
    c = common.connect(a.copy); cur = c.cursor()
    counts = {}
    for t in TABLES:
        cur.execute(f"SELECT * INTO [dbo].[{t}] FROM [{SOURCE}].[dbo].[{t}]")
        counts[t] = cur.execute(f"SELECT COUNT(*) FROM [dbo].[{t}]").fetchone()[0]
    print("copied", counts)

    mutations = []
    # SETTINGS: one row added (a new P row for a real base), one changed (SET1 text), one deleted
    # [Change Request ID] is an IDENTITY column in the legacy SETTINGS (SELECT INTO keeps it): the added row names its own
    cur.execute("SET IDENTITY_INSERT dbo.SETTINGS ON; INSERT INTO dbo.SETTINGS (OLD_NO, [Change Request ID], LOCATION, ASSET, EQUIPMENT, DEVICE, MANUFACTURER, SET1, CDATE, VDATE) SELECT 'P9999', 99999901, LOCATION, ASSET, EQUIPMENT, DEVICE, MANUFACTURER, 'CUTOVER=ADDED', CDATE, VDATE FROM dbo.SETTINGS WHERE OLD_NO = 'A0227'; SET IDENTITY_INSERT dbo.SETTINGS OFF")
    mutations.append(("SETTINGS", "added", "P9999 / CR 99999901 (a superseded record for base 0227)"))
    cur.execute("UPDATE dbo.SETTINGS SET SET1 = ISNULL(SET1, '') + CHAR(13) + CHAR(10) + 'CUTOVER=CHANGED' WHERE OLD_NO = 'A0227'")
    mutations.append(("SETTINGS", "changed", "A0227: SET1 gained a line CUTOVER=CHANGED"))
    r = cur.execute("SELECT TOP (1) OLD_NO, [Change Request ID] FROM dbo.SETTINGS WHERE LEFT(OLD_NO, 1) = 'D' ORDER BY OLD_NO").fetchone()
    cur.execute("DELETE FROM dbo.SETTINGS WHERE OLD_NO = ? AND [Change Request ID] = ?", r[0], r[1])
    mutations.append(("SETTINGS", "deleted", f"{r[0]} / CR {r[1]} (a D row)"))
    # header: one added (for the new P row), one changed (a note), one deleted
    cur.execute("INSERT INTO dbo.[Settings Management] ([Change Request ID], [Relay ID Number], [Type], [Reqested By], Notes) VALUES (99999901, 'P9999', 'Add Order', 'Cutover Rehearsal', 'added at the cutover rehearsal')")
    mutations.append(("Settings Management", "added", "CR 99999901 / P9999"))
    cur.execute("UPDATE dbo.[Settings Management] SET Notes = 'CUTOVER CHANGED' WHERE [Change Request ID] = 2144042 AND [Relay ID Number] = 'P0002'")
    mutations.append(("Settings Management", "changed", "CR 2144042 / P0002: Notes"))
    # no header or track row names a D relay: the deleted rows are a superseded relay's (not P0002, whose rows are the changed ones)
    r = cur.execute("SELECT TOP (1) [Change Request ID], [Relay ID Number] FROM dbo.[Settings Management] WHERE [Relay ID Number] LIKE 'P%' AND [Relay ID Number] NOT IN ('P0002', 'P9999') ORDER BY [Change Request ID] DESC").fetchone()
    cur.execute("DELETE FROM dbo.[Settings Management] WHERE [Change Request ID] = ? AND [Relay ID Number] = ?", r[0], r[1])
    mutations.append(("Settings Management", "deleted", f"CR {r[0]} / {r[1]}"))
    # the two tracks: one added row each for the new P row; one changed date; one deleted superseded relay's row
    for t in ("Relay Document Management", "Setting Database Management"):
        cur.execute(f"INSERT INTO dbo.[{t}] ([Change Request ID], [Relay ID Number], Status, Date) VALUES (99999901, 'P9999', 'Complete', '2026-09-01')")
        mutations.append((t, "added", "CR 99999901 / P9999 Complete 2026-09-01"))
        cur.execute(f"UPDATE dbo.[{t}] SET Date = '2008-07-11' WHERE [Change Request ID] = 2144042 AND [Relay ID Number] = 'P0002'")
        mutations.append((t, "changed", "CR 2144042 / P0002: Date 2008-07-10 → 2008-07-11"))
        r = cur.execute(f"SELECT TOP (1) [Change Request ID], [Relay ID Number] FROM dbo.[{t}] WHERE [Relay ID Number] LIKE 'P%' AND [Relay ID Number] NOT IN ('P0002', 'P9999') ORDER BY [Change Request ID] DESC").fetchone()
        cur.execute(f"DELETE FROM dbo.[{t}] WHERE [Change Request ID] = ? AND [Relay ID Number] = ?", r[0], r[1])
        mutations.append((t, "deleted", f"CR {r[0]} / {r[1]}"))
    # LOCATIONS: one added station, one changed group, one deleted duplicate row
    cur.execute("INSERT INTO dbo.LOCATIONS (Location, USERNAME) VALUES ('CUTOVER TEST TERMINAL', 'Eng')")
    mutations.append(("LOCATIONS", "added", "CUTOVER TEST TERMINAL / Eng"))
    cur.execute("UPDATE dbo.LOCATIONS SET USERNAME = 'Dist' WHERE Location = 'NEGUAC' AND USERNAME = 'Eng'")
    mutations.append(("LOCATIONS", "changed", "NEGUAC: Eng → Dist"))
    cur.execute("DELETE TOP (1) FROM dbo.LOCATIONS WHERE Location = 'BELLEDUNE PLANT' AND USERNAME = 'Eng'")
    mutations.append(("LOCATIONS", "deleted", "one of BELLEDUNE PLANT's Eng rows"))
    # Users: one added
    cols = [d[0] for d in cur.execute("SELECT TOP 0 * FROM dbo.Users").description]
    print("Users columns:", cols)
    after = {t: cur.execute(f"SELECT COUNT(*) FROM [dbo].[{t}]").fetchone()[0] for t in TABLES}
    print("after mutations", after)
    for t, kind, what in mutations:
        print(f"  {t}: {kind}: {what}")
    json.dump({"copy": a.copy, "before": counts, "after": after, "mutations": mutations}, open("CUTOVER-COPY-MUTATIONS.json", "w", encoding="utf-8"), indent=1)
    print("expected by the diff: added", sum(1 for m in mutations if m[1] == "added"), "changed", sum(1 for m in mutations if m[1] == "changed"), "deleted", sum(1 for m in mutations if m[1] == "deleted"))


if __name__ == "__main__":
    main()
