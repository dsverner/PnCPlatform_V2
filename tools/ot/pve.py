"""Proxmox VE client for the OT hosts (the VGS-VM02 install and the gates) (docs/runbook/VM02-SECOND-SITE.md, decision #89),
over the documented path: Proxmox API + QEMU guest agent (predecessor docs/working-agreements/qa-environment.md:21).
Credentials from the predecessor's dev.local (PVE_USER / PVE_PWD); never printed.

  python pve.py inventory                      read-only: VMs, agent ping, IIS sites/bindings/pools on VM 101
  python pve.py chunktest                      find the largest file-write chunk the API accepts (temp file, removed)
  python pve.py transfer <local file> <guest path> [chunk_kib]   chunked upload, assembled and SHA-256-verified in the guest
  python pve.py ps <script.ps1> [vmid]         run a PowerShell script file in the guest, print its output
  python pve.py ping|exec-test|reboot <vmid>   guest-agent reachability; reboot (W2 card A2) when the agent stops answering
  python pve.py sh <vmid> "<cmd>"              a shell line in a Linux guest (the Samba DC, VM 105)
  python pve.py lxc | put <local> <guest path>  containers; one small file through the file channel
"""
import base64, hashlib, json, os, ssl, sys, time, urllib.parse, urllib.request

HOST = "https://10.10.15.60:8006"
NODE = "pve-ryzen"
VM02 = 101
CTX = ssl.create_default_context(); CTX.check_hostname = False; CTX.verify_mode = ssl.CERT_NONE

def creds():
    d = {}
    for line in open(r"C:\Projects\PnCPlatform\dev.local", encoding="utf-8"):
        if "=" in line: k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d["PVE_USER"], d["PVE_PWD"]

class Pve:
    def __init__(self):
        user, pwd = creds()
        data = urllib.parse.urlencode({"username": user, "password": pwd}).encode()
        r = self._raw("POST", "/api2/json/access/ticket", data, {})
        self.ticket = r["ticket"]; self.csrf = r["CSRFPreventionToken"]
    def _raw(self, method, path, data, headers):
        req = urllib.request.Request(HOST + path, data=data, method=method, headers=headers)
        with urllib.request.urlopen(req, context=CTX, timeout=120) as resp:
            return json.loads(resp.read().decode())["data"]
    def _h(self, csrf=False):
        h = {"Cookie": "PVEAuthCookie=" + self.ticket}
        if csrf: h["CSRFPreventionToken"] = self.csrf
        return h
    def get(self, path, **q):
        return self._raw("GET", path + ("?" + urllib.parse.urlencode(q) if q else ""), None, self._h())
    def post(self, path, **form):
        items = []
        for k, v in form.items():
            if isinstance(v, list): items += [(k, x) for x in v]
            else: items.append((k, v))
        return self._raw("POST", path, urllib.parse.urlencode(items).encode(), self._h(csrf=True))
    def ping(self, vmid): return self.post(f"/api2/json/nodes/{NODE}/qemu/{vmid}/agent/ping")
    def exec(self, vmid, cmd, timeout=180):
        pid = self.post(f"/api2/json/nodes/{NODE}/qemu/{vmid}/agent/exec", command=cmd)["pid"]
        t0 = time.time()
        while True:
            st = self.get(f"/api2/json/nodes/{NODE}/qemu/{vmid}/agent/exec-status", pid=pid)
            if st.get("exited"): return st
            if time.time() - t0 > timeout: raise TimeoutError(f"pid {pid} still running after {timeout}s")
            time.sleep(1)
    def ps(self, vmid, script, timeout=180):
        enc = base64.b64encode(script.encode("utf-16-le")).decode()
        st = self.exec(vmid, ["powershell.exe", "-NoProfile", "-NonInteractive", "-EncodedCommand", enc], timeout)
        return st.get("exitcode"), st.get("out-data", ""), st.get("err-data", "")
    def file_write(self, vmid, path, data: bytes):
        return self.post(f"/api2/json/nodes/{NODE}/qemu/{vmid}/agent/file-write", file=path, content=base64.b64encode(data).decode(), encode=0)

def inventory(p):
    for v in sorted(p.get(f"/api2/json/nodes/{NODE}/qemu"), key=lambda x: x["vmid"]): print(v["vmid"], v.get("name"), v.get("status"))
    print("ping 101:", p.ping(VM02))
    code, out, err = p.ps(VM02, "$ProgressPreference='SilentlyContinue'; whoami; $env:COMPUTERNAME; Import-Module WebAdministration; Get-Website | Select-Object name,state,physicalPath,applicationPool | Format-Table -AutoSize | Out-String -Width 200; Get-WebBinding | Select-Object protocol,bindingInformation,certificateHash | Format-Table -AutoSize | Out-String -Width 200; Get-ChildItem IIS:\\AppPools | Select-Object name,state | Format-Table -AutoSize | Out-String -Width 120")
    print("exit", code); print(out); print(err[:500])

def chunktest(p):
    for kib in (24, 32, 40, 44):
        data = os.urandom(kib * 1024); h = hashlib.sha256(data).hexdigest()
        try:
            p.file_write(VM02, r"C:\Windows\Temp\pnc-fw-test.bin", data)
            code, out, err = p.ps(VM02, r"(Get-FileHash C:\Windows\Temp\pnc-fw-test.bin -Algorithm SHA256).Hash.ToLower(); Remove-Item C:\Windows\Temp\pnc-fw-test.bin -Force", timeout=60)
            print(f"{kib} KiB: ok, hash match = {out.split()[0] == h if out else None}")
        except Exception as e:
            print(f"{kib} KiB: failed: {str(e)[:120]}")

def transfer(p, local, guest_path, chunk_kib=32):
    data = open(local, "rb").read(); h = hashlib.sha256(data).hexdigest()
    chunk = chunk_kib * 1024; n = (len(data) + chunk - 1) // chunk
    gdir = guest_path.rsplit("\\", 1)[0]
    p.ps(VM02, f"New-Item -ItemType Directory -Force '{gdir}\\parts' | Out-Null; Remove-Item '{gdir}\\parts\\*' -Force -ErrorAction SilentlyContinue", timeout=60)
    print(f"{local}: {len(data)} bytes, sha256 {h}, {n} chunks of {chunk_kib} KiB")
    for i in range(n):
        p.file_write(VM02, f"{gdir}\\parts\\{i:05d}.part", data[i*chunk:(i+1)*chunk])
        if i % 20 == 0 or i == n - 1: print(f"  chunk {i+1}/{n}")
    script = f"""
$parts = Get-ChildItem '{gdir}\\parts\\*.part' | Sort-Object Name
$out = [System.IO.File]::Create('{guest_path}')
foreach ($f in $parts) {{ $b = [System.IO.File]::ReadAllBytes($f.FullName); $out.Write($b, 0, $b.Length) }}
$out.Close()
Remove-Item '{gdir}\\parts' -Recurse -Force
(Get-Item '{guest_path}').Length
(Get-FileHash '{guest_path}' -Algorithm SHA256).Hash.ToLower()
"""
    code, out, err = p.ps(VM02, script, timeout=180)
    lines = out.split()
    ok = len(lines) >= 2 and lines[0] == str(len(data)) and lines[1] == h
    print(f"assembled in guest: length {lines[0] if lines else '?'}, sha256 {lines[1] if len(lines) > 1 else '?'} -> {'VERIFIED' if ok else 'MISMATCH'}")
    if err: print("ERR:", err[:400])
    return ok

def run_ps(p, path, vmid=VM02):
    code, out, err = p.ps(vmid, open(path, encoding="utf-8").read(), timeout=600)
    print("exit", code); print(out)
    if err: print("ERR:", err[:2000])
    return code

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "inventory"
    p = Pve()
    if cmd == "inventory": inventory(p)
    elif cmd == "chunktest": chunktest(p)
    elif cmd == "transfer": sys.exit(0 if transfer(p, sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 32) else 1)
    elif cmd == "ps": sys.exit(run_ps(p, sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else VM02) or 0)
    elif cmd == "ping":  # read-only: is the guest agent on this VM reachable, and what does the API say if not
        import urllib.error
        try: print("ping", sys.argv[2], "->", p.ping(int(sys.argv[2])))
        except urllib.error.HTTPError as e: print("ping", sys.argv[2], "-> HTTP", e.code, e.read().decode()[:300])
    elif cmd == "sh":  # run a shell command line in a Linux guest through its agent: python pve.py sh <vmid> "<command>"
        st = p.exec(int(sys.argv[2]), ["/bin/sh", "-c", sys.argv[3]], timeout=180)
        print("exit", st.get("exitcode")); print(st.get("out-data", "")); print(st.get("err-data", "")[:800])
    elif cmd == "lxc":  # read-only: the node's containers
        for c in sorted(p.get(f"/api2/json/nodes/{NODE}/lxc"), key=lambda x: int(x["vmid"])): print(c["vmid"], c.get("name"), c.get("status"))
    elif cmd == "reboot":  # W2 card A2: reboot a VM whose guest agent has stopped answering commands, then wait for the agent
        vm = int(sys.argv[2])
        print("reboot", vm, "->", p.post(f"/api2/json/nodes/{NODE}/qemu/{vm}/status/reboot", timeout=120))
        import urllib.error
        for i in range(36):
            time.sleep(10)
            try:
                p.ping(vm); st = p.exec(vm, ["cmd.exe", "/c", "ver"], timeout=60)
                print(f"agent back after ~{(i+1)*10}s:", (st.get("out-data") or "").strip()[:80]); break
            except Exception as e: last = str(e)[:80]
        else: print("agent still not answering after 6 min:", last)
    elif cmd == "exec-test":  # read-only: can the guest agent on this VM run a trivial command; and its agent config
        import urllib.error
        vm = int(sys.argv[2])
        cfg = p.get(f"/api2/json/nodes/{NODE}/qemu/{vm}/config")
        print("agent config:", cfg.get("agent"), "| ostype:", cfg.get("ostype"))
        for cmdline in (["cmd.exe", "/c", "ver"], ["powershell.exe", "-NoProfile", "-Command", "$env:COMPUTERNAME"]):
            try:
                st = p.exec(vm, cmdline, timeout=90)
                print(cmdline[0], "->", "exit", st.get("exitcode"), (st.get("out-data") or "").strip()[:120], (st.get("err-data") or "").strip()[:120])
            except urllib.error.HTTPError as e: print(cmdline[0], "-> HTTP", e.code, e.read().decode()[:200])
            except Exception as e: print(cmdline[0], "->", str(e)[:200])
    elif cmd == "put":   # one small file, written through the agent's file channel only; nothing is executed
        data = open(sys.argv[2], "rb").read()
        if len(data) > 40 * 1024: sys.exit("put is for files under 40 KiB; use transfer")
        p.file_write(VM02, sys.argv[3], data); print(f"wrote {len(data)} bytes to {sys.argv[3]} on VM02")
    else: sys.exit("unknown command")
