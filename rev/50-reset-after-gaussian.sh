#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "===== RESET GAUSSIAN CONFIG + MODELS on $ip ====="
  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" 'bash -s' <<'REMOTE'
set -euo pipefail
echo HOST:$(hostname) IP:$(hostname -I | awk '{print $1}')

CFG=/opt/fl-client/config.env
[ -f "$CFG" ] || touch "$CFG"

python3 - <<'PY'
from pathlib import Path
p=Path("/opt/fl-client/config.env")
lines=p.read_text().splitlines()
out=[]
drop_prefixes=("BYZ_CLIENTS=","ATTACK_MODE=","ATTACK_SCALE=","ATTACK_SIGMA=","ATTACK_SEED=","ATTACK_DELTA=")
for line in lines:
    if any(line.startswith(px) for px in drop_prefixes):
        continue
    out.append(line)
p.write_text("\n".join(out).rstrip()+"\n")
print("OK_CLEANED_ATTACK_LINES")
PY

echo "--- remaining attack lines (should be empty) ---"
grep -E '^(BYZ_CLIENTS|ATTACK_MODE|ATTACK_SCALE|ATTACK_SIGMA|ATTACK_SEED|ATTACK_DELTA)=' /opt/fl-client/config.env || true

rm -f /opt/fl-client/models/*.npz 2>/dev/null || true
echo "--- models dir ---"
ls -la /opt/fl-client/models | head -n 6 || true
REMOTE
done

echo DONE
