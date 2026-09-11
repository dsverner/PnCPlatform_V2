"""
package_release.py — the release artifact set (PLATFORM-ARCHITECTURE §9.2, decision 249).

Produced on the build machine, never on an OT server:
  dist/<version>/PnCPlatform.dacpac      the schema (built from docs/schema/ddl)
  dist/<version>/app/                     the published site (PnC.Api, framework-dependent, win-x64) + wwwroot
  dist/<version>/PnC.Api-<version>.zip    the same, zipped
  dist/<version>/sbom.json                every server package (direct + transitive) for PnC.Api and PnC.Api.Smoke;
                                          the browser tier carries no packages (decision 242)
  dist/<version>/release.json             version, commit, built-at, SHA-256 of dacpac / zip / sbom
  dist/<version>/RELEASE-<version>.md     the release document skeleton (sections to fill before promotion)

Version = <DacVersion> of the sqlproj. Nothing is written to any database: deploy.py --package dist/<version>
passes the package hash to record_release.py so platform.Release carries both hashes.

Usage: python tools/package_release.py [--out dist] [--configuration Release]
"""
import argparse, hashlib, json, os, re, shutil, subprocess, sys, zipfile
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DDL = os.path.join(ROOT, "docs", "schema", "ddl")
DOTNET = os.environ.get("DOTNET", r"C:\Program Files\dotnet\dotnet.exe" if os.name == "nt" else "dotnet")


def run(args, cwd=ROOT, capture=False):
    print("+ " + " ".join(args))
    r = subprocess.run(args, cwd=cwd, text=True, capture_output=capture)
    if r.returncode != 0:
        if capture:
            print(r.stdout); print(r.stderr)
        sys.exit(f"failed: {args[0]}")
    return r.stdout if capture else None


def dac_version():
    for f in os.listdir(DDL):
        if f.endswith(".sqlproj"):
            m = re.search(r"<DacVersion>([^<]+)</DacVersion>", open(os.path.join(DDL, f), encoding="utf-8").read())
            if m:
                return m.group(1)
    sys.exit("no <DacVersion> in the sqlproj")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def commit():
    try:
        return subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True, capture_output=True).stdout.strip()
    except OSError:
        return None


def sbom(projects, configuration):
    """dotnet list package --include-transitive --format json, per project, folded into one list."""
    packages = {}
    for proj in projects:
        out = run([DOTNET, "list", os.path.join(ROOT, proj), "package", "--include-transitive", "--format", "json"], capture=True)
        data = json.loads(out[out.index("{"):])
        for p in data.get("projects", []):
            for fw in p.get("frameworks", []):
                for kind in ("topLevelPackages", "transitivePackages"):
                    for pkg in fw.get(kind, []):
                        key = (pkg["id"], pkg.get("resolvedVersion") or pkg.get("requestedVersion"))
                        packages.setdefault(key, {"id": key[0], "version": key[1], "direct": kind == "topLevelPackages", "usedBy": []})
                        packages[key]["usedBy"].append(os.path.basename(proj))
                        if kind == "topLevelPackages":
                            packages[key]["direct"] = True
    return sorted(packages.values(), key=lambda x: x["id"].lower())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "dist"))
    ap.add_argument("--configuration", default="Release")
    ap.add_argument("--no-dacpac", action="store_true", help="reuse docs/schema/ddl/bin/Debug/PnCPlatform.dacpac (deploy.py has just built it)")
    a = ap.parse_args()
    version = dac_version()
    out = os.path.join(a.out, version)
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(os.path.join(out, "app"))
    print(f"release {version} -> {out}")

    # 1. the DACPAC
    if a.no_dacpac:
        src = os.path.join(DDL, "bin", "Debug", "PnCPlatform.dacpac")
    else:
        env = dict(os.environ, DOTNET_ROLL_FORWARD="Major")
        print("+ dotnet build (sqlproj)")
        r = subprocess.run([DOTNET, "build", "-c", "Debug", "-v", "q", "-nologo"], cwd=DDL, text=True, env=env)
        if r.returncode != 0:
            sys.exit("sqlproj build failed")
        src = os.path.join(DDL, "bin", "Debug", "PnCPlatform.dacpac")
    dacpac = os.path.join(out, "PnCPlatform.dacpac")
    shutil.copyfile(src, dacpac)

    # 2. the application package (framework-dependent: the OT server carries the shared framework, PLATFORM-ARCHITECTURE §2.1)
    run([DOTNET, "publish", os.path.join(ROOT, "src", "PnC.Api", "PnC.Api.csproj"), "-c", a.configuration, "-r", "win-x64", "--self-contained", "false", "-o", os.path.join(out, "app"), "-nologo", "-v", "q"])
    for f in ("appsettings.Local.json", "appsettings.Development.json"):
        p = os.path.join(out, "app", f)
        if os.path.exists(p):
            os.remove(p)   # never a developer configuration in the package (§1.4 step 3)
    zip_path = os.path.join(out, f"PnC.Api-{version}.zip")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for dp, _, fs in os.walk(os.path.join(out, "app")):
            for f in fs:
                full = os.path.join(dp, f)
                z.write(full, os.path.relpath(full, os.path.join(out, "app")))

    # 2b. the user-journey smoke, self-contained (win-x64) under tools/: the Application VM runs it under Windows
    #     authentication with no SDK and no runtime of its own (decision 256; PLATFORM-ARCHITECTURE section 9.3)
    smoke_dir = os.path.join(out, "tools", "PnC.Api.Smoke")
    run([DOTNET, "publish", os.path.join(ROOT, "src", "PnC.Api.Smoke", "PnC.Api.Smoke.csproj"), "-c", a.configuration, "-r", "win-x64", "--self-contained", "true",
         "-p:PublishSingleFile=true", "-p:DebugType=none", "-o", smoke_dir, "-nologo", "-v", "q"])
    smoke_exe = os.path.join(smoke_dir, "PnC.Api.Smoke.exe")

    # 3. the SBOM
    packages = sbom([os.path.join("src", "PnC.Api", "PnC.Api.csproj"), os.path.join("src", "PnC.Api.Smoke", "PnC.Api.Smoke.csproj")], a.configuration)
    sbom_path = os.path.join(out, "sbom.json")
    with open(sbom_path, "w", encoding="utf-8") as f:
        json.dump({"version": version, "generatedAt": datetime.now(timezone.utc).isoformat(), "format": "pnc-sbom-1",
                   "serverPackages": packages, "sharedFramework": "Microsoft.AspNetCore.App / Microsoft.NETCore.App (net10.0, on the host)",
                   "browserPackages": [], "note": "decision 239: one direct package; decision 242: the shell carries no browser packages"}, f, indent=2)

    # 4. release.json + the release document skeleton
    rel = {"version": version, "commit": commit(), "builtAt": datetime.now(timezone.utc).isoformat(), "configuration": a.configuration,
           "artifacts": {"dacpac": {"file": os.path.basename(dacpac), "sha256": sha256(dacpac)},
                         "package": {"file": os.path.basename(zip_path), "sha256": sha256(zip_path)},
                         "smoke": {"file": os.path.relpath(smoke_exe, out).replace(os.sep, "/"), "sha256": sha256(smoke_exe)},
                         "sbom": {"file": "sbom.json", "sha256": sha256(sbom_path)}}}
    with open(os.path.join(out, "release.json"), "w", encoding="utf-8") as f:
        json.dump(rel, f, indent=2)
    doc = os.path.join(out, f"RELEASE-{version}.md")
    with open(doc, "w", encoding="utf-8") as f:
        f.write(f"""# Release {version}

Built {rel['builtAt']} from commit `{rel['commit']}` (PLATFORM-ARCHITECTURE §9.2, decision 229).

| Artifact | File | SHA-256 |
|---|---|---|
| DACPAC | `{rel['artifacts']['dacpac']['file']}` | `{rel['artifacts']['dacpac']['sha256']}` |
| Application package | `{rel['artifacts']['package']['file']}` | `{rel['artifacts']['package']['sha256']}` |
| Journey smoke (self-contained, for the Application VM) | `{rel['artifacts']['smoke']['file']}` | `{rel['artifacts']['smoke']['sha256']}` |
| SBOM | `sbom.json` | `{rel['artifacts']['sbom']['sha256']}` |

## What changed
- Schema steps: _fill in_
- Procedures: _fill in_
- Definitions seeded: _fill in_

## Host-baseline contribution (§8.1)
_fill in: services, ports, accounts the package needs on the application server_

## Register delta (§1.2)
_fill in: new or changed flows, or "none"_

## Runbook delta (§9.4)
_fill in, or "none"_

## Deployment order
1. `deploy.py` (DACPAC: build, publish, regenerate, publish, check, smoke)
2. the application package (`app/` or the zip) to the IIS site; configuration naming OT/DMZ endpoints only
3. `/health`
4. the `PlatformDeployment` record with the checklist outcome (§1.4 step 7)
""")
    print(json.dumps(rel, indent=2))
    print(f"SBOM: {len(packages)} server packages ({sum(1 for p in packages if p['direct'])} direct)")
    print("OK")


if __name__ == "__main__":
    main()
