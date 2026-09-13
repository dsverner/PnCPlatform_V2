"""W8 (decision #149): the four gate accounts as platform users on a fresh V2 database — the way #97 seeded them on
`PnCPlatform_V2_DEV` by hand: `personnel.Person_Add` (system account, noted as a gate fixture), `security.User_Add`,
`security.Grant_Add`, all as the SYSTEM actor. Idempotent: a user that exists (by principal name) is left alone.
Writes only through the deployed procedures; the database must be a PnCPlatform_V2_* one (#73, #99).

  python tools/ot/gate_users.py --database PnCPlatform_V2_QA
"""
import argparse, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "docs", "schema", "migration"))
import common   # noqa: E402  (connect / password from dev.local, never printed)

SYSTEM_ACTOR = "00000000-0000-0000-0000-000000000001"
UPN_SUFFIX = "vgsot.internal"
ACCOUNTS = [
    ("pnc-gate-admin",    "Administrator", "Global",      None,                 "PnC gate: Administrator (#97)"),
    ("pnc-gate-approver", "Administrator", "Global",      None,                 "PnC gate: second Administrator, approves what pnc-gate-admin authored (#105)"),
    ("pnc-gate-ro",       "ReadOnly",      "Global",      None,                 "PnC gate: ReadOnly (#97)"),
    ("pnc-gate-hydro",    "PCEngineer",    "NodeSubtree", "Generation · Hydro", "PnC gate: engineer scoped to Generation · Hydro (#97)"),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--database", required=True)
    ap.add_argument("--server", default=common.SERVER)
    ap.add_argument("--also", action="append", default=[], help="an extra domain account as <sAMAccountName>:<RoleCode> (Global) — e.g. VGS01:Administrator, the owner's VM07 account (W8, 2026-09-13)")
    a = ap.parse_args()
    accounts = list(ACCOUNTS) + [(x.split(":")[0], x.split(":")[1], "Global", None, f"Seeded on the owner's request as a QA user for the VM07 vantage point (W8 card T2)") for x in a.also]
    if not a.database.startswith("PnCPlatform_V2_"):
        sys.exit("refusing: the target must be a PnCPlatform_V2_* database (#99)")
    con = common.connect(a.database, a.server); cur = con.cursor()
    for sam, role, scope_kind, scope_name, note in accounts:
        upn = f"{sam}@{UPN_SUFFIX}"
        row = cur.execute("SELECT TOP (1) EntityId FROM security.vUser WHERE UserPrincipalName = ? AND IsEnabled = 1", upn).fetchone()
        if row:
            print(f"  {upn}: exists"); continue
        node = None
        if scope_kind == "NodeSubtree":
            r = cur.execute("SELECT TOP (1) EntityId FROM location.vNode WHERE NodeTypeCode = N'Division' AND Name = ?", scope_name).fetchone()
            if not r:
                sys.exit(f"no Division named {scope_name!r} on {a.database}: deploy the seeds first")
            node = str(r[0])
        person = cur.execute("SET NOCOUNT ON; DECLARE @e UNIQUEIDENTIFIER; EXEC personnel.Person_Add @FirstName=?, @LastName=N'Gate', @DisplayName=?, @Email=?, @IsSystemAccount=1, @Notes=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e",
                             sam, f"{sam} (gate account)", upn, note, SYSTEM_ACTOR).fetchone()[0]
        user = cur.execute("SET NOCOUNT ON; DECLARE @e UNIQUEIDENTIFIER; EXEC security.User_Add @PersonEntityId=?, @UserPrincipalName=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e",
                           str(person), upn, SYSTEM_ACTOR).fetchone()[0]
        cur.execute("SET NOCOUNT ON; DECLARE @e UNIQUEIDENTIFIER; EXEC security.Grant_Add @GranteeKind=N'User', @GranteeEntityId=?, @RoleCode=?, @ScopeKind=?, @ScopeNodeEntityId=?, @GrantedByActorId=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e",
                    str(user), role, scope_kind, node, SYSTEM_ACTOR, SYSTEM_ACTOR).fetchone()
        print(f"  {upn}: created as {role}/{scope_kind}" + (f" on {scope_name}" if scope_name else ""))


if __name__ == "__main__":
    main()
