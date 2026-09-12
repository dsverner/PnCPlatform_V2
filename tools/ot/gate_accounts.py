"""W2 card A1 (standing authorisation, 2026-09-12): the three gate accounts on vgsot.internal, created through the
Samba domain controller VGS-VM05 (Proxmox VM 105) with samba-tool, passwords generated here and written ONLY to the
predecessor's gitignored dev.local (PNC_GATE_ADMIN_PWD, PNC_GATE_RO_PWD, PNC_GATE_HYDRO_PWD; W3 adds
PNC_GATE_APPROVER_PWD for the second Administrator the Author/Approve segregation needs). Idempotent: an account
that exists is left alone (its password on file is kept). Nothing is printed but names and outcomes."""
import os, secrets, string, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pve

DEV_LOCAL = r"C:\Projects\PnCPlatform\dev.local"
ACCOUNTS = [("pnc-gate-admin", "PNC_GATE_ADMIN_PWD", "PnC gate: Administrator"),
            ("pnc-gate-ro", "PNC_GATE_RO_PWD", "PnC gate: ReadOnly"),
            ("pnc-gate-hydro", "PNC_GATE_HYDRO_PWD", "PnC gate: Hydro-scoped engineer"),
            ("pnc-gate-approver", "PNC_GATE_APPROVER_PWD", "PnC gate: second Administrator (W3, approves what pnc-gate-admin authored)")]
ALPHABET = string.ascii_letters + string.digits

def read_env():
    d = {}
    for line in open(DEV_LOCAL, encoding="utf-8"):
        if "=" in line and not line.startswith("#"): k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d

p = pve.Pve()
env = read_env()
for sam, key, desc in ACCOUNTS:
    st = p.exec(105, ["/bin/sh", "-c", f"samba-tool user show {sam} >/dev/null 2>&1 && echo EXISTS || echo ABSENT"], timeout=60)
    state = (st.get("out-data") or "").strip()
    if state == "EXISTS" and key in env:
        print(f"{sam}: exists on the domain, password on file — left alone"); continue
    pwd = env.get(key) or "".join(secrets.choice(ALPHABET) for _ in range(24))
    if state == "EXISTS":
        # exists but no password on file: set a fresh one so the file and the domain agree
        st = p.exec(105, ["samba-tool", "user", "setpassword", sam, "--newpassword", pwd], timeout=60)
        ok = st.get("exitcode") == 0
        print(f"{sam}: existed with no password on file — password reset: {'ok' if ok else 'FAILED ' + (st.get('err-data') or '')[:200]}")
    else:
        # the CN is built from the names; each account needs its own (the first run collided on "PnC Gate")
        st = p.exec(105, ["samba-tool", "user", "create", sam, pwd, "--given-name", "PnC", "--surname", sam, "--description", desc, "--mail-address", f"{sam}@vgsot.internal"], timeout=60)
        ok = st.get("exitcode") == 0
        print(f"{sam}: create: {'ok' if ok else 'FAILED ' + (st.get('err-data') or st.get('out-data') or '')[:300]}")
    if ok:
        p.exec(105, ["samba-tool", "user", "setexpiry", sam, "--noexpiry"], timeout=60)
        if key not in env:
            with open(DEV_LOCAL, "a", encoding="utf-8") as f: f.write(f"{key}={pwd}\n")
            env[key] = pwd
            print(f"  {key} written to dev.local")
st = p.exec(105, ["/bin/sh", "-c", "samba-tool user list | grep -i pnc-gate"], timeout=60)
print("domain now has:", (st.get("out-data") or "").split())
