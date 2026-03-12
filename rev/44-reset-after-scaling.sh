#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "===== RESET SCALING CONFIG + MODELS on $ip ====="
  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
echo HOST:\$(hostname) IP:\$(hostname -I | awk '{print \$1}')

CFG=/opt/fl-client/config.env
[ -f \"\$CFG\" ] || touch \"\$CFG\"

python3 - <<'PY'
from pathlib import Path
p=Path('/opt/fl-client/config.env')
lines=p.read_text().splitlines()
out=[]
for line in lines:
    if line.startswith('BYZ_CLIENTS='):
        continue
    if line.startswith('ATTACK_MODE='):
        continue
    if line.startswith('ATTACK_SCALE='):
        continue
    if line.startswith('ATTACK_SIGMA='):
        continue
    if line.startswith('ATTACK_SEED='):
        continue
    if line.startswith('ATTACK_DELTA='):
        continue
    out.append(line)
p.write_text('\n'.join(out).rstrip()+'\n')
print('OK_CLEANED_ATTACK_LINES')
PY

rm -f /opt/fl-client/models/*.npz 2>/dev/null || true

echo '--- remaining attack lines (should be empty) ---'
grep -E '^BYZ_CLIENTS=|^ATTACK_' /opt/fl-client/config.env || true

echo '--- models dir ---'
ls -la /opt/fl-client/models | head -n 5 || true
"
done

echo DONE
