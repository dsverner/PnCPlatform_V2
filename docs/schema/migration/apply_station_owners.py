"""W8 card A (owner, 2026-09-13; decision #153): move the migrated stations of an existing V2 database under the owner's
marked division (mappings/station_owner.csv) — Transmission, Generation, Distribution — through location.MoveNode, as
a migration run with provenance (one row per move). A division the tree lacks is created under NB Power. Idempotent:
a station already under its marked division is skipped. A fresh load places them there itself (legacy_import.py).

  python apply_station_owners.py --database PnCPlatform_V2_DEV
"""
import argparse, os, sys
from common import Run, row_hash, TARGET_DB
from legacy_import import read_csv, CAPTURE_AT

SOURCE = "dbRelayManagement_Legacy"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--database", default=TARGET_DB)
    a = ap.parse_args()
    if not a.database.startswith("PnCPlatform_V2_"):
        sys.exit("refusing: the target must be a PnCPlatform_V2_* database (#99)")
    mapping = {m["legacy_location"].strip().upper(): m["owner"].strip() for m in read_csv("station_owner.csv") if m.get("owner")}
    with Run(SOURCE, CAPTURE_AT, notes="W8 card A: stations under the owner's marked division (#153)", target_db=a.database) as run:
        owner = run.rows("SELECT TOP (1) EntityId FROM location.vNode WHERE NodeTypeCode = N'Owner' AND Name = N'NB Power'")[0][0]
        divisions = {r[0]: str(r[1]) for r in run.rows("SELECT Name, EntityId FROM location.vNode WHERE NodeTypeCode = N'Division' AND ParentEntityId = ?", owner)}
        stations = run.rows("""SELECT s.EntityId, s.Name, d.Name FROM location.vNode s JOIN location.vNode d ON d.EntityId = s.ParentEntityId
                               WHERE s.NodeTypeCode = N'Station' AND s.MigrationRunId IS NOT NULL""")
        moved = skipped = unmapped = 0
        for sid, name, division in stations:
            target = mapping.get(name.strip().upper())
            if not target:
                unmapped += 1; continue
            if target == division or (target in divisions and divisions[target] == str(run.rows("SELECT ParentEntityId FROM location.vNode WHERE EntityId = ?", sid)[0][0])):
                skipped += 1; continue
            if target not in divisions:
                merchant = run.rows("SELECT TOP (1) d.EntityId FROM location.vNode o JOIN location.vNode d ON d.ParentEntityId = o.EntityId AND d.NodeTypeCode = N'Division' AND d.Name = N'Generation' WHERE o.NodeTypeCode = N'Owner' AND o.Name = ?", target)
                if merchant: divisions[target] = str(merchant[0][0])
            if target not in divisions:
                (e, r) = run.exec("location.AddNode", outputs=[("EntityId", "UNIQUEIDENTIFIER"), ("RowId", "UNIQUEIDENTIFIER")], NodeTypeCode="Division", ParentEntityId=str(owner), Name=target,
                                  Notes="Created for the owner's station markup (W8 card A, #153)")
                run.provenance("location", "Node", f"Division:{target}", row_hash("Division", str(owner), target), entity_id=e, row_id=r)
                divisions[target] = str(e)
            key = f"StationOwner:{name}"; h = row_hash("StationOwner", name, target)
            if run.already_loaded("location", "Node", key, h):
                skipped += 1; continue
            (r,) = run.exec("location.MoveNode", outputs=[("RowId", "UNIQUEIDENTIFIER")], EntityId=str(sid), NewParentEntityId=divisions[target])
            run.provenance("location", "Node", key, h, entity_id=str(sid), row_id=r, notes=f"moved from {division} to {target} (owner's markup, W8 card A)")
            moved += 1
        print(f"{a.database}: moved {moved}, already placed {skipped}, not in the mapping {unmapped}; divisions now {sorted(divisions)}")


if __name__ == "__main__":
    main()
