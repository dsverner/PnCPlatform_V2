"""
Records a platform release and its deployment (PLATFORM-ARCHITECTURE §8.1, §9.2; PROCEDURES.md #42).
Called by deploy.py after a successful publish (and smoke, when run), or by hand:

    python tools/record_release.py [--server ..] [--database ..] [--outcome Succeeded|Failed|RolledBack]
                                   [--smoke-checks N] [--notes ..]

Version: the <DacVersion> of PnCPlatform.sqlproj. Hash: SHA-256 of bin/Debug/PnCPlatform.dacpac.
Environment: from the database name suffix (_DEV, _QA, _TRAIN; otherwise PROD). The Release row is
appended once per version (a re-deploy of the same version cites the existing row); a Deployment row
is appended every time. Both through the generated _Append procedures — never a direct insert.
"""
import argparse, hashlib, os, re, sys
import pyodbc

HERE = os.path.dirname(os.path.abspath(__file__))
DDL = os.path.abspath(os.path.join(HERE, ".."))
ROOT = os.path.abspath(os.path.join(DDL, "..", "..", ".."))
SYSTEM_ACTOR = "00000000-0000-0000-0000-000000000001"


def password():
    if os.environ.get("PNC_DEV_PWD"):
        return os.environ["PNC_DEV_PWD"]
    for line in open(os.path.join(ROOT, "dev.local"), encoding="utf-8"):
        if line.startswith("PNC_DEV_PWD="):
            return line.split("=", 1)[1].strip()
    sys.exit("no password")


def dac_version():
    text = open(os.path.join(DDL, "PnCPlatform.sqlproj"), encoding="utf-8").read()
    m = re.search(r"<DacVersion>([^<]+)</DacVersion>", text)
    if not m:
        sys.exit("PnCPlatform.sqlproj has no <DacVersion>")
    return m.group(1).strip()


def dacpac_hash():
    p = os.path.join(DDL, "bin", "Debug", "PnCPlatform.dacpac")
    with open(p, "rb") as f:
        return hashlib.sha256(f.read()).digest()


def package_hash(arg, version):
    """None, a 64-hex digest, or a release.json whose version must match the DacVersion."""
    if not arg:
        return None
    if os.path.isfile(arg):
        import json
        rel = json.load(open(arg, encoding="utf-8"))
        if rel.get("version") != version:
            sys.exit(f"release.json is for {rel.get('version')}, the sqlproj is {version}")
        arg = rel["artifacts"]["package"]["sha256"]
    if not re.fullmatch(r"[0-9a-fA-F]{64}", arg):
        sys.exit("--package-hash must be a SHA-256 hex digest or a release.json path")
    return bytes.fromhex(arg)


def environment(database):
    for suffix, env in (("_DEV", "DEV"), ("_QA", "QA"), ("_TRAIN", "TRAIN")):
        if database.upper().endswith(suffix):
            return env
    return "PROD"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default="10.10.70.25")
    ap.add_argument("--database", default="PnCPlatform_DEV")
    ap.add_argument("--outcome", default="Succeeded", choices=["Succeeded", "Failed", "RolledBack"])
    ap.add_argument("--smoke-checks", type=int, default=None)
    ap.add_argument("--notes", default=None)
    ap.add_argument("--package-hash", default=None, help="SHA-256 (hex) of the application package, or the path of a dist/<version>/release.json (tools/package_release.py)")
    a = ap.parse_args()
    version, digest, env = dac_version(), dacpac_hash(), environment(a.database)
    package = package_hash(a.package_hash, version)
    con = pyodbc.connect(f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={a.server};DATABASE={a.database};UID=dev_pnc;PWD={password()};TrustServerCertificate=yes", autocommit=True, timeout=15)
    cur = con.cursor()
    row = cur.execute("SELECT ReleaseId, DacpacHash FROM platform.vRelease WHERE Version = ?", version).fetchone()
    if row is None:
        rid = cur.execute("DECLARE @id BIGINT, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC platform.Release_Append @Version=?, @ReleasedAt=@t, @DacpacHash=?, @PackageHash=?, @RecordedByActorId=?, @ReleaseId=@id OUTPUT; SELECT @id",
                          version, pyodbc.Binary(digest), pyodbc.Binary(package) if package else None, SYSTEM_ACTOR).fetchone()[0]
        print(f"  release {version} recorded (ReleaseId {rid})")
    else:
        rid = row[0]
        if bytes(row[1]) != digest:
            print(f"  WARNING: release {version} already recorded with a different DACPAC hash — bump <DacVersion> for a changed schema")
    did = cur.execute("DECLARE @id BIGINT, @t DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC platform.Deployment_Append @ReleaseId=?, @Environment=?, @DatabaseName=?, @DeployedAt=@t, @DeployedByActorId=?, @Outcome=?, @SmokeChecks=?, @Notes=?, @DeploymentId=@id OUTPUT; SELECT @id",
                      rid, env, a.database, SYSTEM_ACTOR, a.outcome, a.smoke_checks, a.notes).fetchone()[0]
    print(f"  deployment of {version} to {env} ({a.database}) recorded: {a.outcome} (DeploymentId {did})")


if __name__ == "__main__":
    main()
