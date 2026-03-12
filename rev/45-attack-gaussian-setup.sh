#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

BYZ_CLIENTS="${BYZ_CLIENTS:-edge-client-1 edge-client-6 edge-client-11 edge-client-16}"
ATTACK_MODE="${ATTACK_MODE:-gaussian}"
ATTACK_SIGMA="${ATTACK_SIGMA:-0.5}"
ATTACK_SEED="${ATTACK_SEED:-}"

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "===== SETUP GAUSSIAN on $ip ====="
  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" 'bash -s' <<REMOTE
set -euo pipefail
CFG=/opt/fl-client/config.env
[ -f "\$CFG" ] || touch "\$CFG"

python3 - <<'PY'
from pathlib import Path
p=Path("/opt/fl-client/config.env")
lines=p.read_text().splitlines()
kv={}
for l in lines:
    if "=" in l and not l.lstrip().startswith("#"):
        k,v=l.split("=",1)
        kv[k.strip()]=v.strip()

kv["BYZ_CLIENTS"] = '"'"$BYZ_CLIENTS"'"'
kv["ATTACK_MODE"] = "gaussian"
kv["ATTACK_SIGMA"] = "'"$ATTACK_SIGMA"'"
seed="'"$ATTACK_SEED"'".strip()
if seed:
    kv["ATTACK_SEED"] = seed
else:
    kv.pop("ATTACK_SEED", None)

out=[]
for k in sorted(kv.keys()):
    out.append(f"{k}={kv[k]}")
p.write_text("\n".join(out).rstrip()+"\n")
print("OK_SET")
PY

echo HOST:\$(hostname) IP:\$(hostname -I | awk '{print \$1}')
grep -E '^(BYZ_CLIENTS|ATTACK_MODE|ATTACK_SIGMA|ATTACK_SEED)=' /opt/fl-client/config.env || true
REMOTE
done

echo DONE
