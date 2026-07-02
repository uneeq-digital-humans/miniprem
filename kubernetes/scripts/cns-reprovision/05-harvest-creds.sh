#!/usr/bin/env bash
# Phase 0.5 — recover deploy credentials from the (stopped) Docker setup into a
# root-only creds.conf. Explicitly authorized by the operator. Reads the backup
# container inspects + docker login config (no docker daemon needed). Values are
# never printed — only which keys were found.
set -euo pipefail
log() { printf '\033[1;36m[creds]\033[0m %s\n' "$*"; }
MIG=/home/admin/migration
BK=/home/admin/prek8s-backup-2026-06-27

sudo python3 - "$MIG" "$BK" <<'PY'
import json, os, sys, base64, glob
mig, bk = sys.argv[1], sys.argv[2]

def env_of(path):
    try:
        d = json.load(open(path))
        if isinstance(d, list): d = d[0]
        return dict(e.split("=",1) for e in d["Config"]["Env"] if "=" in e)
    except Exception:
        return {}

def find(var, files):
    for f in files:
        v = env_of(f).get(var)
        if v: return v
    return ""

g = lambda *names: [os.path.join(bk, n) for n in names]
ngc = find("NGC_API_KEY", sorted(glob.glob(f"{bk}/inspect-*.json")))
pkey = find("DHOP_APIKEY", g("inspect-renny.json"))
tid  = find("DHOP_TENANTID", g("inspect-renny.json"))

huser = hpass = ""
try:
    cfg = json.load(open("/root/.docker/config.json"))
    auth = cfg.get("auths", {}).get("cr.uneeq.io", {}).get("auth", "")
    if auth:
        dec = base64.b64decode(auth).decode()
        huser, hpass = dec.split(":", 1)
except Exception:
    pass

# Single-quote for the shell so $-containing values (e.g. Harbor robot names like
# 'robot$uneeq+x') are NOT expanded when sourced under `set -u`.
def shq(s): return "'" + str(s).replace("'", "'\\''") + "'"
out = (f"export NGC_API_KEY={shq(ngc)}\n"
       f"export HARBOR_USERNAME={shq(huser)}\n"
       f"export HARBOR_PASSWORD={shq(hpass)}\n"
       f"export PLATFORM_KEY={shq(pkey)}\n"
       f"export TENANT_ID={shq(tid)}\n")
open(f"{mig}/creds.conf", "w").write(out)
os.chmod(f"{mig}/creds.conf", 0o600)
for k,v in [("NGC_API_KEY",ngc),("HARBOR_USERNAME",huser),("HARBOR_PASSWORD",hpass),
            ("PLATFORM_KEY",pkey),("TENANT_ID",tid)]:
    print(f"  {k}={'<set>' if v else '<EMPTY>'}")
PY
sudo chown "$(id -un)":"$(id -gn)" "$MIG/creds.conf"
chmod 600 "$MIG/creds.conf"
log "creds.conf written (owner-only, readable by the deploy user)."
