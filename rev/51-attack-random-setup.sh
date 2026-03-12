#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

BYZ_CLIENTS="${BYZ_CLIENTS:-edge-client-1 edge-client-6 edge-client-11 edge-client-16}"
ATTACK_MODE="${ATTACK_MODE:-random}"
ATTACK_SEED="${ATTACK_SEED:-42}"

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "===== SETUP RANDOM on $ip ====="
  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" 'bash -s' <<REMOTE
set -euo pipefail
CFG=/opt/fl-client/config.env
[ -f "\$CFG" ] || touch "\$CFG"

python3 - <<PY
from pathlib import Path
p=Path("/opt/fl-client/config.env")
lines=p.read_text().splitlines()
out=[]
drop=("BYZ_CLIENTS=","ATTACK_MODE=","ATTACK_SEED=","ATTACK_SCALE=","ATTACK_SIGMA=","ATTACK_DELTA=")
for line in lines:
    if any(line.startswith(d) for d in drop):
        continue
    out.append(line)
out.append('BYZ_CLIENTS="'+"""${BYZ_CLIENTS}"""+'"')
out.append('ATTACK_MODE='+"${ATTACK_MODE}")
out.append('ATTACK_SEED='+"${ATTACK_SEED}")
p.write_text("\n".join([x for x in out if x.strip()])+"\n")
print("OK_SET")
PY

echo HOST:\$(hostname) IP:\$(hostname -I | awk '{print \$1}')
grep -E '^BYZ_CLIENTS=|^ATTACK_MODE=|^ATTACK_SEED=' /opt/fl-client/config.env || true
REMOTE
done
echo DONE
